// =====================================================================
// yookassa-create-payment
//
// Создаёт платёж в YooKassa. Поддерживает четыре сценария:
//
//   A. С редиректом на YooKassa (как обычно):
//      POST { kind: 'subscription' | 'service_slot', service_id?, return_url? }
//      → клиент получает confirmation_url и открывает его в браузере.
//
//   B. С редиректом + сохранением карты:
//      POST { ..., save_card: true }
//      → после успешной оплаты webhook ловит payment_method.saved=true
//        и кладёт её в saved_payment_methods.
//
//   C. Списание с уже сохранённой карты (без редиректа):
//      POST { kind, service_id?, payment_method_id }
//      → платёж списывается мгновенно. confirmation_url в ответе пуст.
//
//   D. Привязка карты (card_binding):
//      POST { kind: 'card_binding', return_url? }
//      → списываем 1 ₽ с обязательным `save_payment_method=true`,
//        webhook сохранит карту в `saved_payment_methods` и инициирует
//        авто-рефанд (см. yookassa-webhook). Юзер по факту ничего не
//        теряет, но получает привязанную карту для будущих оплат.
//        YooKassa не поддерживает «нулевые» payment_method-binding
//        запросы, минимум — 1 ₽, поэтому такая обходная схема.
//
// kind=subscription:  490₽ — продлевает подписку на 30 дней
// kind=service_slot:   99₽ — оплата публикации конкретной услуги
//                            (требуется service_id, услуга должна
//                            принадлежать юзеру и не быть оплаченной)
// kind=card_binding:    1₽ — техническая транзакция для сохранения
//                            карты, рефандится автоматически.
//
// Триггеры в БД (apply_payment_success / snapshot_service_in_payment)
// сами обработают эффекты, когда yookassa-webhook поставит
// status='succeeded'. Для card_binding apply_payment_success — no-op
// (нет ветки subscription/service_slot), эффект только в save card.
// =====================================================================

const YOOKASSA_SHOP_ID = Deno.env.get("YOOKASSA_SHOP_ID") ?? "";
const YOOKASSA_SECRET_KEY = Deno.env.get("YOOKASSA_SECRET_KEY") ?? "";
// Цены тянем из таблицы `settings` (см. getPrice ниже). Раньше брали
// из env-vars `YOOKASSA_PRICE_SUBSCRIPTION` / `YOOKASSA_PRICE_SERVICE_SLOT`,
// но UI читает цены из `settings` через SettingsService — расхождение
// приводило к ситуации «UI показывает 1000 ₽, ЮКасса видит 99 ₽».
// Fallback'и оставляем на случай, если строки в settings нет (например,
// первая инициализация БД до накатывания seed'а).
const PRICE_SUBSCRIPTION_FALLBACK = 1000;
const PRICE_SERVICE_SLOT_FALLBACK = 1000;

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const JWT_SECRET = Deno.env.get("JWT_SECRET") ?? "";

// По умолчанию редиректим на нашу же Edge Function `payment-return`,
// которая отдаёт публичную HTML-страницу (без Basic Auth корневого
// домена) и пробует открыть deeplink приложения. Клиент может передать
// собственный return_url, тогда default не используется.
const RETURN_URL_DEFAULT = Deno.env.get("YOOKASSA_RETURN_URL_DEFAULT")
  ?? `${SUPABASE_URL.replace(/\/$/, "")}/functions/v1/payment-return`;

if (!YOOKASSA_SHOP_ID || !YOOKASSA_SECRET_KEY) {
  console.error("[create-payment] YOOKASSA_SHOP_ID / SECRET_KEY не заданы");
}

function base64UrlDecode(s: string): Uint8Array {
  const norm = s.replace(/-/g, "+").replace(/_/g, "/");
  const padded = norm + "=".repeat((4 - (norm.length % 4)) % 4);
  const bin = atob(padded);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

interface JwtPayload {
  sub?: string;
  exp?: number;
}

async function verifyJwt(token: string): Promise<JwtPayload | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [h, p, s] = parts;
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(JWT_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const valid = await crypto.subtle.verify(
    "HMAC",
    cryptoKey,
    base64UrlDecode(s),
    new TextEncoder().encode(`${h}.${p}`),
  );
  if (!valid) return null;
  let payload: JwtPayload;
  try {
    payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(p)));
  } catch {
    return null;
  }
  if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) return null;
  if (!payload.sub) return null;
  return payload;
}

async function dbFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  headers.set("apikey", SERVICE_ROLE_KEY);
  headers.set("Authorization", `Bearer ${SERVICE_ROLE_KEY}`);
  if (init.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  return fetch(`${SUPABASE_URL}${path}`, { ...init, headers });
}

async function getServiceForUser(
  serviceId: string,
  userId: string,
): Promise<{ id: string; title: string; is_paid: boolean } | null> {
  const url = `/rest/v1/services?id=eq.${encodeURIComponent(serviceId)}`
    + `&executor_id=eq.${encodeURIComponent(userId)}`
    + `&select=id,title,is_paid&limit=1`;
  const r = await dbFetch(url);
  if (!r.ok) return null;
  const rows = (await r.json()) as Array<{ id: string; title: string; is_paid: boolean }>;
  return rows[0] ?? null;
}

async function getPrice(key: string, fallback: number): Promise<number> {
  // settings.value — jsonb, поэтому в REST-ответе оно может прийти
  // и как number (`1000`), и как string (`"1000"`) — обрабатываем оба
  // варианта. На любую сетевую/парс-ошибку возвращаем fallback,
  // чтобы оплата не падала из-за временного сбоя БД.
  try {
    const url = `/rest/v1/settings?key=eq.${encodeURIComponent(key)}&select=value&limit=1`;
    const r = await dbFetch(url);
    if (!r.ok) return fallback;
    const rows = (await r.json()) as Array<{ value: unknown }>;
    const v = rows[0]?.value;
    if (typeof v === "number" && Number.isFinite(v) && v > 0) return v;
    if (typeof v === "string") {
      const n = Number(v);
      if (Number.isFinite(n) && n > 0) return n;
    }
    return fallback;
  } catch (_) {
    return fallback;
  }
}

async function getActivePaymentMethod(
  pmId: string,
  userId: string,
): Promise<{ id: string } | null> {
  const url = `/rest/v1/saved_payment_methods?id=eq.${encodeURIComponent(pmId)}`
    + `&user_id=eq.${encodeURIComponent(userId)}`
    + `&is_active=is.true&select=id&limit=1`;
  const r = await dbFetch(url);
  if (!r.ok) return null;
  const rows = (await r.json()) as Array<{ id: string }>;
  return rows[0] ?? null;
}

interface YooKassaPayment {
  id: string;
  status: string;
  paid: boolean;
  confirmation?: { type: string; confirmation_url?: string };
  payment_method?: { id?: string; saved?: boolean };
}

async function createYooKassaPayment(
  body: Record<string, unknown>,
  idempotencyKey: string,
): Promise<YooKassaPayment> {
  const auth = btoa(`${YOOKASSA_SHOP_ID}:${YOOKASSA_SECRET_KEY}`);
  const resp = await fetch("https://api.yookassa.ru/v3/payments", {
    method: "POST",
    headers: {
      "Authorization": `Basic ${auth}`,
      "Idempotence-Key": idempotencyKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`YooKassa POST /v3/payments → HTTP ${resp.status}: ${text}`);
  }
  return JSON.parse(text) as YooKassaPayment;
}

interface RequestBody {
  kind?: string;
  service_id?: string | null;
  return_url?: string;
  save_card?: boolean;
  payment_method_id?: string;
  /// `card_binding` с этим флагом активирует подписочный триал: после
  /// успешной привязки карты webhook ставит paid_until=now()+30d,
  /// trial_used=true, auto_renew=true. См. webhook activateTrial().
  /// Игнорируется для kind != 'card_binding'.
  activate_trial?: boolean;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }
  if (req.method !== "POST") return jsonResponse(405, { error: "Method not allowed" });

  // 1. Auth
  const authHeader = req.headers.get("authorization") ?? "";
  const m = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!m) return jsonResponse(401, { error: "Missing Bearer token" });
  const jwt = await verifyJwt(m[1]);
  if (!jwt?.sub) return jsonResponse(401, { error: "Invalid JWT" });
  const userId = jwt.sub;

  // 2. Body
  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "Invalid JSON body" });
  }
  const kind = body.kind;
  if (kind !== "subscription" && kind !== "service_slot" && kind !== "card_binding") {
    return jsonResponse(400, {
      error: "Field 'kind' must be 'subscription', 'service_slot' or 'card_binding'",
    });
  }

  // 3. Resolve amount + description + service check
  let amount: number;
  let description: string;
  let serviceId: string | null = null;

  if (kind === "subscription") {
    amount = await getPrice("subscription.monthly_price_rub", PRICE_SUBSCRIPTION_FALLBACK);
    description = "Подписка Диспетчер №1 — 30 дней";
  } else if (kind === "card_binding") {
    // Минимально допустимая в YooKassa сумма для привязки —
    // 1 ₽ (нулевые транзакции не разрешены). Сразу после
    // успеха webhook вызовет refund на ту же сумму, юзер ничего
    // не платит по факту.
    amount = 1;
    description = "Привязка карты Диспетчер №1";
  } else {
    if (!body.service_id) {
      return jsonResponse(400, { error: "Field 'service_id' required for service_slot" });
    }
    serviceId = body.service_id;
    const svc = await getServiceForUser(serviceId, userId);
    if (!svc) return jsonResponse(404, { error: "Service not found or not yours" });
    if (svc.is_paid) return jsonResponse(409, { error: "Service is already paid" });
    amount = await getPrice("service_slot.price_rub", PRICE_SERVICE_SLOT_FALLBACK);
    description = `Публикация услуги: ${svc.title}`.slice(0, 128);
  }

  // Привязка карты не должна идти ни через сохранённую карту, ни
  // без save_payment_method — это ломает весь смысл сценария.
  // Принудительно нормализуем флаги.
  if (kind === "card_binding") {
    body.payment_method_id = undefined;
    body.save_card = true;
  }

  // 4. Если используется сохранённая карта — проверяем что она наша и активна
  if (body.payment_method_id) {
    const pm = await getActivePaymentMethod(body.payment_method_id, userId);
    if (!pm) {
      return jsonResponse(404, { error: "Saved payment method not found or inactive" });
    }
  }

  // 5. Build YooKassa payload
  const paymentId = crypto.randomUUID();
  const idempotencyKey = crypto.randomUUID();
  // Дополняем return_url нашим внутренним paymentId, чтобы экран
  // результата в приложении сразу подцепил статус по deep link
  // (клиент в момент createPayment ещё не знает id).
  const baseReturnUrl = body.return_url || RETURN_URL_DEFAULT;
  const sep = baseReturnUrl.includes("?") ? "&" : "?";
  const returnUrl = `${baseReturnUrl}${sep}payment_id=${encodeURIComponent(paymentId)}`;

  const ykPayload: Record<string, unknown> = {
    amount: { value: amount.toFixed(2), currency: "RUB" },
    capture: true,
    description,
    metadata: {
      user_id: userId,
      kind,
      service_id: serviceId ?? "",
      internal_payment_id: paymentId,
      // Webhook читает этот флаг при kind='card_binding': если '1' —
      // активирует подписочный триал на 30 дней (см. activateTrial).
      activate_trial:
        kind === "card_binding" && body.activate_trial === true ? "1" : "0",
    },
  };

  // confirmation.return_url ставим ВСЕГДА — YooKassa использует его
  // только если потребуется редирект (форма ввода реквизитов или 3DS-
  // челлендж сохранённой карты). Без явного return_url для сценария
  // C (saved card + 3DS) YooKassa подставляла default из настроек
  // мерчанта (главная yoomoney.ru), и юзер после ввода 3DS-кода
  // оказывался не в нашем приложении, а на главной YooMoney.
  ykPayload.confirmation = { type: "redirect", return_url: returnUrl };
  if (body.payment_method_id) {
    // Сценарий C: списание с сохранённой карты. Обычно проходит
    // мгновенно, но банк может потребовать 3DS — тогда YooKassa
    // вернёт confirmation_url с нашим return_url.
    ykPayload.payment_method_id = body.payment_method_id;
  } else {
    // Сценарии A/B: редирект на YooKassa-форму ввода реквизитов.
    if (body.save_card) ykPayload.save_payment_method = true;
  }

  // 6. Call YooKassa
  let yk: YooKassaPayment;
  try {
    yk = await createYooKassaPayment(ykPayload, idempotencyKey);
  } catch (e) {
    console.error(`[create-payment] YooKassa fail: ${e}`);
    return jsonResponse(502, { error: "Failed to create payment in YooKassa" });
  }

  // 7. INSERT в payments. Если YK уже вернул succeeded (мгновенный платёж
  //    с сохранённой карты), сохраняем сразу с правильным статусом —
  //    триггер apply_payment_success применит side-effects.
  //    YooKassa-canceled маппится в наш `failed` (constraint в БД
  //    разрешает только pending/succeeded/failed/refunded).
  const ourStatus =
    yk.status === "succeeded"
      ? "succeeded"
      : yk.status === "canceled"
        ? "failed"
        : "pending";

  // Если YooKassa уже вернула payment_method.id (off-session-списание
  // с сохранённой карты, или мгновенно одобренный платёж) — пишем его
  // сразу. Иначе webhook добавит после payment.succeeded. Это нужно,
  // чтобы триггер apply_payment_success мог сохранить карту в
  // profiles_private.subscription_payment_method_id для последующих
  // авто-списаний.
  const initialPmId = yk.payment_method?.id ?? body.payment_method_id ?? null;
  const insertResp = await dbFetch("/rest/v1/payments", {
    method: "POST",
    headers: { "Prefer": "return=representation" },
    body: JSON.stringify({
      id: paymentId,
      user_id: userId,
      kind,
      amount,
      currency: "RUB",
      external_id: yk.id,
      idempotency_key: idempotencyKey,
      status: ourStatus,
      service_id: serviceId,
      payment_method_id: initialPmId,
    }),
  });
  if (!insertResp.ok) {
    const txt = await insertResp.text();
    console.error(`[create-payment] DB insert failed: ${insertResp.status} ${txt}`);
    return jsonResponse(500, { error: "Failed to record payment" });
  }

  // 8. Если списали с сохранённой карты — трогаем last_used_at
  if (body.payment_method_id && yk.status === "succeeded") {
    await dbFetch(
      `/rest/v1/saved_payment_methods?id=eq.${encodeURIComponent(body.payment_method_id)}`,
      {
        method: "PATCH",
        body: JSON.stringify({ last_used_at: new Date().toISOString() }),
      },
    );
  }

  console.log(
    `[create-payment] OK user=${userId} kind=${kind} amount=${amount} ` +
      `payment=${paymentId} yk_id=${yk.id} status=${yk.status}` +
      (body.save_card ? " save_card=1" : "") +
      (body.payment_method_id ? " from_saved=1" : ""),
  );

  return jsonResponse(200, {
    payment_id: paymentId,
    yookassa_payment_id: yk.id,
    status: yk.status,
    confirmation_url: yk.confirmation?.confirmation_url ?? null,
    amount,
    currency: "RUB",
  });
});

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

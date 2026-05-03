// =====================================================================
// yookassa-webhook
//
// Приём HTTP-уведомлений от YooKassa. Делает четыре вещи:
//   1. Проверяет, что запрос пришёл с IP, который YooKassa официально
//      объявила (https://yookassa.ru/developers/using-api/webhooks).
//   2. Идемпотентно фиксирует событие в payment_events (PK по event_id),
//      чтобы повторные доставки не дублировали обработку.
//   3. На payment.succeeded ставит payments.status='succeeded' — после
//      чего БД-триггер apply_payment_success сам продлит подписку или
//      пометит услугу is_paid=true. На payment.canceled — status='canceled'.
//   4. Если в успешном платеже карта сохранена (save_payment_method=true
//      → object.payment_method.saved=true), кладём её в
//      saved_payment_methods для будущих списаний без редиректа.
// =====================================================================

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const YOOKASSA_SHOP_ID = Deno.env.get("YOOKASSA_SHOP_ID") ?? "";
const YOOKASSA_SECRET_KEY = Deno.env.get("YOOKASSA_SECRET_KEY") ?? "";

if (!SERVICE_ROLE_KEY) console.error("[webhook] SUPABASE_SERVICE_ROLE_KEY is empty");

const YK_IPV4_RANGES: Array<[string, number]> = [
  ["185.71.76.0", 27],
  ["185.71.77.0", 27],
  ["77.75.153.0", 25],
  ["77.75.154.128", 25],
  ["77.75.156.11", 32],
  ["77.75.156.35", 32],
];

function ipv4ToInt(ip: string): number | null {
  const m = ip.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (!m) return null;
  const [, a, b, c, d] = m.map(Number);
  if ([a, b, c, d].some((n) => n < 0 || n > 255)) return null;
  return ((a << 24) | (b << 16) | (c << 8) | d) >>> 0;
}

function isIpInYkWhitelist(ip: string): boolean {
  const ipInt = ipv4ToInt(ip);
  if (ipInt === null) return false;
  for (const [base, prefix] of YK_IPV4_RANGES) {
    const baseInt = ipv4ToInt(base);
    if (baseInt === null) continue;
    const mask = prefix === 0 ? 0 : (~0 << (32 - prefix)) >>> 0;
    if ((ipInt & mask) === (baseInt & mask)) return true;
  }
  return false;
}

function clientIp(req: Request): string {
  const xff = req.headers.get("x-forwarded-for") ?? "";
  if (xff) return xff.split(",")[0].trim();
  return req.headers.get("x-real-ip") ?? "";
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

interface PaymentMethodInfo {
  type?: string;
  id?: string;
  saved?: boolean;
  title?: string;
  card?: {
    first6?: string;
    last4?: string;
    expiry_month?: string;
    expiry_year?: string;
    card_type?: string;
  };
}

interface Notification {
  type?: string;
  event?: string;
  object?: {
    id?: string;
    status?: string;
    paid?: boolean;
    metadata?: Record<string, string>;
    payment_method?: PaymentMethodInfo;
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  // 1. IP whitelist
  const ip = clientIp(req);
  if (!ip || !isIpInYkWhitelist(ip)) {
    console.warn(`[webhook] rejected by IP: ip="${ip}"`);
    return new Response("unauthorized", { status: 401 });
  }

  // 2. Parse body
  const rawBody = await req.text();
  let n: Notification;
  try {
    n = JSON.parse(rawBody);
  } catch {
    return new Response("bad json", { status: 400 });
  }
  const event = n.event ?? "";
  const objId = n.object?.id ?? "";
  if (!event || !objId) {
    console.warn(`[webhook] missing event/object.id: ${rawBody.slice(0, 200)}`);
    return new Response("bad payload", { status: 400 });
  }
  const eventId = `${event}:${objId}`;

  // 3. Идемпотентный INSERT в payment_events
  const insertEvtResp = await dbFetch(
    "/rest/v1/payment_events?on_conflict=event_id",
    {
      method: "POST",
      headers: { "Prefer": "return=representation,resolution=ignore-duplicates" },
      body: JSON.stringify({ event_id: eventId, payload: n }),
    },
  );
  if (!insertEvtResp.ok) {
    const t = await insertEvtResp.text();
    console.error(`[webhook] insert payment_events failed: ${insertEvtResp.status} ${t}`);
    return new Response("db error", { status: 500 });
  }
  const inserted = (await insertEvtResp.json()) as Array<unknown>;
  if (inserted.length === 0) {
    console.log(`[webhook] duplicate event=${eventId}, returning 200`);
    return new Response("duplicate", { status: 200 });
  }

  // 4. Apply effects.
  // YooKassa-`canceled` маппим в наш `failed` (БД-constraint разрешает
  // только pending/succeeded/failed/refunded).
  let applyError: string | null = null;
  if (event === "payment.succeeded") {
    // ПОРЯДОК ВАЖЕН: триггер `apply_payment_success` стреляет на UPDATE
    // payments.status; чтобы он мог записать `subscription_payment_method_id`
    // в profiles_private, payments.payment_method_id должен быть выставлен
    // ДО смены status на 'succeeded'. Поэтому передаём pm.id первым же PATCH.
    const pmId = n.object?.payment_method?.id ?? null;
    applyError = await updatePaymentStatus(objId, "succeeded", pmId);
    // Параллельно — если в этом платеже сохранили карту, кладём её
    // в saved_payment_methods. Метаданные user_id берём из webhook payload.
    if (!applyError) {
      const pm = n.object?.payment_method;
      const userId = n.object?.metadata?.user_id;
      if (pm?.saved && pm.id && userId) {
        const err = await upsertSavedCard(userId, pm);
        if (err) console.error(`[webhook] save card failed: ${err}`);
        // Падать на этом не будем — основной эффект (продление) уже применён.
      }
    }
    // Технический платёж «привязка карты» (1 ₽) — после succeeded
    // сразу инициируем рефанд той же суммы. Если YooKassa приняла
    // запрос — переводим payment в `refunded`. Реальный refund.succeeded
    // придёт отдельным webhook'ом и просто будет залогирован — мы
    // эффект уже применили. Падать при ошибке рефанда не будем:
    // у саппорта останется техзадача вернуть юзеру 1 ₽ вручную,
    // но карта-то уже привязана, основной UX не ломается.
    if (!applyError && n.object?.metadata?.kind === "card_binding") {
      // Активация триала: пользователь нажал «Продолжить» в paywall'е,
      // карта успешно привязана за 1 ₽ — сразу даём 30 дней доступа,
      // запоминаем карту для авто-списания и включаем auto_renew.
      // `apply_payment_success` (БД-триггер) сам не активирует подписку
      // для card_binding: его контракт — продление только для kind='subscription'.
      // Поэтому делаем UPDATE profiles_private отсюда.
      if (n.object?.metadata?.activate_trial === "1") {
        const userId = n.object?.metadata?.user_id;
        if (userId) {
          const err = await activateTrial(userId, pmId ?? undefined);
          if (err) console.error(`[webhook] activate_trial failed: ${err}`);
        }
      }
      // Один retry с задержкой — YooKassa изредка отдаёт 5xx или
      // временный network error, и второй попытки достаточно. Если
      // оба раза fail — оставляем status='succeeded', сообщаем
      // подробно в лог; саппорт вручную сделает refund + payments PATCH.
      let refundErr = await issueRefund(objId, "1.00");
      if (refundErr) {
        await new Promise((r) => setTimeout(r, 2000));
        refundErr = await issueRefund(objId, "1.00");
      }
      if (refundErr) {
        console.error(
          `[webhook] card_binding refund failed (after retry): ${refundErr}`,
        );
      } else {
        const e = await updatePaymentStatus(objId, "refunded");
        if (e) console.error(`[webhook] mark refunded failed: ${e}`);
      }
    }
  } else if (event === "payment.canceled") {
    applyError = await updatePaymentStatus(objId, "failed");
  } else if (event === "refund.succeeded") {
    // Возврат — эффект сложный (кто-то возвращает деньги, надо откатить
    // продление подписки или is_paid). Пока только логируем, реальный
    // откат — отдельная задача.
    console.warn(`[webhook] refund.succeeded for ${objId} — manual handling needed`);
  } else {
    console.log(`[webhook] unknown event=${event}, ignoring`);
  }

  // 5. Mark event processed (or with error)
  const updatePayload: Record<string, unknown> = applyError === null
    ? { processed_at: new Date().toISOString() }
    : { processed_at: new Date().toISOString(), error: applyError };

  await dbFetch(
    `/rest/v1/payment_events?event_id=eq.${encodeURIComponent(eventId)}`,
    { method: "PATCH", body: JSON.stringify(updatePayload) },
  );

  if (applyError !== null) {
    console.error(`[webhook] apply failed event=${eventId}: ${applyError}`);
    return new Response("apply failed", { status: 500 });
  }

  console.log(`[webhook] processed event=${eventId}`);
  return new Response("ok", { status: 200 });
});

async function updatePaymentStatus(
  externalId: string,
  status: "succeeded" | "failed" | "refunded",
  paymentMethodId?: string | null,
): Promise<string | null> {
  const body: Record<string, unknown> = { status };
  // Передаём `payment_method_id` ВМЕСТЕ со сменой статуса на succeeded —
  // это условие, при котором БД-триггер `apply_payment_success` запишет
  // его в `profiles_private.subscription_payment_method_id`. Cron auto-renew
  // потом спишет с этой карты.
  if (paymentMethodId) body.payment_method_id = paymentMethodId;
  const r = await dbFetch(
    `/rest/v1/payments?external_id=eq.${encodeURIComponent(externalId)}`,
    {
      method: "PATCH",
      headers: { "Prefer": "return=representation" },
      body: JSON.stringify(body),
    },
  );
  if (!r.ok) {
    const t = await r.text();
    return `PATCH payments → HTTP ${r.status}: ${t}`;
  }
  const rows = (await r.json()) as Array<{ id: string }>;
  if (rows.length === 0) {
    console.warn(`[webhook] no matching payment for external_id=${externalId}`);
  }
  return null;
}

/// Активирует подписочный триал для юзера: ставит paid_until = now()+30 дней,
/// trial_used=true, auto_renew=true, payment_method_id=<привязанная карта>.
/// Используется в card_binding-флоу с metadata.activate_trial='1'.
/// Идемпотентно: повторный вызов на уже активированном юзере просто
/// перепишет payment_method_id (карта могла быть заменена) — но
/// trial_used и auto_renew повторно не накатим (CASE WHEN trial_used=false).
async function activateTrial(
  userId: string,
  paymentMethodId?: string,
): Promise<string | null> {
  // Берём текущее состояние, чтобы не переставлять paid_until назад,
  // если триал уже был дан и юзер активировал ещё раз карту.
  const cur = await dbFetch(
    `/rest/v1/profiles_private?id=eq.${encodeURIComponent(userId)}` +
      `&select=subscription_paid_until,subscription_trial_used`,
  );
  if (!cur.ok) return `GET profiles_private → HTTP ${cur.status}`;
  const rows = (await cur.json()) as Array<{
    subscription_paid_until: string | null;
    subscription_trial_used: boolean;
  }>;
  if (rows.length === 0) return `profile not found: ${userId}`;
  const trialUsed = rows[0].subscription_trial_used;
  const curUntil = rows[0].subscription_paid_until
    ? new Date(rows[0].subscription_paid_until)
    : null;
  const base = curUntil && curUntil.getTime() > Date.now() ? curUntil : new Date();
  const newUntil = new Date(base.getTime() + 30 * 24 * 60 * 60 * 1000);

  const body: Record<string, unknown> = {
    subscription_payment_method_id: paymentMethodId ?? null,
  };
  if (!trialUsed) {
    // Первая активация: даём триал на 30 дней. trial_until ставится
    // тем же значением, что и paid_until — это маркер «идёт триал».
    // Когда cron позже спишет 1 000 ₽, триггер `apply_payment_success`
    // обновит только paid_until, а trial_until останется в прошлом —
    // UI поймёт «триал кончился».
    body.subscription_paid_until = newUntil.toISOString();
    body.subscription_trial_until = newUntil.toISOString();
    body.subscription_trial_used = true;
    body.subscription_auto_renew = true;
  } else {
    // Повторная привязка: триал не повторяется, paid_until не
    // продлеваем. Однако auto_renew всё-таки включаем — типичный
    // сценарий «юзер удалил карту → триггер выключил auto_renew →
    // юзер тапает тумблер „Авто-продление“ → попадает на привязку
    // новой карты». Без этого юзер привяжет карту, но подписка не
    // продлится — баг.
    body.subscription_auto_renew = true;
  }
  const upd = await dbFetch(
    `/rest/v1/profiles_private?id=eq.${encodeURIComponent(userId)}`,
    {
      method: "PATCH",
      body: JSON.stringify(body),
    },
  );
  if (!upd.ok) {
    const t = await upd.text();
    return `PATCH profiles_private → HTTP ${upd.status}: ${t}`;
  }
  return null;
}

/// Запускает рефанд в YooKassa. Используется для авто-возврата 1 ₽
/// после успешной привязки карты (kind='card_binding'). Идемпотентность
/// обеспечиваем уникальным заголовком, привязанным к external payment id —
/// если webhook payment.succeeded прилетит повторно, второй refund не
/// создастся (YooKassa вернёт тот же объект).
async function issueRefund(
  paymentExternalId: string,
  amountValue: string,
): Promise<string | null> {
  if (!YOOKASSA_SHOP_ID || !YOOKASSA_SECRET_KEY) {
    return "YOOKASSA_SHOP_ID/SECRET not configured";
  }
  const auth = btoa(`${YOOKASSA_SHOP_ID}:${YOOKASSA_SECRET_KEY}`);
  const idempotencyKey = `refund-binding:${paymentExternalId}`;
  try {
    const resp = await fetch("https://api.yookassa.ru/v3/refunds", {
      method: "POST",
      headers: {
        "Authorization": `Basic ${auth}`,
        "Idempotence-Key": idempotencyKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: { value: amountValue, currency: "RUB" },
        payment_id: paymentExternalId,
      }),
    });
    if (!resp.ok) {
      const t = await resp.text();
      return `POST /v3/refunds → HTTP ${resp.status}: ${t}`;
    }
    return null;
  } catch (e) {
    return `refund fetch failed: ${e}`;
  }
}

async function upsertSavedCard(
  userId: string,
  pm: PaymentMethodInfo,
): Promise<string | null> {
  if (!pm.id) return "missing payment_method.id";
  // ON CONFLICT id DO NOTHING — если карта уже сохранена раньше, не трогаем.
  const r = await dbFetch(
    "/rest/v1/saved_payment_methods?on_conflict=id",
    {
      method: "POST",
      headers: { "Prefer": "resolution=ignore-duplicates" },
      body: JSON.stringify({
        id: pm.id,
        user_id: userId,
        kind: pm.type ?? "bank_card",
        card_last4: pm.card?.last4 ?? null,
        card_brand: pm.card?.card_type ?? null,
        card_expiry_month: pm.card?.expiry_month ?? null,
        card_expiry_year: pm.card?.expiry_year ?? null,
        title: pm.title ?? null,
        is_active: true,
      }),
    },
  );
  if (!r.ok) {
    const t = await r.text();
    return `POST saved_payment_methods → HTTP ${r.status}: ${t}`;
  }
  return null;
}

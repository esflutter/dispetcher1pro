// =====================================================================
// subscription-charge-due
//
// Cron-задача: раз в день списывает 1000 ₽ с сохранённой карты у тех
// юзеров, у кого закончилась подписка и включено auto_renew.
//
// Запускается pg_cron'ом ежедневно (см. миграцию `subscription_cron`).
// Защита от внешних вызовов: требует header `X-Cron-Secret`, который
// совпадает с переменной окружения CRON_SECRET. Без секрета 401.
//
// Алгоритм:
//   1. Получаем список due-юзеров через RPC `list_due_subscriptions()`.
//   2. Для каждого делаем off-session платёж в YooKassa
//      (`payment_method_id` = сохранённая карта, без redirect).
//   3. INSERT в `payments` с pending/succeeded — apply_payment_success
//      продлит подписку, если YK сразу отвечает succeeded.
//   4. Если YooKassa отказала (4xx с card_expired / insufficient_funds /
//      и т.п.) — выключаем auto_renew. Юзер пропадает из каталога,
//      на экране /subscription/manage появится «Возобновить подписку».
//   5. Возвращаем сводку: how many charged / how many failed.
// =====================================================================

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const YOOKASSA_SHOP_ID = Deno.env.get("YOOKASSA_SHOP_ID") ?? "";
const YOOKASSA_SECRET_KEY = Deno.env.get("YOOKASSA_SECRET_KEY") ?? "";
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

// Цена тянется из `settings`, как и в yookassa-create-payment, чтобы
// прайс был один источником правды (можно править через админку, не
// перевыкатывая Edge Function).
const PRICE_FALLBACK = 1000;

async function dbFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  headers.set("apikey", SERVICE_ROLE_KEY);
  headers.set("Authorization", `Bearer ${SERVICE_ROLE_KEY}`);
  if (init.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  return fetch(`${SUPABASE_URL}${path}`, { ...init, headers });
}

async function getPrice(): Promise<number> {
  try {
    const r = await dbFetch(
      `/rest/v1/settings?key=eq.subscription.monthly_price_rub&select=value&limit=1`,
    );
    if (!r.ok) return PRICE_FALLBACK;
    const rows = (await r.json()) as Array<{ value: unknown }>;
    const v = rows[0]?.value;
    if (typeof v === "number" && Number.isFinite(v) && v > 0) return v;
    if (typeof v === "string") {
      const n = Number(v);
      if (Number.isFinite(n) && n > 0) return n;
    }
    return PRICE_FALLBACK;
  } catch {
    return PRICE_FALLBACK;
  }
}

interface DueSubscriber {
  user_id: string;
  payment_method_id: string;
  paid_until: string | null;
}

async function listDue(): Promise<DueSubscriber[]> {
  const r = await dbFetch(`/rest/v1/rpc/list_due_subscriptions`, {
    method: "POST",
    body: "{}",
  });
  if (!r.ok) {
    const t = await r.text();
    throw new Error(`list_due_subscriptions failed: ${r.status} ${t}`);
  }
  return (await r.json()) as DueSubscriber[];
}

interface YkPayment {
  id: string;
  status: string;
}

async function chargeSavedCard(
  userId: string,
  paymentMethodId: string,
  amount: number,
  paymentId: string,
): Promise<{ ok: true; yk: YkPayment } | { ok: false; error: string }> {
  const auth = btoa(`${YOOKASSA_SHOP_ID}:${YOOKASSA_SECRET_KEY}`);
  // Стабильный ключ в рамках суток: при повторном запуске cron в тот
  // же день YooKassa вернёт ТОТ ЖЕ платёж, без двойного списания.
  // Раньше использовали `auto-renew:${paymentId}` где paymentId — UUID,
  // на каждый вызов новый, и идемпотентность не работала.
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
  const idempotencyKey = `auto-renew:${userId}:${today}`;
  try {
    const resp = await fetch("https://api.yookassa.ru/v3/payments", {
      method: "POST",
      headers: {
        "Authorization": `Basic ${auth}`,
        "Idempotence-Key": idempotencyKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: { value: amount.toFixed(2), currency: "RUB" },
        capture: true,
        payment_method_id: paymentMethodId,
        description: "Подписка Диспетчер №1 — авто-продление",
        metadata: {
          user_id: userId,
          kind: "subscription",
          internal_payment_id: paymentId,
        },
      }),
    });
    if (!resp.ok) {
      const t = await resp.text();
      return { ok: false, error: `HTTP ${resp.status}: ${t}` };
    }
    const yk = (await resp.json()) as YkPayment;
    return { ok: true, yk };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
}

// Сколько дней после окончания подписки даём на повторные попытки списания,
// прежде чем отписать. Cron — раз в сутки, значит это ≈ число ретраев.
const RENEW_GRACE_DAYS = 3;

function overdueDays(paidUntil: string | null): number {
  if (!paidUntil) return 999;
  const t = Date.parse(paidUntil);
  if (!Number.isFinite(t)) return 999;
  return (Date.now() - t) / 86_400_000;
}

/// Обработать неудачную попытку списания: НЕ отписываем сразу — даём
/// несколько суточных ретраев (вдруг сегодня нет денег / временный сбой
/// банка). Отписываем только когда подписка просрочена дольше grace-периода.
async function handleChargeFailure(s: DueSubscriber): Promise<void> {
  if (overdueDays(s.paid_until) >= RENEW_GRACE_DAYS) {
    await disableAutoRenew(s.user_id);
  }
  // иначе оставляем auto_renew=true — завтрашний cron попробует снова.
}

async function disableAutoRenew(userId: string): Promise<void> {
  await dbFetch(
    `/rest/v1/profiles_private?id=eq.${encodeURIComponent(userId)}`,
    {
      method: "PATCH",
      body: JSON.stringify({ subscription_auto_renew: false }),
    },
  );
}

async function insertPayment(opts: {
  paymentId: string;
  userId: string;
  amount: number;
  externalId: string;
  status: "pending" | "succeeded" | "failed";
  paymentMethodId: string;
  idempotencyKey: string;
}): Promise<void> {
  // ON CONFLICT DO NOTHING на UNIQUE-индексе `payments_external_id_unique`:
  // если cron повторно запустился (ретрай после network-сбоя в момент
  // INSERT), YooKassa вернёт тот же external_id, и Postgrest откажется
  // вставлять дубликат. Без этого подписка продлевалась бы дважды
  // (триггер apply_payment_success стрельнул бы для каждой строки).
  // Заголовок `Prefer: resolution=ignore-duplicates` — Postgrest-аналог
  // ON CONFLICT DO NOTHING.
  const r = await dbFetch("/rest/v1/payments", {
    method: "POST",
    headers: { "Prefer": "resolution=ignore-duplicates" },
    body: JSON.stringify({
      id: opts.paymentId,
      user_id: opts.userId,
      kind: "subscription",
      amount: opts.amount,
      currency: "RUB",
      external_id: opts.externalId,
      idempotency_key: opts.idempotencyKey,
      status: opts.status,
      payment_method_id: opts.paymentMethodId,
    }),
  });
  if (!r.ok) {
    const t = await r.text();
    console.error(`[charge-due] insert payment failed: ${r.status} ${t}`);
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  if (!CRON_SECRET || req.headers.get("x-cron-secret") !== CRON_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  let due: DueSubscriber[];
  try {
    due = await listDue();
  } catch (e) {
    console.error(`[charge-due] listDue failed: ${e}`);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (due.length === 0) {
    console.log("[charge-due] no due subscribers");
    return new Response(JSON.stringify({ charged: 0, failed: 0 }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const amount = await getPrice();
  let charged = 0;
  let failed = 0;

  for (const s of due) {
    const paymentId = crypto.randomUUID();
    // ВНИМАНИЕ: этот ключ идёт только в колонку payments.idempotency_key как
    // пометка и НИГДЕ не читается для дедупа. Реальная защита от повторного
    // списания — это (а) дата-стабильный ключ в заголовке Idempotence-Key
    // внутри chargeSavedCard (`auto-renew:<user>:<today>`) и (б) UNIQUE(external_id)
    // в БД. Не принимайте эту колонку за механизм дедупа.
    const idempotencyKey = `auto-renew-${s.user_id}-${paymentId}`;
    const result = await chargeSavedCard(
      s.user_id,
      s.payment_method_id,
      amount,
      paymentId,
    );
    if (!result.ok) {
      console.error(
        `[charge-due] charge failed user=${s.user_id}: ${result.error}`,
      );
      // Карта не сработала (истекла, нет средств, банк отклонил и т.п.).
      // НЕ отписываем сразу — даём суточные ретраи в пределах grace-периода,
      // и только если подписка просрочена дольше — выключаем auto_renew.
      await handleChargeFailure(s);
      failed++;
      continue;
    }
    const ourStatus =
      result.yk.status === "succeeded"
        ? "succeeded"
        : result.yk.status === "canceled"
          ? "failed"
          : "pending";
    await insertPayment({
      paymentId,
      userId: s.user_id,
      amount,
      externalId: result.yk.id,
      status: ourStatus,
      paymentMethodId: s.payment_method_id,
      idempotencyKey,
    });
    if (ourStatus === "succeeded") {
      charged++;
    } else if (ourStatus === "failed") {
      // YK сразу отказался — обрабатываем как сбой, но тоже с grace-ретраями.
      await handleChargeFailure(s);
      failed++;
    } else {
      // pending — webhook сам продлит, считаем как charged для отчёта.
      charged++;
    }
  }

  console.log(`[charge-due] done charged=${charged} failed=${failed}`);
  return new Response(
    JSON.stringify({ charged, failed, total: due.length }),
    { headers: { "Content-Type": "application/json" } },
  );
});

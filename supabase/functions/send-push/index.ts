// =====================================================================
// send-push — Edge Function для доставки пушей через FCM v1.
//
// КОГДА ВЫЗЫВАЕТСЯ:
// 1) Триггер `notifications_send_trigger` на INSERT в notifications через
//    pg_net.http_post — мгновенная отправка для срочных пушей.
// 2) pg_cron-задача `flush_pending_notifications` раз в минуту — safety
//    fallback для записей, где триггер не справился (pg_net упал,
//    Edge Function вернула 5xx и т.п.).
// 3) Cron `dispatch_scheduled_notifications` раз в минуту — берёт
//    отложенные (scheduled_for <= now()).
//
// ЧТО ДЕЛАЕТ:
// - Берёт pending записи из notifications (либо одну по id, либо до 100
//   через batch).
// - Атомарно «захватывает» запись через CAS (retry_count++), чтобы два
//   параллельных вызова не отправили один и тот же пуш дважды.
// - Получает FCM access_token: либо из кэша в `internal_state` (TTL 55
//   мин), либо подписывает свежий JWT (RS256) и обменивает на токен.
// - Для каждой нотификации читает активные device_tokens юзера, шлёт в
//   FCM v1 параллельно. Помечает UNREGISTERED токены как invalidated.
// - Записывает результат в notifications (sent_push / fcm_error /
//   failed_at). После 3 ретраев или 30 минут — финальный fail.
//
// ENV (Supabase Secrets):
//   SUPABASE_URL                  — стандарт (предзаполнен)
//   SUPABASE_SERVICE_ROLE_KEY     — стандарт (предзаполнен)
//   FCM_SERVICE_ACCOUNT_JSON      — service-account JSON одной строкой
//                                   (вкладка Service Accounts в Firebase)
// =====================================================================

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.45.4";

// ---------------------------------------------------------------------
// Конфиг
// ---------------------------------------------------------------------

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const FCM_SERVICE_ACCOUNT_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "";

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("[send-push] missing Supabase env");
}
if (!FCM_SERVICE_ACCOUNT_JSON) {
  console.error("[send-push] missing FCM_SERVICE_ACCOUNT_JSON env");
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

let serviceAccount: ServiceAccount | null = null;
try {
  serviceAccount = JSON.parse(FCM_SERVICE_ACCOUNT_JSON) as ServiceAccount;
} catch (e) {
  console.error("[send-push] invalid FCM_SERVICE_ACCOUNT_JSON:", e);
}

const FCM_PROJECT_ID = serviceAccount?.project_id ?? "";

// ---------------------------------------------------------------------
// JWT RS256 через Web Crypto (нативно в Deno, быстрее node:crypto).
// ---------------------------------------------------------------------

function base64UrlEncode(buf: Uint8Array | ArrayBuffer): string {
  const bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let str = "";
  for (let i = 0; i < bytes.length; i++) str += String.fromCharCode(bytes[i]);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(b64);
  const buf = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) buf[i] = binary.charCodeAt(i);
  return buf.buffer;
}

async function signJwtRS256(
  payload: Record<string, unknown>,
  privateKeyPem: string,
): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const enc = (obj: Record<string, unknown>) =>
    base64UrlEncode(new TextEncoder().encode(JSON.stringify(obj)));

  const signingInput = `${enc(header)}.${enc(payload)}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const sigBuf = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${base64UrlEncode(new Uint8Array(sigBuf))}`;
}

// ---------------------------------------------------------------------
// FCM access_token: получение с кэшем в internal_state.
// ---------------------------------------------------------------------

async function getFcmAccessToken(supabase: SupabaseClient): Promise<string> {
  // 1. Кэш в БД — общий для всех инстансов Edge Function.
  const { data: cached } = await supabase
    .from("internal_state")
    .select("value, expires_at")
    .eq("key", "fcm_access_token")
    .maybeSingle();

  if (
    cached?.value &&
    cached.expires_at &&
    new Date(cached.expires_at).getTime() > Date.now() + 60_000
  ) {
    return cached.value;
  }

  if (!serviceAccount) {
    throw new Error("FCM service account not configured");
  }

  // 2. Подписать JWT и обменять на access_token у Google.
  const now = Math.floor(Date.now() / 1000);
  const jwt = await signJwtRS256(
    {
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    },
    serviceAccount.private_key,
  );

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!res.ok) {
    throw new Error(`Google OAuth failed: ${res.status} ${await res.text()}`);
  }

  const { access_token, expires_in } = await res.json() as {
    access_token: string;
    expires_in: number;
  };

  // 3. Кэшируем на (expires_in - 5min) — запас от истечения.
  const expiresAt = new Date(
    Date.now() + (expires_in - 300) * 1000,
  ).toISOString();
  await supabase.from("internal_state").upsert({
    key: "fcm_access_token",
    value: access_token,
    expires_at: expiresAt,
  });

  return access_token;
}

// ---------------------------------------------------------------------
// Отправка одного пуша через FCM v1.
// ---------------------------------------------------------------------

interface FcmResult {
  ok: boolean;
  messageId?: string;
  error?: string;
  shouldInvalidate: boolean; // UNREGISTERED / NOT_FOUND → пометить токен
  tokenId: string;
}

async function sendOneFcm(
  accessToken: string,
  tokenId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, unknown>,
): Promise<FcmResult> {
  // FCM v1 требует data как Record<string, string>.
  const stringifiedData = Object.fromEntries(
    Object.entries(data || {}).map(([k, v]) => [k, String(v)]),
  );

  const payload = {
    message: {
      token,
      notification: { title, body },
      data: stringifiedData,
      android: {
        // priority HIGH доставляется даже в Doze (когда телефон спит).
        // Для маркетинговых рассылок надо было бы NORMAL — у нас все
        // пуши «по делу», ставим HIGH.
        priority: "HIGH",
        // ВАЖНО: channel_id НЕ передаём. Если канал с указанным id
        // отсутствует на устройстве — Android 8+ молча отбрасывает пуш.
        // Клиент сам создаст дефолтный канал через flutter_local_notifications.
      },
    },
  };

  try {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      },
    );

    if (res.ok) {
      const { name } = await res.json() as { name: string };
      return { ok: true, messageId: name, shouldInvalidate: false, tokenId };
    }

    const errText = await res.text();
    let shouldInvalidate = false;
    try {
      const errJson = JSON.parse(errText);
      const errorCode = errJson?.error?.details?.[0]?.errorCode;
      // UNREGISTERED — токен инвалидирован (приложение удалили или сбросили).
      // NOT_FOUND — на старых API тоже означало мёртвый токен.
      if (errorCode === "UNREGISTERED" || res.status === 404) {
        shouldInvalidate = true;
      }
    } catch { /* errText не JSON — оставляем shouldInvalidate=false */ }

    return {
      ok: false,
      error: `${res.status}: ${errText.substring(0, 300)}`,
      shouldInvalidate,
      tokenId,
    };
  } catch (e) {
    return {
      ok: false,
      error: `network: ${String(e).substring(0, 300)}`,
      shouldInvalidate: false,
      tokenId,
    };
  }
}

// ---------------------------------------------------------------------
// Обработка одной нотификации: захват CAS + проверка opt-out +
// чтение токенов + параллельная отправка + запись результата.
// ---------------------------------------------------------------------

interface NotificationRow {
  id: string;
  user_id: string;
  event_kind: string;
  title: string;
  body: string;
  data: Record<string, unknown> | null;
  retry_count: number;
  created_at: string;
}

async function processNotification(
  supabase: SupabaseClient,
  accessToken: string,
  n: NotificationRow,
): Promise<void> {
  // === 1. Атомарный захват через CAS ===
  // Увеличиваем retry_count только если запись ещё в pending-состоянии
  // И retry_count совпадает с тем, что мы прочитали. Это защита от
  // двойной обработки одной записи параллельными вызовами (триггер +
  // cron-фолбэк, или два экземпляра cron).
  const { data: claimed } = await supabase
    .from("notifications")
    .update({ retry_count: n.retry_count + 1 })
    .eq("id", n.id)
    .eq("retry_count", n.retry_count)
    .eq("sent_push", false)
    .is("failed_at", null)
    .select("id")
    .maybeSingle();

  if (!claimed) {
    // Кто-то другой захватил запись — пропускаем без логов.
    return;
  }

  // === 2. Проверка opt-out юзера ===
  const { data: settings } = await supabase
    .from("profiles_private")
    .select("push_enabled")
    .eq("id", n.user_id)
    .maybeSingle();

  if (settings?.push_enabled === false) {
    // Юзер отключил пуши тумблером. Помечаем как «обработано» — пуш не
    // идёт, но запись в inbox остаётся (юзер увидит при заходе).
    await supabase
      .from("notifications")
      .update({
        sent_push: true,
        sent_at: new Date().toISOString(),
        fcm_error: "user_opted_out",
      })
      .eq("id", n.id);
    return;
  }

  // === 3. Активные device_tokens юзера ===
  // Фильтр по приложению-получателю: каждый юзер может быть зарегистрирован
  // и как исполнитель, и как заказчик с разных устройств — пуш про
  // «новый отклик» должен прийти ТОЛЬКО на приложение заказчика, иначе
  // тап откроет битый deep-link.
  // target_app передаётся в data.target_app из enqueue_*; если NULL —
  // шлём во все токены юзера (например, account_blocked, review_received).
  const targetApp = (n.data?.target_app as string | undefined) ?? null;

  let tokensQuery = supabase
    .from("device_tokens")
    .select("id, token, app")
    .eq("user_id", n.user_id)
    .is("invalidated_at", null);

  if (targetApp === "executor" || targetApp === "customer") {
    // Старые токены до миграции 015 имеют app=NULL — их тоже шлём (fallback),
    // чтобы не потерять. После того как клиенты переустановятся на новый
    // APK с записью app, NULL-токены постепенно сменятся.
    tokensQuery = tokensQuery.or(`app.eq.${targetApp},app.is.null`);
  }

  const { data: tokens } = await tokensQuery;

  if (!tokens || tokens.length === 0) {
    // У юзера нет активных токенов (вышел из всех устройств, или
    // приложение не успело зарегистрироваться). Inbox-запись всё равно
    // останется — юзер увидит при следующем заходе.
    await supabase
      .from("notifications")
      .update({
        sent_push: true,
        sent_at: new Date().toISOString(),
        fcm_error: "no_active_tokens",
      })
      .eq("id", n.id);
    return;
  }

  // === 4. Параллельная отправка во все токены юзера ===
  const results = await Promise.allSettled(
    tokens.map((t) =>
      sendOneFcm(
        accessToken,
        t.id,
        t.token,
        n.title,
        n.body,
        n.data ?? {},
      )
    ),
  );

  // === 5. Анализ результатов + инвалидация мёртвых токенов ===
  let anySuccess = false;
  let lastMessageId: string | undefined;
  let lastError: string | undefined;
  const toInvalidate: string[] = [];

  for (const r of results) {
    if (r.status === "rejected") {
      lastError = String(r.reason).substring(0, 300);
      continue;
    }
    const v = r.value;
    if (v.ok) {
      anySuccess = true;
      lastMessageId = v.messageId;
    } else {
      lastError = v.error;
      if (v.shouldInvalidate) toInvalidate.push(v.tokenId);
    }
  }

  if (toInvalidate.length > 0) {
    await supabase
      .from("device_tokens")
      .update({ invalidated_at: new Date().toISOString() })
      .in("id", toInvalidate);
  }

  // === 6. Финальная запись результата ===
  if (anySuccess) {
    await supabase
      .from("notifications")
      .update({
        sent_push: true,
        sent_at: new Date().toISOString(),
        fcm_message_id: lastMessageId,
        // lastError может быть set если часть токенов отказала — пишем
        // для диагностики, но sent_push=true (хотя бы одно устройство
        // получило пуш).
        fcm_error: lastError ?? null,
      })
      .eq("id", n.id);
  } else {
    // Все токены вернули ошибку — пометить fcm_error, проверить retry.
    const newRetry = n.retry_count + 1;
    const ageMs = Date.now() - new Date(n.created_at).getTime();
    const giveUp = newRetry >= 3 || ageMs > 30 * 60 * 1000;

    await supabase
      .from("notifications")
      .update({
        fcm_error: lastError ?? "all sends failed",
        failed_at: giveUp ? new Date().toISOString() : null,
      })
      .eq("id", n.id);
  }
}

// ---------------------------------------------------------------------
// HTTP handler
// ---------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    // POST body опционален. Если есть { notification_id } — обрабатываем
    // одну запись (триггер). Иначе — берём пачку pending (cron).
    let body: { notification_id?: string } | undefined;
    if (req.method === "POST") {
      try {
        body = await req.json();
      } catch { /* пустое body OK */ }
    }

    let query = supabase
      .from("notifications")
      .select(
        "id, user_id, event_kind, title, body, data, retry_count, created_at",
      )
      .eq("sent_push", false)
      .is("failed_at", null);

    if (body?.notification_id) {
      query = query.eq("id", body.notification_id);
    } else {
      // Batch-режим: берём только те, чьё время пришло (или нет scheduled_for)
      // и не старше 30 минут (старые помечаем failed отдельно).
      const nowIso = new Date().toISOString();
      const cutoff = new Date(Date.now() - 30 * 60 * 1000).toISOString();
      query = query
        .or(`scheduled_for.is.null,scheduled_for.lte.${nowIso}`)
        .gt("created_at", cutoff)
        .order("created_at")
        .limit(100);
    }

    const { data: pending, error: pendingErr } = await query;

    if (pendingErr) {
      console.error("[send-push] fetch pending failed:", pendingErr.message);
      return jsonResp(500, { ok: false, error: pendingErr.message });
    }

    if (!pending || pending.length === 0) {
      return jsonResp(200, { ok: true, processed: 0 });
    }

    const accessToken = await getFcmAccessToken(supabase);

    // Параллельная обработка всех записей пачки.
    await Promise.allSettled(
      pending.map((n) =>
        processNotification(supabase, accessToken, n as NotificationRow)
      ),
    );

    return jsonResp(200, { ok: true, processed: pending.length });
  } catch (err) {
    console.error("[send-push] unhandled error:", err);
    return jsonResp(500, {
      ok: false,
      error: String(err).substring(0, 500),
    });
  }
});

function jsonResp(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

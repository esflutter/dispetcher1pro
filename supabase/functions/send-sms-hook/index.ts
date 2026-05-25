// =====================================================================
// send-sms-hook
//
// Supabase Auth Hook (HTTP) — вызывается GoTrue при `signInWithOtp`,
// если телефон НЕ попал в `GOTRUE_SMS_TEST_OTP`. Шлёт SMS через RedSMS.
// До 2026-05 здесь использовался SMS.ru (см. git-историю); по решению
// клиента провайдер заменён на RedSMS.
//
// Запросы подписаны Standard Webhooks (заголовки webhook-id /
// webhook-timestamp / webhook-signature). Без валидной подписи функция
// возвращает 401 — иначе любой мог бы дёрнуть наш URL и слать SMS за
// наш счёт.
//
// Env (задаются в Beget Supabase Studio → Edge Functions → Secrets):
//   REDSMS_LOGIN                — логин в ЛК cp.redsms.ru (обязательно).
//   REDSMS_API_KEY              — API-ключ из «Настройки / HTTP API»
//                                 (обязательно).
//   REDSMS_SENDER               — имя отправителя (опц.; пусто =
//                                 `REDSMS.RU` — общий тестовый
//                                 отправитель с лимитом 30 SMS/день,
//                                 для прода нужно зарегистрировать
//                                 собственное буквенное имя).
//   REDSMS_TEST_MODE            — `"true"` → код не отправляется
//                                 реально, в логи пишется payload.
//                                 По умолчанию `"false"`.
//   SEND_SMS_HOOK_SECRET        — `v1,whsec_<base64>`, тот же, что
//                                 `GOTRUE_HOOK_SEND_SMS_SECRET`
//                                 (обязательно).
//
// API RedSMS (см. https://docs.redsms.ru/http/):
//   POST https://cp.redsms.ru/api/message
//   Headers:
//     login: <REDSMS_LOGIN>
//     ts: ts-value-<unix-seconds>
//     secret: md5(ts + REDSMS_API_KEY)   ← где ts — целиком строка
//                                          с префиксом "ts-value-".
//     Content-Type: application/json
//   Body: { route: "sms", from, to: "+79991234567", text }
//
// Успешный ответ: 200 {"success": true, "items": [{uuid, status,
//                       status_time, to}], "errors": []}.
// При ошибке поле success=false и заполнен errors[].
// =====================================================================

// MD5 в Web Crypto не поддерживается — берём из node:crypto (Deno имеет
// Node compat layer). На Beget self-hosted edge-runtime Node API уже
// работает (используется в других функциях).
import { createHash } from "node:crypto";

// inline base64 decoder — без внешних импортов с deno.land,
// потому что в сети edge-runtime deno.land резолвится только на IPv6,
// а у контейнера нет IPv6, и fetch ESM-модулей виснет.
function decodeBase64(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

interface SendSmsHookPayload {
  user?: { id?: string; phone?: string };
  sms?: { otp?: string };
}

interface RedSmsItem {
  uuid?: string;
  status?: string;
  status_time?: number;
  to?: string;
}

interface RedSmsError {
  code?: number | string;
  message?: string;
  to?: string;
}

interface RedSmsResponse {
  success?: boolean;
  items?: RedSmsItem[];
  errors?: RedSmsError[];
  count?: number;
  message?: string;
}

const REDSMS_LOGIN = Deno.env.get("REDSMS_LOGIN") ?? "";
const REDSMS_API_KEY = Deno.env.get("REDSMS_API_KEY") ?? "";
const REDSMS_SENDER = Deno.env.get("REDSMS_SENDER") || "REDSMS.RU";
const REDSMS_TEST_MODE = Deno.env.get("REDSMS_TEST_MODE") === "true";
const HOOK_SECRET = Deno.env.get("SEND_SMS_HOOK_SECRET") ?? "";

// Проверяем env при холодном старте — лучше ругнуться в логах сразу,
// чем молча возвращать 401/500 на каждый запрос.
if (!REDSMS_LOGIN) console.error("[send-sms-hook] REDSMS_LOGIN is empty");
if (!REDSMS_API_KEY) console.error("[send-sms-hook] REDSMS_API_KEY is empty");
if (!HOOK_SECRET) console.error("[send-sms-hook] SEND_SMS_HOOK_SECRET is empty");

// "v1,whsec_<base64>" → сырые байты HMAC-ключа.
function loadHookKey(): Uint8Array | null {
  const prefix = "v1,whsec_";
  if (!HOOK_SECRET.startsWith(prefix)) return null;
  try {
    return decodeBase64(HOOK_SECRET.slice(prefix.length));
  } catch {
    return null;
  }
}

const HOOK_KEY = loadHookKey();

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function verifySignature(
  rawBody: string,
  webhookId: string,
  webhookTimestamp: string,
  signatureHeader: string,
): Promise<boolean> {
  if (!HOOK_KEY) return false;
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    HOOK_KEY,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = `${webhookId}.${webhookTimestamp}.${rawBody}`;
  const sigBuf = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    new TextEncoder().encode(signed),
  );
  const expected = btoa(String.fromCharCode(...new Uint8Array(sigBuf)));

  // Заголовок может содержать несколько подписей через пробел
  // (на случай ротации ключей). Достаточно совпадения с одной.
  for (const part of signatureHeader.split(" ")) {
    const [version, sig] = part.split(",");
    if (version === "v1" && sig && constantTimeEqual(sig, expected)) return true;
  }
  return false;
}

/**
 * Приводит номер к формату RedSMS: `+79991234567`.
 * - Принимает любые цифры/символы, нормализует к 10 цифрам с префиксом `+7`.
 * - Если телефон не «российский» (10 цифр после кода страны, начинается
 *   на 7/8 либо ровно 10 цифр) — отдаём как есть с `+` спереди, RedSMS
 *   сам ответит ошибкой, если формат он не примет.
 */
function normalizePhone(phone: string): string {
  const digits = phone.replace(/[^0-9]/g, "");
  if (digits.length === 10) return `+7${digits}`;
  if (digits.length === 11 && (digits[0] === "7" || digits[0] === "8")) {
    return `+7${digits.substring(1)}`;
  }
  // Не российский формат: оставляем как есть с обязательным `+`.
  return digits.startsWith("+") ? digits : `+${digits}`;
}

function md5Hex(input: string): string {
  return createHash("md5").update(input).digest("hex");
}

/**
 * Маппинг кодов ошибок RedSMS на HTTP-статусы для GoTrue. GoTrue
 * показывает юзеру разные сообщения в зависимости от HTTP-кода ответа
 * хука: 4xx → пользовательская ошибка, 5xx → "Server error".
 *
 * Документация RedSMS не публикует исчерпывающий список кодов, поэтому
 * ориентируемся на текст сообщения и общий «success=false». Известные
 * нам грабли:
 *   - неверный/несогласованный отправитель — RedSMS отвечает success=true
 *     с пустыми items и errors, в которых сказано «no sender». Это
 *     не наш косяк, но юзер не получит код, поэтому 503.
 *   - неверный API-ключ — 401 от RedSMS, у нас → 500 (внутренняя
 *     конфигурация).
 *   - неверный формат номера — на стороне RedSMS либо 400, либо
 *     success=false c message. Маппим в 400.
 */
function classifyError(
  data: RedSmsResponse,
  httpStatus: number,
): { httpStatus: number; details: string } {
  if (httpStatus === 401 || httpStatus === 403) {
    return { httpStatus: 500, details: `redsms auth failed: HTTP ${httpStatus}` };
  }
  const firstErr = data.errors?.[0];
  const msg = firstErr?.message ?? data.message ?? `HTTP ${httpStatus}`;
  const code = String(firstErr?.code ?? "");
  // Грубая категоризация по тексту/коду:
  if (/balance|insufficient|funds|нет средств/i.test(msg)) {
    return { httpStatus: 503, details: `redsms: ${msg}` };
  }
  if (/sender|отправитель/i.test(msg)) {
    return { httpStatus: 503, details: `redsms sender error: ${msg}` };
  }
  if (/phone|number|номер/i.test(msg)) {
    return { httpStatus: 400, details: `redsms invalid phone: ${msg}` };
  }
  if (/rate|limit|превышен|лимит/i.test(msg)) {
    return { httpStatus: 429, details: `redsms rate-limited: ${msg}` };
  }
  return {
    httpStatus: httpStatus >= 500 ? 502 : 502,
    details: `redsms error code=${code} msg=${msg}`,
  };
}

async function sendRedSms(
  phone: string,
  text: string,
): Promise<{ ok: true; uuid?: string } | { ok: false; httpStatus: number; details: string }> {
  if (REDSMS_TEST_MODE) {
    console.log(
      `[send-sms-hook][TEST_MODE] would send phone=${phone} text="${text}" from=${REDSMS_SENDER}`,
    );
    return { ok: true };
  }
  // ts — целиком строка с префиксом "ts-value-", чтобы совпадать с
  // примерами из docs.redsms.ru (PHP/Node/Bash sample-кода). Под
  // подписью идёт именно эта полная строка.
  const tsValue = `ts-value-${Math.floor(Date.now() / 1000)}`;
  const secret = md5Hex(tsValue + REDSMS_API_KEY);
  const body = JSON.stringify({
    route: "sms",
    from: REDSMS_SENDER,
    to: phone,
    text,
  });

  let resp: Response;
  try {
    resp = await fetch("https://cp.redsms.ru/api/message", {
      method: "POST",
      headers: {
        "login": REDSMS_LOGIN,
        "ts": tsValue,
        "secret": secret,
        "Content-Type": "application/json",
      },
      body,
    });
  } catch (e) {
    return { ok: false, httpStatus: 502, details: `network error: ${e}` };
  }

  let data: RedSmsResponse;
  try {
    data = (await resp.json()) as RedSmsResponse;
  } catch {
    return { ok: false, httpStatus: 502, details: `redsms: invalid JSON (HTTP ${resp.status})` };
  }

  if (!resp.ok) {
    return { ok: false, ...classifyError(data, resp.status) };
  }
  // success=true с непустым items — реальная доставка в очередь оператора.
  // RedSMS возвращает массив items по числу адресатов; нам нужен первый.
  if (data.success && (data.items?.length ?? 0) > 0) {
    return { ok: true, uuid: data.items?.[0]?.uuid };
  }
  // success=false ИЛИ success=true c пустым items — оба случая считаем
  // провалом. Берём первую ошибку из errors[] для логов.
  return { ok: false, ...classifyError(data, resp.status) };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const rawBody = await req.text();
  const webhookId = req.headers.get("webhook-id") ?? "";
  const webhookTimestamp = req.headers.get("webhook-timestamp") ?? "";
  const webhookSignature = req.headers.get("webhook-signature") ?? "";

  if (!webhookId || !webhookTimestamp || !webhookSignature) {
    return new Response("Missing webhook headers", { status: 401 });
  }
  // Replay-защита: тело старше 5 минут отбрасываем.
  const ts = Number.parseInt(webhookTimestamp, 10);
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isFinite(ts) || Math.abs(now - ts) > 5 * 60) {
    return new Response("Stale timestamp", { status: 401 });
  }
  if (!(await verifySignature(rawBody, webhookId, webhookTimestamp, webhookSignature))) {
    return new Response("Invalid signature", { status: 401 });
  }

  let payload: SendSmsHookPayload;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const phoneRaw = payload.user?.phone ?? "";
  const otp = payload.sms?.otp ?? "";
  if (!phoneRaw || !otp) {
    return new Response("Missing user.phone or sms.otp", { status: 400 });
  }
  const phone = normalizePhone(phoneRaw);
  // Простая проверка длины — RedSMS сам отдаст ошибку, если формат
  // не примет, но дешевле отрубить на нашей стороне.
  if (phone.length < 11 || phone.length > 16) {
    return new Response("Invalid phone format", { status: 400 });
  }

  const text = `Ваш код: ${otp}`;
  const result = await sendRedSms(phone, text);

  if (result.ok) {
    console.log(
      `[send-sms-hook] sent phone=${phone}${result.uuid ? ` uuid=${result.uuid}` : ""}${REDSMS_TEST_MODE ? " [TEST_MODE]" : ""}`,
    );
    return new Response(JSON.stringify({}), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  console.error(
    `[send-sms-hook] failed phone=${phone} http=${result.httpStatus} ${result.details}`,
  );
  return new Response(
    JSON.stringify({
      error: { http_code: result.httpStatus, message: result.details },
    }),
    { status: result.httpStatus, headers: { "Content-Type": "application/json" } },
  );
});

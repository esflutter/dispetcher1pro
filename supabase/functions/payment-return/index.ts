// Edge Function `payment-return`: возвращает простую HTML-страницу,
// которая авторедиректит браузер на deep link `dispatcher1pro://...`.
//
// Зачем: Chrome/Android (и часть других браузеров) НЕ открывают
// кастомные схемы (`dispatcher1pro://`) при прямом 302-редиректе с
// чужого сайта (yoomoney.ru/yookassa) — это защита от unsolicited
// app-launch. Они допускают такой переход только из явного
// пользовательского контекста (тапа) или из той же страницы, где
// JavaScript вызвал `window.location`.
//
// Поэтому YooKassa в `confirmation.return_url` указываем на ЭТУ
// страницу (https-схема, валидная для редиректа), а уже она через
// JS-присваивание `window.location.href = 'dispatcher1pro://...'`
// переходит на deep link — Chrome это пропускает.
//
// Что в URL: query-параметры, которые YooKassa отдала нам обратно
// (если есть) + наши собственные `return` и `binding`. Прокидываем их
// 1:1 в deep link, чтобы PaymentResultScreen открыл нужное место и
// показал правильные тексты.
//
// Безопасность: страница не читает БД, не пишет, секретов не содержит —
// единственное действие, которое она делает, это `window.location.href`
// в `dispatcher1pro://`. RLS на `payments` защищает данные на стороне
// приложения, когда оно открывается по deep link.
//
// Деплой: scp index.ts на VPS в `/srv/supabase/volumes/functions/payment-return/`,
// затем `docker compose restart functions` (как и для `yookassa-create-payment`).

const HTML = (deepLink: string) => `<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Возврат в приложение</title>
  <style>
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #FFFFFF;
      color: #1A1A1A;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
      box-sizing: border-box;
    }
    .card {
      max-width: 360px;
      width: 100%;
      text-align: center;
    }
    .spinner {
      width: 48px;
      height: 48px;
      border: 4px solid #FFE4B0;
      border-top-color: #FF9800;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin: 0 auto 24px;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    h1 { font-size: 22px; font-weight: 700; margin: 0 0 12px; }
    p { font-size: 15px; line-height: 1.4; color: #666; margin: 0 0 24px; }
    a.button {
      display: inline-block;
      background: #FF9800;
      color: #FFFFFF;
      text-decoration: none;
      font-weight: 600;
      padding: 14px 24px;
      border-radius: 12px;
      font-size: 16px;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="spinner"></div>
    <h1>Возвращаем в приложение</h1>
    <p>Если приложение не открылось автоматически — нажмите кнопку ниже.</p>
    <a class="button" href="${deepLink}">Открыть Диспетчер №1</a>
  </div>
  <script>
    // Триггерим deep link после первого кадра, чтобы Chrome
    // воспринимал это как переход «в рамках страницы», а не извне.
    setTimeout(function() {
      window.location.href = ${JSON.stringify(deepLink)};
    }, 50);
  </script>
</body>
</html>`;

// Вычистка query: пропускаем только известные ключи, чтобы не
// прокинуть в deep link что-то лишнее/опасное.
const ALLOWED_KEYS = new Set(["id", "payment_id", "binding", "return"]);

Deno.serve((req) => {
  const url = new URL(req.url);
  const out = new URLSearchParams();
  for (const [k, v] of url.searchParams.entries()) {
    if (ALLOWED_KEYS.has(k)) out.set(k, v);
  }
  const qs = out.toString();
  const deepLink = qs.length > 0
    ? `dispatcher1pro://payment/result?${qs}`
    : `dispatcher1pro://payment/result`;
  return new Response(HTML(deepLink), {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      // Никакого кэширования — страница приходит на разные платежи.
      "Cache-Control": "no-store",
    },
  });
});

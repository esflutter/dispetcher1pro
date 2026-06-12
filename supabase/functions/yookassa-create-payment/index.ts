// =====================================================================
// УСТАРЕВШАЯ КОПИЯ — НЕ ДЕПЛОИТЬ.
//
// Канонический исходник: dispetcher1/supabase/functions/yookassa-create-payment/index.ts
// Эта копия отставала от канона (идемпотентность, серверные цены, таймауты).
// Удалить каталог не дала политика прав — файл заменён заглушкой, чтобы
// случайный деплой отсюда сразу упал, а не вернул старую логику.
// =====================================================================
Deno.serve(() =>
  new Response(
    JSON.stringify({
      error: "stale_copy",
      message:
        "Эта копия yookassa-create-payment устарела. Деплойте из supabase/functions/yookassa-create-payment.",
    }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  ));

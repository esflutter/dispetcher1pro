// =====================================================================
// УСТАРЕВШАЯ КОПИЯ — НЕ ДЕПЛОИТЬ.
//
// Канонический исходник: dispetcher1/supabase/functions/payment-return/index.ts
// Эта копия отставала от канона (валидация deep-link параметров).
// Удалить каталог не дала политика прав — файл заменён заглушкой, чтобы
// случайный деплой отсюда сразу упал, а не вернул старую логику.
// =====================================================================
Deno.serve(() =>
  new Response(
    JSON.stringify({
      error: "stale_copy",
      message:
        "Эта копия payment-return устарела. Деплойте из supabase/functions/payment-return.",
    }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  ));

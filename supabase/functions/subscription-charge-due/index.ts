// =====================================================================
// ПЕРЕЕХАЛО — НЕ ДЕПЛОИТЬ ОТСЮДА.
//
// Канонический исходник: dispetcher1/supabase/functions/subscription-charge-due/index.ts
// Раньше эта функция жила ТОЛЬКО здесь, из-за чего каталог claude/supabase
// смешивал живой канон и устаревшие копии — массовый деплой отсюда мог
// затереть боевые функции. Теперь весь канон в supabase/functions, а здесь
// заглушка: случайный деплой отсюда упадёт громко (410), а не молча.
// =====================================================================
Deno.serve(() =>
  new Response(
    JSON.stringify({
      error: "stale_copy",
      message:
        "Канон subscription-charge-due переехал в supabase/functions/subscription-charge-due.",
    }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  ));

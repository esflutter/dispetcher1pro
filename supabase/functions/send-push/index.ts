// =====================================================================
// ПЕРЕЕХАЛО — НЕ ДЕПЛОИТЬ ОТСЮДА.
//
// Канонический исходник: dispetcher1/supabase/functions/send-push/index.ts
// Здесь заглушка, чтобы случайный деплой из claude/supabase упал громко
// (410), а не воскресил устаревшую копию. Подробнее — в шапке заглушки
// subscription-charge-due рядом.
// =====================================================================
Deno.serve(() =>
  new Response(
    JSON.stringify({
      error: "stale_copy",
      message: "Канон send-push переехал в supabase/functions/send-push.",
    }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  ));

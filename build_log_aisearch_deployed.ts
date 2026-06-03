// =====================================================================
// ai-search — one-shot RAG-поиск заказов (для исполнителя) или
//             исполнителей (для заказчика).
//
// Паттерн (как в видео-методичке):
//   1. Клиент шлёт свободный текст («экскаватор в радиусе 10 км от Москвы»)
//   2. Берём справочники machinery/categories через ai_get_search_catalogs()
//   3. LLM #1 (Lite, jsonObject): текст + справочники → JSON-фильтр
//   4. SQL: ai_search_orders / ai_search_executors с этим фильтром
//   5. LLM #2 (Lite): описание найденного → короткий комментарий
//   6. Возвращаем клиенту: { reply, data: { kind, ids } }
//
// ВХОД:
//   POST /functions/v1/ai-search
//   Authorization: Bearer <JWT>
//   Body: {
//     "session_id"?: "uuid",
//     "message":     "текст",
//     "app":         "executor" | "customer"
//   }
//
// ВЫХОД:
//   200 {
//     session_id, reply, data: { kind, ids[], items[] },
//     filter_used, model, quota
//   }
// =====================================================================

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.45.4";

import { systemPromptFor, REPLY_CONTENT_FILTER, REPLY_QUOTA_EXCEEDED } from "../_shared/persona.ts";
import {
  yandexCompletion,
  estimateCostKopecks,
  loadTariffs,
  YandexContentFilterError,
  type YandexMessage,
} from "../_shared/yandex.ts";

const SUPABASE_URL              = Deno.env.get("SUPABASE_URL")              ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SUPABASE_ANON_KEY         = Deno.env.get("SUPABASE_ANON_KEY")         ?? "";
const DADATA_TOKEN              = Deno.env.get("DADATA_TOKEN")              ?? "";

const corsHeaders: HeadersInit = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------
// 1a. Простой keyword-парсер (server-side).
//
// В наших тестах YandexGPT (и Lite, и Pro) ненадёжно извлекает поля из
// промпта со справочниками — теряет город, путает технику. Делаем
// надёжный keyword-matching: проходим по справочнику и ищем совпадения
// в тексте. Дёшево, детерминированно, работает для 90% запросов.
//
// LLM используется только для финального комментария к найденным карточкам.
// ---------------------------------------------------------------------
function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function keywordParseFilter(
  text: string,
  app: "executor" | "customer",
  catalogs: { machinery: Array<{ id: number; title: string }>; categories: Array<{ id: number; title: string }> },
  todayIso: string,
): ParsedFilter {
  const lc = text.toLowerCase();

  // --- Техника: ищем по подстроке title (и по «слову основы») ---
  // Расширенный словарь синонимов и опечаток (бытовое употребление).
  const synonyms: Record<string, string[]> = {
    "экскаватор":      ["копать", "котлован", "траншея", "землекоп", "экскаватр", "экскавтор"],
    "экскаватор-погрузчик": ["jcb", "джи си би", "джисиби"],
    "миниэкскаватор":  ["мини экскаватор", "малый экскаватор"],
    "погрузчик":       ["грузить", "разгружать", "грузчик", "фронтальник", "погрузщик"],
    "минипогрузчик":   ["мини погрузчик", "bobcat", "бобкэт", "бобкат"],
    "самосвал":        ["вывоз", "вывезти", "мусор", "сыпучие", "грузовик", "самосвл"],
    "автокран":        ["кран", "поднять", "поднимать"],
    "буроям":          ["бур", "столбы", "сваи", "буровая"],
    "автовышка":       ["вышка", "высота", "монтаж проводов"],
    "самогруз":        ["манипулятор-кран", "грузовой кран"],
    "манипулятор":     ["разгрузить", "разгрузка"],
    "эвакуатор":       ["эваку", "вывезти машину"],
    "бетононасос":     ["залить бетон", "бетон", "подача бетона", "бетоновоз"],
    "минитрактор":     ["трактор", "малый трактор", "огород"],
  };

  const matchedMachinery = new Set<number>();
  for (const m of catalogs.machinery) {
    const titleLc = m.title.toLowerCase();
    // Точная подстрока названия техники
    if (lc.includes(titleLc)) {
      matchedMachinery.add(m.id);
      continue;
    }
    // База слова без дефисов — "экскаватор-погрузчик" → проверяем "экскаватор"
    const bases = titleLc.split(/[-\s]+/);
    for (const base of bases) {
      if (base.length >= 5 && lc.includes(base)) {
        matchedMachinery.add(m.id);
        break;
      }
    }
    // Синонимы
    const syn = synonyms[titleLc];
    if (syn) {
      for (const s of syn) {
        if (lc.includes(s)) {
          matchedMachinery.add(m.id);
          break;
        }
      }
    }
  }

  // --- Категории: ищем по ключевым словам в title ---
  const matchedCategories = new Set<number>();
  for (const c of catalogs.categories) {
    const titleLc = c.title.toLowerCase();
    if (lc.includes(titleLc)) {
      matchedCategories.add(c.id);
      continue;
    }
    // Корни слов
    const root = titleLc.split(/\s+/)[0];
    if (root.length >= 5 && lc.includes(root)) {
      matchedCategories.add(c.id);
    }
  }

  // --- Город (с учётом падежей через корень слова + word boundary) ---
  // ВАЖНО: раньше использовали lc.includes(root) — давало false-positive
  // на «сочинить»→Сочи, «твердые»→Тверь, «перманент»→Пермь, «тулово»→Тула.
  // Теперь проверяем что корень окружён НЕ-буквенными символами (пробел,
  // пунктуация, начало/конец строки). Покрывает все падежи: «москв-е/а/ой/у».
  let city: string | null = null;
  // Кириллическая буква в JS regex — без флага u; используем явный класс.
  const letter = "а-яёa-z";
  for (const key of Object.keys(CITY_COORDS)) {
    let matched = false;
    if (key.length <= 4) {
      // Короткое сокращение («спб», «уфа», «сочи») — целое слово.
      const re = new RegExp(`(^|[^${letter}])${escapeRegex(key)}([^${letter}]|$)`, "i");
      matched = re.test(lc);
    } else if (key.includes(" ") || key.includes("-")) {
      // Многословное: «нижний новгород», «ростов-на-дону», «санкт-петербург».
      // Берём ПОСЛЕДНЕЕ слово как ключевое (для «нижний новгород» — это
      // «новгород»: в «Нижнем Новгороде» именно «новгороде» — главный
      // именной корень). Падежи режутся последней буквой.
      const parts = key.split(/[\s-]+/);
      const mainWord = parts[parts.length - 1];
      if (mainWord.length >= 5) {
        const root = mainWord.slice(0, mainWord.length - 1);
        const re = new RegExp(`(^|[^${letter}])${escapeRegex(root)}[${letter}]{0,3}([^${letter}]|$)`, "i");
        matched = re.test(lc);
      }
    } else {
      // Для длинных одиночных слов — корень без последней буквы.
      // Например «москв» из «москва»: матчит «в Москве», «у Москвы»,
      // но не «москвич» (защита границей).
      const root = key.slice(0, key.length - 1);
      const re = new RegExp(`(^|[^${letter}])${escapeRegex(root)}[${letter}]{0,3}([^${letter}]|$)`, "i");
      matched = re.test(lc);
    }
    if (matched) {
      city = (key === "питер") ? "Санкт-Петербург"
           : (key === "спб")   ? "Санкт-Петербург"
           : (key === "санкт-петербург") ? "Санкт-Петербург"
           : (key === "нижний новгород") ? "Нижний Новгород"
           : (key === "ростов-на-дону") ? "Ростов-на-Дону"
           : (key === "ростов") ? "Ростов-на-Дону"
           : key.charAt(0).toUpperCase() + key.slice(1);
      break;
    }
  }

  // --- Радиус: ТРЕБУЕМ явное «радиус N км» или «N км вокруг» ---
  // Раньше префикс был опциональный → «везти 30 км до объекта» сворачивался
  // в radius=20, что искажало поиск.
  let radius: number | null = null;
  const rMatch = lc.match(/(?:в\s+)?радиус[еа]?\s+(\d{1,3})\s*км|(\d{1,3})\s*км\s+вокруг/);
  if (rMatch) {
    const v = parseInt(rMatch[1] ?? rMatch[2], 10);
    if ([5, 10, 20, 50, 100].includes(v)) radius = v;
    else if (v < 10) radius = 10;
    else if (v < 30) radius = 20;
    else if (v < 75) radius = 50;
    else radius = 100;
  }

  // --- Даты: относительные, ДИАПАЗОНЫ, «DD месяца» словом, «DD.MM» ---
  const today = new Date(todayIso + "T00:00:00Z");
  const day = 24 * 3600 * 1000;
  let dateFrom: string | null = null;
  let dateTo:   string | null = null;
  const isoOf = (d: Date) => d.toISOString().slice(0, 10);

  // Месяц словом → номер (по основе). Порядок: «март» раньше «ма[йя]».
  const MONTHS: Array<[RegExp, number]> = [
    [/январ/, 1], [/феврал/, 2], [/март/, 3], [/апрел/, 4], [/ма[йя]/, 5],
    [/июн/, 6], [/июл/, 7], [/авгус/, 8], [/сентябр/, 9], [/октябр/, 10],
    [/ноябр/, 11], [/декабр/, 12],
  ];
  const monthNum = (s: string): number | null => {
    for (const [re, n] of MONTHS) if (re.test(s)) return n;
    return null;
  };
  // День+месяц → ISO. Если месяц уже прошёл в этом году — берём следующий год.
  const mkDate = (d: number, m: number): string | null => {
    if (!(d >= 1 && d <= 31 && m >= 1 && m <= 12)) return null;
    let y = today.getUTCFullYear();
    if (m < today.getUTCMonth() + 1) y += 1;
    return isoOf(new Date(Date.UTC(y, m - 1, d)));
  };
  // ВАЖНО: окончания месяцев — кириллический класс [а-яё]*, а НЕ \w*: в
  // JS-регексе \w не матчит кириллицу, и «июн\w*» съедало только «июн»,
  // оставляя «я» — это ломало разбор диапазонов «15 июня - 5 июля».
  const MO = "январ[а-яё]*|феврал[а-яё]*|март[а-яё]*|апрел[а-яё]*|ма[йя][а-яё]*|июн[а-яё]*|июл[а-яё]*|авгус[а-яё]*|сентябр[а-яё]*|октябр[а-яё]*|ноябр[а-яё]*|декабр[а-яё]*";

  // 1) Явные ДИАПАЗОНЫ дат (раньше всего).
  let mr: RegExpMatchArray | null;
  if ((mr = lc.match(/(\d{1,2})\.(\d{2})\s*[-–—]\s*(\d{1,2})\.(\d{2})/))) {
    // «15.06-20.06»
    dateFrom = mkDate(+mr[1], +mr[2]); dateTo = mkDate(+mr[3], +mr[4]);
  } else if ((mr = lc.match(new RegExp(`(\\d{1,2})\\s+(${MO})\\s*[-–—]\\s*(\\d{1,2})\\s+(${MO})`)))) {
    // «15 июня - 5 июля»
    const m1 = monthNum(mr[2]); const m2 = monthNum(mr[4]);
    if (m1 && m2) { dateFrom = mkDate(+mr[1], m1); dateTo = mkDate(+mr[3], m2); }
  } else if ((mr = lc.match(new RegExp(`с\\s+(\\d{1,2})\\s+(${MO})\\s+(?:по|до)\\s+(\\d{1,2})\\s+(${MO})`)))) {
    // «с 20 июня по 10 июля» (месяц после каждого числа)
    const m1 = monthNum(mr[2]); const m2 = monthNum(mr[4]);
    if (m1 && m2) { dateFrom = mkDate(+mr[1], m1); dateTo = mkDate(+mr[3], m2); }
  } else if ((mr = lc.match(new RegExp(`с\\s+(\\d{1,2})\\s+(?:по|до)\\s+(\\d{1,2})\\s+(${MO})`)))) {
    // «с 15 по 20 июня» (один месяц на оба числа)
    const m = monthNum(mr[3]);
    if (m) { dateFrom = mkDate(+mr[1], m); dateTo = mkDate(+mr[2], m); }
  } else if ((mr = lc.match(new RegExp(`(\\d{1,2})\\s*[-–—]\\s*(\\d{1,2})\\s+(${MO})`)))) {
    // «15-20 июня»
    const m = monthNum(mr[3]);
    if (m) { dateFrom = mkDate(+mr[1], m); dateTo = mkDate(+mr[2], m); }
  }

  // 2) Относительные дни — если диапазон не распознан.
  if (!dateFrom) {
    if (lc.includes("сегодня") && lc.includes("завтра") && !/не\s+(на\s+)?сегодня/.test(lc) && !lc.includes("послезавтра")) {
      dateFrom = isoOf(today);
      dateTo   = isoOf(new Date(today.getTime() + 1 * day));
    } else if (lc.includes("послезавтра")) {
      dateFrom = isoOf(new Date(today.getTime() + 2 * day));
    } else if (lc.includes("завтра")) {
      dateFrom = isoOf(new Date(today.getTime() + 1 * day));
    } else if (lc.includes("сегодня") && !/не\s+(на\s+)?сегодня/.test(lc)) {
      dateFrom = isoOf(today);
    } else if (/недел/.test(lc)) {
      dateFrom = isoOf(today);
      dateTo   = isoOf(new Date(today.getTime() + 7 * day));
    } else {
      const inN = lc.match(/через\s+(\d{1,2})\s+(день|дня|дней)/);
      if (inN) {
        dateFrom = isoOf(new Date(today.getTime() + parseInt(inN[1], 10) * day));
      } else {
        // 3) «DD месяца» словом («20 июня»).
        const mn = lc.match(new RegExp(`(\\d{1,2})\\s+(${MO})`));
        if (mn) { const m = monthNum(mn[2]); if (m) dateFrom = mkDate(+mn[1], m); }
        // 4) «DD.MM[.YYYY]» (2-значный месяц — чтобы «4.5» не было датой).
        if (!dateFrom) {
          const md = lc.match(/(\d{1,2})\.(\d{2})(?:\.(\d{2,4}))?/);
          if (md) {
            const d = parseInt(md[1], 10); const m = parseInt(md[2], 10);
            if (md[3]) {
              let y = parseInt(md[3], 10); if (y < 100) y += 2000;
              if (d >= 1 && d <= 31 && m >= 1 && m <= 12) dateFrom = isoOf(new Date(Date.UTC(y, m - 1, d)));
            } else {
              dateFrom = mkDate(d, m);
            }
          }
        }
      }
    }
  }

  // --- min_rating (обе роли: у исполнителя это рейтинг ЗАКАЗЧИКА, у заказчика —
  //     рейтинг ИСПОЛНИТЕЛЯ) и max_price (только заказчик — у заказов цены нет) ---
  let minRating:  number | null = null;
  let maxPrice:   number | null = null;
  // «рейтинг»/«рейтингом»/«оценка не ниже» + «от/выше» + число (4.5 или 4,5).
  // \D{0,22}? — любые НЕ-цифры между словом и числом (падежи, «от», пробелы, а
  // также «заказчика»/«исполнителя» между: «рейтингом заказчика от 4»).
  const rMr = lc.match(/(?:рейтинг|оценк)\D{0,22}?(\d(?:[.,]\d)?)/);
  if (rMr) {
    const v = parseFloat(rMr[1].replace(",", "."));
    if (Number.isFinite(v) && v >= 1 && v <= 5) minRating = v;
  }
  if (app === "customer") {
    const rMp = lc.match(/(?:до|не\s+более|не\s+дороже|максимум)\s+(\d{2,5})\s*(?:руб|₽|р\.?)\s*(?:в\s*час|\/час|за\s*час)?/);
    if (rMp) maxPrice = parseFloat(rMp[1]);
    if (lc.includes("недорого") || lc.includes("дешёво") || lc.includes("дешево")) {
      maxPrice = maxPrice ?? 1500;
    }
  }

  // Относительные уточнения (ответ на «давайте сузим»): «поближе»/«поблизости»
  // → узкий радиус, «подальше» → широкий; «подешевле» (заказчик) → потолок цены.
  // Грубо, но лучше, чем молча проигнорировать наречие. В рамках сессии радиус
  // считается от уже накопленной локации (город/карточка).
  // Только сравнительные «поближе/ближе» (а не базовое «поблизости» — оно про
  // обычную близость к карточке и не должно ужимать радиус до 10).
  if (/поближе|(^|\s)ближе/.test(lc)) radius = radius ?? 10;
  else if (/подальше|(^|\s)дальше/.test(lc)) radius = radius ?? 100;
  if (app === "customer" && /подешевле|подешевл|дешевле/.test(lc)) {
    maxPrice = maxPrice ?? 1500;
  }

  return {
    machinery_ids: Array.from(matchedMachinery),
    category_ids:  Array.from(matchedCategories),
    city,
    radius_km:     radius,
    date_from:     dateFrom,
    date_to:       dateTo,
    min_rating:    minRating,
    max_price_per_hour: maxPrice,
  };
}

// ---------------------------------------------------------------------
// 1b. Старый LLM-парсер оставлен как запасной (на случай если keyword
//     ничего не нашёл — для редких/нестандартных формулировок).
//     Сейчас не используется по умолчанию.
// ---------------------------------------------------------------------
function buildFilterPrompt(
  app: "executor" | "customer",
  catalogs: { machinery: Array<{ id: number; title: string }>; categories: Array<{ id: number; title: string }> },
  todayIso: string,
): string {
  const machineryList = catalogs.machinery.map((m) => `${m.id}:${m.title}`).join(", ");
  const categoryList  = catalogs.categories.map((c) => `${c.id}:${c.title}`).join(", ");
  const extra  = app === "customer"
    ? ',"min_rating":num|null,"max_price_per_hour":num|null'
    : "";

  // Промпт сделан максимально коротким — длинные инструкции
  // YandexGPT хуже исполняет (видно в наших тестах).
  return `Извлекай параметры поиска из текста и возвращай ТОЛЬКО JSON, без markdown.

Сегодня: ${todayIso}.
Техника: ${machineryList}.
Категории: ${categoryList}.

Формат: {"machinery_ids":[int],"category_ids":[int],"city":str|null,"radius_km":int|null,"date_from":"YYYY-MM-DD"|null,"date_to":"YYYY-MM-DD"|null${extra}}

Примеры:
"экскаватор в Москве" → {"machinery_ids":[2,4],"category_ids":[],"city":"Москва","radius_km":null,"date_from":null,"date_to":null${app === "customer" ? ',"min_rating":null,"max_price_per_hour":null' : ""}}
"автокран Питер завтра" → {"machinery_ids":[7],"category_ids":[],"city":"Санкт-Петербург","radius_km":null,"date_from":"${nextDay(todayIso,1)}","date_to":"${nextDay(todayIso,1)}"${app === "customer" ? ',"min_rating":null,"max_price_per_hour":null' : ""}}

"экскаватор" → 2 и 4. "Питер"/"СПб" → "Санкт-Петербург". Не упомянуто → null/[].`;
}

function nextDay(iso: string, plus: number): string {
  const d = new Date(iso + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + plus);
  return d.toISOString().slice(0, 10);
}

// ---------------------------------------------------------------------
// 2. Промпт для комментатора.
// ---------------------------------------------------------------------
function buildCommentPrompt(
  app: "executor" | "customer",
  userText: string,
  items: unknown[],
): string {
  const target  = app === "executor" ? "заказов" : "исполнителей";
  const itemStr = JSON.stringify(items).slice(0, 4000);

  return `Запрос пользователя: «${userText}»

Найдено ${items.length} ${target}. Вот данные:
${itemStr}

Сформулируйте короткий комментарий (1-3 предложения), какие варианты лучше всего подходят. Если ничего не найдено — мягко скажите об этом и предложите расширить поиск (другой регион, другая техника, другие даты). Не перечисляйте все карточки — упомяните 1-2 самых интересных. Без markdown, без буллетов.`;
}

// ---------------------------------------------------------------------
// 3. Геокодинг города через DaData — упрощённый: не дёргаем DaData
//    (там лимиты), просто отдаём в LLM координаты крупнейших городов
//    через словарь. Если города нет — пропускаем гео-фильтр.
//    В будущем можно прикрутить настоящий DaData hook.
// ---------------------------------------------------------------------
const CITY_COORDS: Record<string, { lat: number; lng: number }> = {
  // Топ-15 городов-миллионников + крупные региональные центры. На MVP
  // хватит; в дальнейшем стоит вынести в БД и/или подключить DaData.
  "москва":             { lat: 55.7558, lng: 37.6173 },
  "санкт-петербург":    { lat: 59.9311, lng: 30.3609 },
  "спб":                { lat: 59.9311, lng: 30.3609 },
  "питер":              { lat: 59.9311, lng: 30.3609 },
  "новосибирск":        { lat: 55.0084, lng: 82.9357 },
  "екатеринбург":       { lat: 56.8389, lng: 60.6057 },
  "нижний новгород":    { lat: 56.2965, lng: 43.9361 },
  "казань":             { lat: 55.8304, lng: 49.0661 },
  "челябинск":          { lat: 55.1644, lng: 61.4368 },
  "омск":               { lat: 54.9885, lng: 73.3242 },
  "самара":             { lat: 53.1959, lng: 50.1002 },
  "ростов-на-дону":     { lat: 47.2357, lng: 39.7015 },
  "ростов":             { lat: 47.2357, lng: 39.7015 }, // короткое название
  "уфа":                { lat: 54.7388, lng: 55.9721 },
  "красноярск":         { lat: 56.0153, lng: 92.8932 },
  "пермь":              { lat: 58.0105, lng: 56.2502 },
  "воронеж":            { lat: 51.6754, lng: 39.2088 },
  "волгоград":          { lat: 48.7080, lng: 44.5133 },
  "краснодар":          { lat: 45.0355, lng: 38.9753 },
  "саратов":            { lat: 51.5331, lng: 46.0342 },
  "тюмень":             { lat: 57.1530, lng: 65.5343 },
  "тольятти":           { lat: 53.5070, lng: 49.4204 },
  "ижевск":             { lat: 56.8526, lng: 53.2045 },
  "барнаул":            { lat: 53.3548, lng: 83.7698 },
  "ульяновск":          { lat: 54.3142, lng: 48.4031 },
  "иркутск":            { lat: 52.2870, lng: 104.3050 },
  "хабаровск":          { lat: 48.4647, lng: 135.0719 },
  "ярославль":          { lat: 57.6261, lng: 39.8845 },
  "владивосток":        { lat: 43.1056, lng: 131.8735 },
  "махачкала":          { lat: 42.9849, lng: 47.5046 },
  "томск":              { lat: 56.4847, lng: 84.9482 },
  "оренбург":           { lat: 51.7682, lng: 55.0974 },
  "кемерово":           { lat: 55.3540, lng: 86.0883 },
  "новокузнецк":        { lat: 53.7596, lng: 87.1216 },
  "рязань":             { lat: 54.6296, lng: 39.7423 },
  "астрахань":          { lat: 46.3497, lng: 48.0408 },
  "пенза":              { lat: 53.2007, lng: 45.0046 },
  "липецк":             { lat: 52.6088, lng: 39.5994 },
  "тула":               { lat: 54.1961, lng: 37.6182 },
  "киров":              { lat: 58.6035, lng: 49.6679 },
  "чебоксары":          { lat: 56.1322, lng: 47.2519 },
  "калининград":        { lat: 54.7104, lng: 20.4522 },
  "брянск":             { lat: 53.2434, lng: 34.3641 },
  "курск":              { lat: 51.7373, lng: 36.1873 },
  "иваново":            { lat: 56.9952, lng: 40.9762 },
  "магнитогорск":       { lat: 53.4078, lng: 58.9794 },
  "тверь":              { lat: 56.8587, lng: 35.9176 },
  "ставрополь":         { lat: 45.0445, lng: 41.9690 },
  "белгород":           { lat: 50.5953, lng: 36.5872 },
  "архангельск":        { lat: 64.5401, lng: 40.5433 },
  "владимир":           { lat: 56.1290, lng: 40.4070 },
  "сочи":               { lat: 43.5855, lng: 39.7231 },
  "якутск":             { lat: 62.0276, lng: 129.7320 },
};

function geocodeCity(city: string | null): { lat: number; lng: number } | null {
  if (!city) return null;
  const key = city.toLowerCase().trim().replace(/^(г\.|город)\s*/, "");
  return CITY_COORDS[key] ?? null;
}

// ---------------------------------------------------------------------
// 3b. DaData fallback для городов, которых нет в CITY_COORDS.
//     Кэшируем в БД (geo_cities_cache) на 30 дней — таблица создаётся
//     миграцией 021. Если DaData не нашёл город — запоминаем «не найдено»,
//     чтобы не дёргать API повторно при том же запросе.
//
//     Передаём adminClient через параметр — не хотим импортировать
//     supabase-js в общий код.
// ---------------------------------------------------------------------
type SupaLike = {
  from: (t: string) => {
    select: (s: string) => {
      eq: (col: string, val: string) => { maybeSingle: () => Promise<{ data: unknown }> };
    };
    upsert: (row: unknown, opts?: unknown) => Promise<unknown>;
  };
};

async function geocodeCityViaDaData(
  city: string,
  adminClient: SupaLike,
): Promise<{ lat: number; lng: number } | null> {
  if (!DADATA_TOKEN) return null;
  const key = city.toLowerCase().trim().replace(/^(г\.|город)\s*/, "");
  if (!key) return null;

  // 1) Кэш
  try {
    const { data: row } = await adminClient
      .from("geo_cities_cache")
      .select("lat, lng, found")
      .eq("city_key", key)
      .maybeSingle();
    if (row) {
      const r = row as { lat: number | null; lng: number | null; found: boolean };
      if (!r.found) return null;
      if (typeof r.lat === "number" && typeof r.lng === "number") {
        return { lat: r.lat, lng: r.lng };
      }
    }
  } catch (_) { /* кэш необязательный */ }

  // 2) DaData. Эндпоинт «suggest address» с granular=city, чтобы получить
  //    geo_lat/geo_lon только по уровню города. Лимит RPS лояльный
  //    (10 000 запросов в день на бесплатном тарифе).
  let lat: number | null = null;
  let lng: number | null = null;
  try {
    const resp = await fetch("https://suggestions.dadata.ru/suggestions/api/4_1/rs/suggest/address", {
      method: "POST",
      headers: {
        "Content-Type":  "application/json",
        "Accept":        "application/json",
        "Authorization": `Token ${DADATA_TOKEN}`,
      },
      body: JSON.stringify({
        query: city,
        count: 1,
        from_bound: { value: "city" },
        to_bound:   { value: "city" },
        locations:  [{ country: "Россия" }],
      }),
    });
    if (resp.ok) {
      const json = await resp.json() as { suggestions?: Array<{ data?: { geo_lat?: string; geo_lon?: string } }> };
      const s = json.suggestions?.[0]?.data;
      if (s?.geo_lat && s?.geo_lon) {
        const la = parseFloat(s.geo_lat);
        const lo = parseFloat(s.geo_lon);
        if (Number.isFinite(la) && Number.isFinite(lo)) {
          lat = la; lng = lo;
        }
      }
    }
  } catch (e) {
    console.warn("[ai-search] dadata fetch failed:", e);
  }

  // 3) Кэшируем результат (даже отрицательный — found=false на 30 дней,
  //    чтобы не дёргать DaData при повторных «найди мне в Зажопинске»)
  try {
    await adminClient.from("geo_cities_cache").upsert({
      city_key: key,
      display:  city,
      lat:      lat,
      lng:      lng,
      found:    lat !== null && lng !== null,
      expires_at: new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString(),
    }, { onConflict: "city_key" });
  } catch (_) { /* кэш необязательный */ }

  return (lat !== null && lng !== null) ? { lat, lng } : null;
}

/** Из текста выдёргиваем кандидат на «название города» по простому regex.
 *  Берём первое сочетание «в/из/около/г.» + слово с большой буквы.
 *  Чтобы не дёргать DaData на каждое «У Игоря болит голова», используем
 *  более конкретные предлоги (в/во/из/город/г.) — у/около часто стоят
 *  перед именами и не дают полезных кандидатов. */
function extractCityCandidate(text: string): string | null {
  // «в Москве», «из Питера», «город Магадан», «г. Норильск»
  const m = text.match(/(?:^|[^а-яё])(?:в|во|из|г\.|город)\s+([А-ЯЁ][а-яё]{2,}(?:[\s\-][А-ЯЁ][а-яё]{2,}){0,2})/u);
  if (m && m[1]) return m[1];
  // Просто слово с большой буквы в начале строки — возможно, город сам по себе.
  // Но только если после нет «-овича/-евича/-ин/-ская» (явных морфем имени).
  const m2 = text.match(/^([А-ЯЁ][а-яё]{2,}(?:[\s\-][А-ЯЁ][а-яё]{2,}){0,2})/u);
  if (m2 && m2[1]) {
    if (!/(?:ович|евич|овна|евна)$/i.test(m2[1])) return m2[1];
  }
  return null;
}

// ---------------------------------------------------------------------
// 4. Парсинг ответа LLM в строгий JSON.
// ---------------------------------------------------------------------
type ParsedFilter = {
  machinery_ids: number[];
  category_ids:  number[];
  city:          string | null;
  radius_km:     number | null;
  date_from:     string | null;
  date_to:       string | null;
  min_rating:        number | null;
  max_price_per_hour: number | null;
};

function safeParseFilter(text: string): ParsedFilter | null {
  // Попытка 1: clean JSON
  let candidate = text.trim();
  // Если модель завернула в ```json ... ```
  const fenced = candidate.match(/```(?:json)?\s*([\s\S]+?)\s*```/);
  if (fenced) candidate = fenced[1].trim();
  // Найти первую { и последнюю }
  const first = candidate.indexOf("{");
  const last  = candidate.lastIndexOf("}");
  if (first < 0 || last < 0 || last <= first) return null;
  candidate = candidate.slice(first, last + 1);

  try {
    const raw = JSON.parse(candidate);
    return {
      machinery_ids: Array.isArray(raw.machinery_ids)
        ? raw.machinery_ids.filter((v: unknown) => typeof v === "number")
        : [],
      category_ids: Array.isArray(raw.category_ids)
        ? raw.category_ids.filter((v: unknown) => typeof v === "number")
        : [],
      city:      typeof raw.city === "string" ? raw.city : null,
      radius_km: typeof raw.radius_km === "number" ? raw.radius_km : null,
      date_from: typeof raw.date_from === "string" ? raw.date_from : null,
      date_to:   typeof raw.date_to   === "string" ? raw.date_to   : null,
      min_rating: typeof raw.min_rating === "number" ? raw.min_rating : null,
      max_price_per_hour: typeof raw.max_price_per_hour === "number" ? raw.max_price_per_hour : null,
    };
  } catch (_) {
    return null;
  }
}

/** Слить накопленный фильтр прошлых сообщений с новым: новые непустые
 *  значения побеждают, не указанное в новом — берётся из прошлого. Так
 *  «трактор» → «а в Москве?» даёт {трактор, Москва}, а не теряет технику. */
function mergeFilters(prev: ParsedFilter, cur: ParsedFilter): ParsedFilter {
  return {
    machinery_ids: cur.machinery_ids.length ? cur.machinery_ids : prev.machinery_ids,
    category_ids:  cur.category_ids.length  ? cur.category_ids  : prev.category_ids,
    city:          cur.city      ?? prev.city,
    radius_km:     cur.radius_km ?? prev.radius_km,
    date_from:     cur.date_from ?? prev.date_from,
    date_to:       cur.date_to   ?? prev.date_to,
    min_rating:         cur.min_rating         ?? prev.min_rating,
    max_price_per_hour: cur.max_price_per_hour ?? prev.max_price_per_hour,
  };
}

// =====================================================================
// 5. Главный handler
// =====================================================================
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST")    return jsonResponse(405, { error: "method_not_allowed" });

  // --- Auth ---
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return jsonResponse(401, { error: "unauthorized" });

  const userClient: SupabaseClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth:   { persistSession: false },
  });
  const adminClient: SupabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const { data: userRes, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userRes?.user) return jsonResponse(401, { error: "unauthorized" });
  const userId = userRes.user.id;

  // --- Body ---
  let body: { session_id?: string; message?: string; app?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "invalid_json" });
  }
  const message = typeof body.message === "string" ? body.message.trim() : "";
  const app     = body.app === "executor" ? "executor" : body.app === "customer" ? "customer" : null;
  if (!message)              return jsonResponse(400, { error: "empty_message" });
  if (message.length > 1000) return jsonResponse(400, { error: "message_too_long" });
  if (!app)                  return jsonResponse(400, { error: "invalid_app" });

  // --- Квота ---
  const { data: quotaRows, error: quotaErr } = await userClient.rpc("ai_check_quota");
  if (quotaErr) {
    console.error("[ai-search] quota check failed:", quotaErr);
    return jsonResponse(500, { error: "internal" });
  }
  const quota = Array.isArray(quotaRows) ? quotaRows[0] : quotaRows;
  if (!quota?.allowed) {
    return jsonResponse(402, {
      error:   "quota_exceeded",
      message: REPLY_QUOTA_EXCEEDED,
      quota:   { used: quota?.used ?? 0, total: quota?.quota ?? 0 },
    });
  }

  // --- Сессия ---
  let sessionId = body.session_id ?? null;
  // Накопленный фильтр прошлых сообщений сессии — для уточняющего поиска
  // («трактор» → «а в Москве?» = трактор в Москве, а не «любое в Москве»).
  let prevFilter: ParsedFilter | null = null;
  if (sessionId) {
    const { data: ses } = await adminClient
      .from("ai_sessions")
      .select("id, user_id, app, kind, state")
      .eq("id", sessionId)
      .maybeSingle();
    if (!ses || ses.user_id !== userId || ses.app !== app || ses.kind !== "search") {
      sessionId = null;
    } else {
      const lf = (ses.state as { last_filter?: ParsedFilter } | null)?.last_filter;
      if (lf && typeof lf === "object") prevFilter = lf;
    }
  }
  if (!sessionId) {
    const { data: newSes, error } = await adminClient.from("ai_sessions").insert({
      user_id: userId,
      app,
      kind:    "search",
      title:   message.slice(0, 80),
    }).select("id").single();
    if (error || !newSes) {
      console.error("[ai-search] session create failed:", error);
      return jsonResponse(500, { error: "internal" });
    }
    sessionId = newSes.id;
  }

  // --- Логируем user-сообщение ---
  await adminClient.from("ai_messages").insert({
    session_id: sessionId,
    role:       "user",
    content:    message,
  });

  // --- Справочники ---
  const { data: catalogsRaw, error: catErr } = await adminClient.rpc("ai_get_search_catalogs");
  if (catErr || !catalogsRaw) {
    console.error("[ai-search] catalogs failed:", catErr);
    return jsonResponse(500, { error: "internal" });
  }
  const catalogs = catalogsRaw as {
    machinery:  Array<{ id: number; title: string }>;
    categories: Array<{ id: number; title: string }>;
  };

  // Тарифы — для оценки стоимости.
  await loadTariffs(adminClient);

  // --- Keyword-парсер фильтра (надёжный, без LLM) ---
  // «Сегодня» считаем по Москве (UTC+3, без перехода на лето) — как дневной
  // лимит и вся остальная логика дат. Иначе вечером по UTC «сегодня»/«неделя»
  // съезжали на день назад.
  const todayIso = new Date(Date.now() + 3 * 3600 * 1000).toISOString().slice(0, 10);
  let parsed = keywordParseFilter(message, app, catalogs, todayIso);

  // Если в словаре города не нашлось — пробуем выдернуть regex'ом и
  // спросить DaData (Кызыл / Магадан / Норильск и т.п.)
  if (!parsed.city) {
    const candidate = extractCityCandidate(message);
    if (candidate) {
      const coords = await geocodeCityViaDaData(candidate, adminClient as unknown as SupaLike);
      if (coords) {
        parsed.city = candidate;
      }
    }
  }

  // Уточняющий поиск: дополняем новый разбор тем, что собрали раньше в
  // этой сессии. Новое побеждает, не указанное — берётся из прошлого.
  if (prevFilter) parsed = mergeFilters(prevFilter, parsed);

  // --- Умный поиск для исполнителя: достраиваем запрос из его профиля ---
  // Если он не назвал технику — ищем заказы под технику ИЗ ЕГО УСЛУГ.
  // Если не назвал место — ищем рядом с его карточкой (в его радиусе).
  // Так «есть заказы поблизости на неделю?» сразу даёт релевантную выдачу.
  // «везде/по всей России» — отключает привязку к карточке.
  const lcMsg = message.toLowerCase();
  const wantsEverywhere = /везде|по всей|любой город|любом город|вся росс|всю росс|по росси|в других город/.test(lcMsg);
  let execCardCoords: { lat: number; lng: number } | null = null;
  let execCardRadius: number | null = null;
  let execHasServices = true;
  if (app === "executor") {
    const [svcRes, cardRes] = await Promise.all([
      adminClient.from("services").select("machinery_ids")
        .eq("executor_id", userId).eq("is_paid", true).eq("is_archived", false),
      adminClient.from("executor_cards").select("location_lat, location_lng, radius_km")
        .eq("user_id", userId).maybeSingle(),
    ]);
    const mset = new Set<number>();
    for (const r of (svcRes.data ?? [])) {
      for (const id of ((r as { machinery_ids?: number[] }).machinery_ids ?? [])) mset.add(id);
    }
    execHasServices = mset.size > 0;
    if (parsed.machinery_ids.length === 0 && mset.size > 0) {
      parsed.machinery_ids = Array.from(mset);   // его техника
    }
    const card = cardRes.data as { location_lat?: number; location_lng?: number; radius_km?: number } | null;
    if (card && typeof card.location_lat === "number" && typeof card.location_lng === "number") {
      execCardCoords = { lat: card.location_lat, lng: card.location_lng };
      execCardRadius = typeof card.radius_km === "number" ? card.radius_km : null;
    }
  }

  // Дамми-completion для счётчиков (парсинг не тратит токены).
  const filterCompletion = { tokensIn: 0, tokensOut: 0, modelVersion: "keyword", text: "", finishReason: "ok" };

  // Если из запроса не извлеклось НИЧЕГО — не идём в SQL (иначе SELECT без
  // фильтра вернёт случайные карточки, а юзер прочитает «нашёл 8 заказов»).
  // Это случай типа «найди мне любовь» или «сколько стоит подписка».
  const emptyFilter = parsed.machinery_ids.length === 0
    && parsed.category_ids.length === 0
    && !parsed.city
    && !parsed.date_from
    && !parsed.date_to
    && parsed.min_rating == null            // поиск по одному рейтингу — валиден
    && parsed.max_price_per_hour == null;   // поиск по одной цене — валиден
  if (emptyFilter) {
    const msg = "Уточните, пожалуйста: какая техника, в каком городе, на какие даты? Можно прислать запрос голосом.";
    // Атомарно: запись ответа + списание квоты.
    await adminClient.rpc("ai_finalize_reply", {
      p_session_id:   sessionId,
      p_user_id:      userId,
      p_content:      msg,
      p_data:         { kind: "needs_more_info" },
      p_tokens_in:    0,
      p_tokens_out:   0,
      p_model:        "keyword",
      p_cost_kopecks: 0,
    });
    return jsonResponse(200, {
      session_id:  sessionId,
      reply:       msg,
      data:        { kind: "needs_more_info" },
      filter_used: parsed,
      model:       "keyword",
      cached:      false,
      quota:       { used: (quota.used ?? 0) + 1, total: quota.quota },
    });
  }

  // --- SQL: вызов соответствующего RPC ---
  // Сначала пробуем точный CITY_COORDS, затем DaData (cache).
  let coords = geocodeCity(parsed.city);
  if (!coords && parsed.city) {
    coords = await geocodeCityViaDaData(parsed.city, adminClient as unknown as SupaLike);
  }
  // Исполнитель не указал город — ищем рядом с его карточкой (в его радиусе).
  let usedCardLocation = false;
  if (!coords && app === "executor" && !wantsEverywhere && execCardCoords) {
    coords = execCardCoords;
    usedCardLocation = true;
  }
  const searchRadius = parsed.radius_km
    ?? (usedCardLocation ? (execCardRadius ?? 50) : (coords ? 50 : null));
  let items: unknown[] = [];
  let kind: string     = app === "executor" ? "order_cards" : "executor_cards";

  // ВАЖНО: p_user_id передаём явно. Через service_role auth.uid()=NULL
  // и фильтр «не свои заказы/исполнители» отключается → юзер видит свои
  // же объявления в выдаче. Миграция 020 добавила параметр.
  if (app === "executor") {
    // Исполнитель ищет ЗАКАЗЫ
    const { data, error } = await adminClient.rpc("ai_search_orders", {
      p_machinery_ids: parsed.machinery_ids.length ? parsed.machinery_ids : null,
      p_category_ids:  parsed.category_ids.length  ? parsed.category_ids  : null,
      p_lat:           coords?.lat ?? null,
      p_lng:           coords?.lng ?? null,
      p_radius_km:     searchRadius,
      p_date_from:     parsed.date_from,
      p_date_to:       parsed.date_to,
      p_limit:         9,
      p_user_id:       userId,
      p_min_customer_rating: parsed.min_rating,
    });
    if (error) {
      console.error("[ai-search] orders RPC failed:", error?.code);
      return jsonResponse(500, { error: "internal" });
    }
    items = Array.isArray(data) ? data : [];
  } else {
    // Заказчик ищет ИСПОЛНИТЕЛЕЙ
    const { data, error } = await adminClient.rpc("ai_search_executors", {
      p_machinery_ids: parsed.machinery_ids.length ? parsed.machinery_ids : null,
      p_category_ids:  parsed.category_ids.length  ? parsed.category_ids  : null,
      p_lat:           coords?.lat ?? null,
      p_lng:           coords?.lng ?? null,
      p_radius_km:     searchRadius,
      p_min_rating:    parsed.min_rating,
      p_max_price_per_hour: parsed.max_price_per_hour,
      p_limit:         9,
      p_user_id:       userId,
    });
    if (error) {
      console.error("[ai-search] executors RPC failed:", error?.code);
      return jsonResponse(500, { error: "internal" });
    }
    items = Array.isArray(data) ? data : [];
  }

  // Лимит 9 (на 1 больше, чем показываем) — чтобы понять «есть ли ещё».
  // Если нашлось больше, чем показываем, предложим сузить уточняющим вопросом.
  const SHOW = 8;
  const total = items.length;
  const manyResults = total > SHOW;
  const shown = items.slice(0, SHOW);

  // --- LLM #2: комментарий (по показываемым карточкам) ---
  const commentMessages: YandexMessage[] = [
    { role: "system", text: systemPromptFor(app) },
    { role: "user",   text: buildCommentPrompt(app, message, shown) },
  ];

  let commentCompletion;
  try {
    commentCompletion = await yandexCompletion(commentMessages, {
      model:       "lite",
      temperature: 0.3,
      maxTokens:   400,
    });
  } catch (e) {
    if (e instanceof YandexContentFilterError) {
      // Если содержимое заблокировал фильтр — всё равно вернём карточки.
      commentCompletion = { text: total > 0
        ? `Нашёл ${shown.length}${manyResults ? "+" : ""} ${app === "executor" ? "подходящих заказов" : "подходящих исполнителей"}.`
        : "Подходящих вариантов не найдено. Попробуйте расширить поиск.",
        tokensIn: 0, tokensOut: 0, modelVersion: "fallback", finishReason: "fallback" };
    } else {
      console.error("[ai-search] comment LLM failed (name=" + (e as Error)?.name + ")");
      return jsonResponse(500, { error: "internal" });
    }
  }

  let replyText = commentCompletion.text.trim();
  // ТЗ: «сервис в зависимости от запроса может предложить уточнить данные
  // (например, в какой локации вы ищете?)». Логика:
  //  - много результатов → конкретный уточняющий вопрос (примеры по роли);
  //  - иначе, если не назван город → мягко предложить указать локацию.
  if (manyResults) {
    const examples = app === "executor"
      ? "«в радиусе 10 км», «на эту неделю», «на конкретную дату» или «заказчик с рейтингом от 4»"
      : "«до 2000 руб/час», «рейтинг от 4.5» или «в радиусе 15 км»";
    replyText = `Нашёл много подходящих — показываю первые. Чтобы выбрать удобнее, давайте сузим: скажите, например, ${examples}.`;
  } else if (total > 0 && !parsed.city && !wantsEverywhere) {
    // Город не назван — предлагаем уточнить локацию (как в примере ТЗ).
    const hint = app === "executor"
      ? (usedCardLocation
          ? "Показываю заказы рядом с вашей карточкой — назовите город, если ищете в другом месте."
          : "Назовите город, чтобы искать заказы в нужном месте.")
      : "Чтобы сузить, назовите город, где ищете исполнителя.";
    replyText = (replyText ? replyText + " " : "") + hint;
  }

  // Исполнитель ищет технику, по которой у него НЕТ опубликованной услуги:
  // откликнуться на такие заказы нельзя (форма отклика требует совпадения
  // техники услуги с техникой заказа). Предупреждаем сразу, чтобы не тратил
  // время и понимал — надо создать услугу с этой техникой.
  if (app === "executor" && parsed.machinery_ids.length > 0 && total > 0) {
    const { data: svcRows, error: svcErr } = await adminClient
      .from("services")
      .select("machinery_ids")
      .eq("executor_id", userId)
      .eq("is_paid", true)
      .eq("is_archived", false);
    if (!svcErr) {
      const mine = new Set<number>();
      for (const r of (svcRows ?? [])) {
        for (const id of ((r as { machinery_ids?: number[] }).machinery_ids ?? [])) mine.add(id);
      }
      const haveOverlap = parsed.machinery_ids.some((id) => mine.has(id));
      if (!haveOverlap) {
        replyText = (replyText ? replyText + " " : "") +
          "Учтите: чтобы откликнуться на такой заказ, нужна опубликованная услуга с этой техникой — у вас её пока нет. Создайте услугу с ней в «Мои услуги».";
      }
    }
  }

  // Исполнитель без единой услуги видит заказы, но откликнуться не сможет —
  // подсказываем добавить услугу (когда технику он не называл — иначе сработает
  // предупреждение выше).
  if (app === "executor" && !execHasServices && total > 0 && parsed.machinery_ids.length === 0) {
    replyText = (replyText ? replyText + " " : "") +
      "Чтобы откликаться на заказы, нужна опубликованная услуга с вашей техникой — у вас её пока нет. Добавьте её в «Мои услуги».";
  }

  const ids = (shown as Array<{ id?: string; user_id?: string }>)
    .map((it) => it.id ?? it.user_id ?? null)
    .filter((v): v is string => typeof v === "string");

  // Запоминаем итоговый фильтр в сессии — следующее сообщение его уточнит.
  await adminClient.from("ai_sessions")
    .update({ state: { last_filter: parsed } })
    .eq("id", sessionId)
    .eq("user_id", userId);   // защёлка владельца (defense-in-depth)

  // --- Атомарно: ответ ассистента + квота одной транзакцией ---
  await adminClient.rpc("ai_finalize_reply", {
    p_session_id:   sessionId,
    p_user_id:      userId,
    p_content:      replyText,
    p_data:         { kind, ids, items: shown, filter: parsed },
    p_tokens_in:    filterCompletion.tokensIn + commentCompletion.tokensIn,
    p_tokens_out:   filterCompletion.tokensOut + commentCompletion.tokensOut,
    p_model:        commentCompletion.modelVersion,
    p_cost_kopecks: estimateCostKopecks(commentCompletion.tokensIn, commentCompletion.tokensOut, "lite"),
  });

  return jsonResponse(200, {
    session_id:  sessionId,
    reply:       replyText,
    data:        { kind, ids, items: shown },
    filter_used: parsed,
    model:       commentCompletion.modelVersion,
    cached:      false,
    quota:       { used: (quota.used ?? 0) + 1, total: quota.quota },
  });
});

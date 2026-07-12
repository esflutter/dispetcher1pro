import 'package:supabase_flutter/supabase_flutter.dart';

/// Глобальные настройки из таблицы `public.settings`. Загружаются один
/// раз при первом обращении и держатся в памяти. RLS: анониму доступны
/// только до-логиновые ключи (цены, ссылки), операционные ключи и токен
/// карт — только authenticated (миграция 078).
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  SupabaseClient get _client => Supabase.instance.client;

  Map<String, dynamic>? _cache;

  // Дедуп параллельных загрузок: два геттера (или warmup + reload на старте)
  // не должны слать два запроса и перетирать кэш друг друга в произвольном
  // порядке — все ждут один и тот же сетевой вызов.
  Future<void>? _inFlight;

  Future<void> _load() {
    if (_cache != null) return Future<void>.value();
    final Future<void> f = _inFlight ??= _doLoad();
    return f;
  }

  Future<void> _doLoad() async {
    try {
      final List<Map<String, dynamic>> rows =
          await _client.from('settings').select('key, value');
      _cache = <String, dynamic>{
        for (final Map<String, dynamic> r in rows) r['key'] as String: r['value'],
      };
    } catch (_) {
      // Кэш НЕ фиксируем пустым: офлайн-старт раньше навсегда (до перезапуска)
      // оставлял приложение на зашитых фолбэках. Оставляем null — следующий
      // геттер повторит запрос, когда сеть появится.
    } finally {
      _inFlight = null;
    }
  }

  /// Настройки проверки обновлений: минимально допустимая версия (ниже неё —
  /// настойчивое окно), последняя версия и переключатель «рекомендуем
  /// обновить». Мягкое окно показывается ТОЛЬКО когда переключатель включён
  /// И версия ниже последней. Дефолты («0.0.0» / выключено) — окно не
  /// появляется, пока админ не задаст значения. Парсинг терпим к хранению
  /// значения как строки и как числа.
  Future<({String min, String latest, bool recommend})> appVersions() async {
    await _load();
    final String min =
        (_values['app.pro_min_version']?.toString() ?? '0.0.0').trim();
    final String latest =
        (_values['app.pro_latest_version']?.toString() ?? '0.0.0').trim();
    final bool recommend =
        (num.tryParse('${_values['app.pro_recommend_update'] ?? 0}') ?? 0) != 0;
    return (min: min, latest: latest, recommend: recommend);
  }

  /// Прогревает кэш настроек на старте приложения. Вызывается из `main()`
  /// fire-and-forget вместе с CatalogService.warmup() — после этого все
  /// геттеры возвращают значения мгновенно, без сетевого запроса.
  Future<void> warmup() => _load();

  /// Сбросить кэш и перечитать настройки. Зовётся ПОСЛЕ входа: прогрев в
  /// main() может идти под анонимной ролью и не получает ключи, видимые
  /// только authenticated (токен карт map.mapbox_token). Сначала дожидаемся
  /// уже летящей загрузки (если есть) — иначе её поздний ответ перетёр бы
  /// свежий авторизованный кэш — и только потом перечитываем под токеном.
  Future<void> reload() async {
    final Future<void>? inflight = _inFlight;
    if (inflight != null) {
      try {
        await inflight;
      } catch (_) {/* неудача старой загрузки не мешает новой */}
    }
    _cache = null;
    await _load();
  }

  /// Снимок кэша для геттеров: после неудачной загрузки кэш остаётся null —
  /// геттеры в этом случае работают по фолбэкам, а следующий вызов снова
  /// попробует сеть.
  Map<String, dynamic> get _values => _cache ?? const <String, dynamic>{};

  Future<int> subscriptionMonthlyPriceRub() async {
    await _load();
    return (_values['subscription.monthly_price_rub'] as num?)?.toInt() ?? 490;
  }

  Future<int> serviceSlotPriceRub() async {
    await _load();
    return (_values['service_slot.price_rub'] as num?)?.toInt() ?? 99;
  }

  Future<int> orderDailyLimit() async {
    await _load();
    return (_values['order.daily_limit'] as num?)?.toInt() ?? 30;
  }

  Future<String> termsCurrentVersion() async {
    await _load();
    return (_values['terms.current_version'] as String?) ?? '1.0';
  }

  /// Ссылка на мессенджер поддержки (МАХ). Пусто — UI покажет мягкую заглушку.
  /// Берётся из настроек, чтобы админ задал её без пересборки приложения.
  Future<String> supportMessengerUrl() async {
    await _load();
    return ((_values['support.messenger_url'] as String?) ?? '').trim();
  }

  /// Ссылка на пользовательское соглашение. У приложения исполнителя СВОЙ
  /// документ (с разделом про подписку и оплаты) — ключ *_pro; общий ключ
  /// остаётся фолбэком на случай, если PRO-ссылку не задали. Пусто — ссылку
  /// не показываем.
  Future<String> legalTermsUrl() async {
    await _load();
    final String pro = ((_values['legal.terms_url_pro'] as String?) ?? '').trim();
    if (pro.isNotEmpty) return pro;
    return ((_values['legal.terms_url'] as String?) ?? '').trim();
  }

  /// Ссылка на политику конфиденциальности (PRO-документ, см. legalTermsUrl).
  Future<String> legalPrivacyUrl() async {
    await _load();
    final String pro = ((_values['legal.privacy_url_pro'] as String?) ?? '').trim();
    if (pro.isNotEmpty) return pro;
    return ((_values['legal.privacy_url'] as String?) ?? '').trim();
  }

  /// Режим графика: считается ли день БЕЗ отметки в расписании рабочим.
  /// true (легаси, по умолчанию) — как в старых сборках: не трогал график,
  /// значит работаешь. false (новый режим «нерабочие по умолчанию») — день
  /// рабочий только если явно отмечен. Флаг серверный
  /// (schedule.unmarked_day_available), переключается вместе с релизом
  /// сборки — до флипа новые сборки ведут себя как старые (миграция 107).
  Future<bool> unmarkedDayAvailable() async {
    await _load();
    final Object? v = _values['schedule.unmarked_day_available'];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.trim().toLowerCase() != 'false';
    return true;
  }

  /// Требуются ли документы при КАЖДОЙ публикации услуги
  /// (verification.per_service_docs, миграция 108). false (по умолчанию) —
  /// одноразовая проверка на аккаунт, как раньше.
  Future<bool> perServiceDocs() async {
    await _load();
    return perServiceDocsCached;
  }

  /// Синхронная версия [perServiceDocs] по УЖЕ ПРОГРЕТОМУ кэшу (warmup в
  /// main + reload после входа). Нужна там, где флаг читается синхронно
  /// (маппинг статуса верификации при загрузке профиля). До прогрева и при
  /// сбое загрузки — false (легаси-режим), это безопасный дефолт.
  bool get perServiceDocsCached {
    final Object? v = _values['verification.per_service_docs'];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.trim().toLowerCase() == 'true';
    return false;
  }

  /// Источник карт: 'mapbox' (по умолчанию) или 'openfreemap'. Аварийный
  /// рубильник в админке — выключает расход квоты Mapbox без пересборки
  /// приложения. Всё, что не 'openfreemap', трактуется как mapbox.
  Future<String> mapProvider() async {
    await _load();
    return ((_values['map.provider'] as String?) ?? 'mapbox').trim().toLowerCase();
  }

  /// Mapbox-токен С СЕРВЕРА. Приоритетнее токена из сборки: при
  /// злоупотреблении (кто-то извлёк токен и тратит квоту) его можно
  /// мгновенно отозвать на mapbox.com и вписать новый в админке — все
  /// приложения подхватят при следующем запуске, без пересборки.
  /// Виден только authenticated (078) — до входа геттер вернёт пусто,
  /// и карта возьмёт токен сборки.
  Future<String> mapboxMapToken() async {
    await _load();
    return ((_values['map.mapbox_token'] as String?) ?? '').trim();
  }
}

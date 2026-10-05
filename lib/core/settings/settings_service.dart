import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Единый терпимый разбор булева флага из таблицы настроек.
///
/// Одно и то же значение приходит в трёх видах, и все три реальны:
/// админ-панель пишет переключатели числом `1`/`0`, миграции — настоящим
/// булевым `true`/`false`, а через REST значение может прийти строкой.
///
/// Правила те же, что на сервере (SQL-функция `schedule_enabled()` и
/// edge-функции ассистента), — иначе приложение и сервер разошлись бы во
/// мнении, включено ли что-то:
///   - булево — как есть;
///   - число — включено, если не ноль;
///   - строка (регистр и пробелы по краям не важны): `1`/`true`/`t`/`yes`/
///     `on` — включено, `0`/`false`/`f`/`no`/`off` — выключено;
///   - всё прочее (нет ключа, мусор, список, словарь) — [fallback].
bool parseSettingsFlag(Object? raw, {required bool fallback}) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) {
    switch (raw.trim().toLowerCase()) {
      case '1' || 'true' || 't' || 'yes' || 'on':
        return true;
      case '0' || 'false' || 'f' || 'no' || 'off':
        return false;
    }
  }
  return fallback;
}

/// Значение флага для синхронных геттеров. Приоритет: свежие настройки с
/// сервера → последнее известное значение, запомненное на устройстве →
/// безопасный дефолт. Если ключ на сервере есть, но значение непонятное,
/// берём дефолт — ровно так же поступает сервер.
bool resolveSettingsFlag({
  required Object? server,
  required bool? device,
  required bool fallback,
}) {
  if (server != null) return parseSettingsFlag(server, fallback: fallback);
  return device ?? fallback;
}

/// Разбор флага бесплатного режима (`billing.free_mode`).
///
/// Ошибка здесь стоит дорого: неверно понятый флаг покажет людям заслонку
/// оплаты там, где платить не надо, — или наоборот. Всё неизвестное
/// трактуем как включённый бесплатный режим. Платный контур должен
/// появляться только после явного «выключено» с сервера.
bool parseFreeModeFlag(Object? raw) => parseSettingsFlag(raw, fallback: true);

/// Разбор флага «График работы включён» (`schedule.enabled`). Всё
/// неизвестное — включён: так приложение ведёт себя ровно как до появления
/// переключателя.
bool parseScheduleEnabledFlag(Object? raw) =>
    parseSettingsFlag(raw, fallback: true);

int? parsePaymentPriceRub(Object? raw) {
  final num? parsed = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
  if (parsed == null ||
      !parsed.isFinite ||
      parsed <= 0 ||
      parsed != parsed.roundToDouble()) {
    return null;
  }
  final int value = parsed.toInt();
  return value > 0 ? value : null;
}

/// Глобальные настройки из таблицы `public.settings`. Загружаются один
/// раз при первом обращении и держатся в памяти. RLS: анониму доступны
/// только до-логиновые ключи (цены, ссылки), операционные ключи и токен
/// карт — только authenticated (миграция 078).
class SettingsService with WidgetsBindingObserver {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  bool _observing = false;
  DateTime? _lastResumeReload;

  /// Перечитывать настройки при возврате приложения из фона.
  ///
  /// Без этого переключение бесплатного режима доезжало до уже открытого
  /// приложения только после полного перезапуска. Хуже всего это выглядело
  /// при ВОЗВРАТЕ платного режима: доступ снова требует подписки, а раздел
  /// «Подписка и оплата» в интерфейсе ещё спрятан флагом — человек упирался
  /// в текст «оплатите» и не мог никуда перейти.
  ///
  /// Чаще раза в минуту не дёргаем: возврат из фона бывает частым.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final DateTime now = DateTime.now();
    if (_lastResumeReload != null &&
        now.difference(_lastResumeReload!) < const Duration(minutes: 1)) {
      return;
    }
    _lastResumeReload = now;
    reload().catchError((Object _) {/* офлайн — останемся на прежних значениях */});
  }

  SupabaseClient get _client => Supabase.instance.client;

  Map<String, dynamic>? _cache;

  /// Сигнал «настройки обновились». Меняется после КАЖДОЙ успешной загрузки
  /// (прогрев, вход, возврат из фона, принудительное перечитывание) и после
  /// подъёма запомненных значений с устройства. Экраны, которые решают по
  /// синхронным геттерам, что показывать (пункты профиля, заглушки), слушают
  /// его и перерисовываются — иначе переключение в админ-панели доезжало бы
  /// до уже открытого экрана только при его случайной перерисовке.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

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
      final List<Map<String, dynamic>> rows = await _client
          .from('settings')
          .select('key, value');
      _applyLoaded(<String, dynamic>{
        for (final Map<String, dynamic> r in rows)
          r['key'] as String: r['value'],
      });
    } catch (_) {
      // Кэш НЕ фиксируем пустым: офлайн-старт раньше навсегда (до перезапуска)
      // оставлял приложение на зашитых фолбэках. Оставляем null — следующий
      // геттер повторит запрос, когда сеть появится.
    } finally {
      _inFlight = null;
    }
  }

  /// Принять свежие настройки с сервера: положить в кэш, запомнить на
  /// устройстве флаги, которые нужны до сети на следующем холодном старте,
  /// и подать сигнал [revision].
  void _applyLoaded(Map<String, dynamic> values) {
    _cache = values;
    _rememberFreeMode(_parseBool(values['billing.free_mode']));
    _rememberScheduleEnabled(
      parseScheduleEnabledFlag(values[_kScheduleEnabledKey]),
    );
    revision.value++;
  }

  /// Настройки проверки обновлений: минимально допустимая версия (ниже неё —
  /// настойчивое окно), последняя версия и переключатель «рекомендуем
  /// обновить». Мягкое окно показывается ТОЛЬКО когда переключатель включён
  /// И версия ниже последней. Дефолты («0.0.0» / выключено) — окно не
  /// появляется, пока админ не задаст значения. Парсинг терпим к хранению
  /// значения как строки и как числа.
  Future<({String min, String latest, bool recommend})> appVersions() async {
    await _load();
    final String min = (_values['app.pro_min_version']?.toString() ?? '0.0.0')
        .trim();
    final String latest =
        (_values['app.pro_latest_version']?.toString() ?? '0.0.0').trim();
    final bool recommend =
        (num.tryParse('${_values['app.pro_recommend_update'] ?? 0}') ?? 0) != 0;
    return (min: min, latest: latest, recommend: recommend);
  }

  /// Прогревает кэш настроек на старте приложения. Вызывается из `main()`
  /// fire-and-forget вместе с CatalogService.warmup() — после этого все
  /// геттеры возвращают значения мгновенно, без сетевого запроса.
  ///
  /// Перед сетью поднимаем с устройства последние известные значения
  /// бесплатного режима и переключателя графика работы: иначе на холодном
  /// старте без сети приложение на секунду считало бы себя платным и могло
  /// показать заслонку оплаты там, где платить уже не нужно, или показать
  /// выключенный из админ-панели график.
  Future<void> warmup() async {
    if (!_observing) {
      _observing = true;
      WidgetsFlutterBinding.ensureInitialized();
      WidgetsBinding.instance.addObserver(this);
    }
    await _restoreFreeMode();
    if (await _restoreScheduleEnabled()) revision.value++;
    await _load();
  }

  // ---------------------------------------------------------------
  // Бесплатный режим (`billing.free_mode` в таблице настроек).
  //
  // Один серверный переключатель на всё приложение: пока он включён,
  // подписка не нужна, размещение услуг бесплатно, оплата не принимается.
  // Выключение возвращает прежнее платное поведение — экраны оплаты никуда
  // не удалены, они просто спрятаны за этим флагом.
  // ---------------------------------------------------------------

  /// Последнее известное значение, поднятое с устройства. `null` — ещё не
  /// читали. Нужно только для первых мгновений холодного старта и для
  /// работы без сети.
  static bool? _stickyFreeMode;

  static const String _kFreeModePrefsKey = 'billing_free_mode_v1';

  static bool _parseBool(Object? v) => parseFreeModeFlag(v);

  Future<void> _restoreFreeMode() async {
    if (_stickyFreeMode != null) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _stickyFreeMode = prefs.getBool(_kFreeModePrefsKey);
    } catch (_) {
      /* нет доступа к хранилищу — останемся на серверном значении */
    }
  }

  void _rememberFreeMode(bool value) {
    if (_stickyFreeMode == value) return;
    _stickyFreeMode = value;
    SharedPreferences.getInstance()
        .then((SharedPreferences p) => p.setBool(_kFreeModePrefsKey, value))
        .catchError((Object _) => false);
  }

  /// Включён ли бесплатный режим. Ждёт загрузку настроек.
  Future<bool> freeMode() async {
    await _load();
    return freeModeCached;
  }

  /// Синхронная версия по уже прогретому кэшу — нужна там, где решение
  /// принимается прямо во время отрисовки (заслонки оплаты, гейты).
  /// Приоритет: свежие настройки с сервера → последнее известное значение
  /// с устройства → бесплатный режим. Пока сервис недоступен, человеку
  /// нельзя показывать экран, карту или текст об оплате: сервер всё равно
  /// остаётся единственной точкой, которая разрешает платёж после будущего
  /// включения монетизации.
  bool get freeModeCached => resolveSettingsFlag(
    server: _values['billing.free_mode'],
    device: _stickyFreeMode,
    fallback: true,
  );

  // ---------------------------------------------------------------
  // Переключатель «График работы» (`schedule.enabled` в таблице настроек).
  //
  // Сделан по образцу бесплатного режима. Выключен — в приложении нет
  // ничего про график: пункт «Мой график» в профиле спрятан, маршруты
  // графика уводят на главный экран, ассистент не предлагает перейти
  // в график, попап «Заполните график работы» не появляется. Экраны
  // графика никуда не удалены — включение возвращает всё как было.
  // По умолчанию (ключа нет, значение непонятно) график ВКЛЮЧЁН.
  // ---------------------------------------------------------------

  static const String _kScheduleEnabledKey = 'schedule.enabled';
  static const String _kScheduleEnabledPrefsKey = 'schedule_enabled_v1';

  /// Последнее известное значение, поднятое с устройства. `null` — ещё не
  /// читали или ни разу не запоминали.
  static bool? _stickyScheduleEnabled;

  /// Поднять запомненное значение с устройства. true — что-то нашлось.
  Future<bool> _restoreScheduleEnabled() async {
    if (_stickyScheduleEnabled != null) return false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool? stored = prefs.getBool(_kScheduleEnabledPrefsKey);
      // Пока читали диск, могли успеть прийти свежие настройки с сервера
      // (перечитывание после входа идёт параллельно прогреву) — их не
      // перетираем старым значением.
      if (stored == null || _stickyScheduleEnabled != null) return false;
      _stickyScheduleEnabled = stored;
      return true;
    } catch (_) {
      /* нет доступа к хранилищу — останемся на серверном значении */
      return false;
    }
  }

  void _rememberScheduleEnabled(bool value) {
    if (_stickyScheduleEnabled == value) return;
    _stickyScheduleEnabled = value;
    SharedPreferences.getInstance()
        .then((SharedPreferences p) =>
            p.setBool(_kScheduleEnabledPrefsKey, value))
        .catchError((Object _) => false);
  }

  /// Включён ли график работы. Ждёт загрузку настроек.
  Future<bool> scheduleEnabled() async {
    await _load();
    return scheduleEnabledCached;
  }

  /// Синхронная версия по уже прогретому кэшу — для решений прямо во время
  /// отрисовки и в роутере. Приоритет: свежие настройки с сервера →
  /// последнее известное значение с устройства → включён.
  bool get scheduleEnabledCached => resolveSettingsFlag(
    server: _values[_kScheduleEnabledKey],
    device: _stickyScheduleEnabled,
    fallback: true,
  );

  /// Только для тестов: подложить «загруженные с сервера» настройки тем же
  /// путём, что и настоящая загрузка (кэш, запоминание на устройстве,
  /// сигнал [revision]).
  @visibleForTesting
  void debugApplyLoaded(Map<String, dynamic> values) => _applyLoaded(values);

  /// Только для тестов: забыть кэш и запомненные значения, как на свежем
  /// запуске приложения.
  @visibleForTesting
  void debugReset() {
    _cache = null;
    _inFlight = null;
    _stickyFreeMode = null;
    _stickyScheduleEnabled = null;
  }

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
      } catch (_) {
        /* неудача старой загрузки не мешает новой */
      }
    }
    _cache = null;
    await _load();
  }

  /// Снимок кэша для геттеров: после неудачной загрузки кэш остаётся null —
  /// геттеры в этом случае работают по фолбэкам, а следующий вызов снова
  /// попробует сеть.
  Map<String, dynamic> get _values => _cache ?? const <String, dynamic>{};

  Future<int?> subscriptionMonthlyPriceRub() async {
    await _load();
    return _positiveIntSetting('subscription.monthly_price_rub');
  }

  Future<int?> serviceSlotPriceRub() async {
    await _load();
    return _positiveIntSetting('service_slot.price_rub');
  }

  /// Для денежных настроек нет локальных фолбэков: UI обязан показать ровно
  /// ту же цену, которую сервер возьмёт из БД. При недоступной/битой настройке
  /// возвращаем null и блокируем кнопку оплаты до повторной загрузки.
  int? _positiveIntSetting(String key) {
    return parsePaymentPriceRub(_values[key]);
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
    final String pro = ((_values['legal.terms_url_pro'] as String?) ?? '')
        .trim();
    if (pro.isNotEmpty) return pro;
    return ((_values['legal.terms_url'] as String?) ?? '').trim();
  }

  /// Ссылка на политику конфиденциальности (PRO-документ, см. legalTermsUrl).
  Future<String> legalPrivacyUrl() async {
    await _load();
    final String pro = ((_values['legal.privacy_url_pro'] as String?) ?? '')
        .trim();
    if (pro.isNotEmpty) return pro;
    return ((_values['legal.privacy_url'] as String?) ?? '').trim();
  }

  /// Режим графика: считается ли день БЕЗ отметки в расписании рабочим.
  /// true (легаси, по умолчанию) — как в старых сборках: не трогал график,
  /// значит работаешь. false (новый режим «нерабочие по умолчанию») — день
  /// рабочий только если явно отмечен. Флаг серверный
  /// (schedule.unmarked_day_available), переключается вместе с релизом
  /// сборки — до флипа новые сборки ведут себя как старые (миграция 107).
  /// Разбор общий с сервером ([parseSettingsFlag]): раньше строка '0'
  /// здесь давала true, а сервер читал её как false.
  Future<bool> unmarkedDayAvailable() async {
    await _load();
    return parseSettingsFlag(
      _values['schedule.unmarked_day_available'],
      fallback: true,
    );
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
    return ((_values['map.provider'] as String?) ?? 'mapbox')
        .trim()
        .toLowerCase();
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

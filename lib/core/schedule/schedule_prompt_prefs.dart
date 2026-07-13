import 'package:shared_preferences/shared_preferences.dart';

/// Видел ли пользователь попап «Заполните график работы». Показывается
/// один раз за всё время — после активации подписки (привязки карты =
/// старта триала), но не раньше, чем создана карточка исполнителя:
/// «Мой график» до карточки закрыт, и попап уводил бы в раздел, куда
/// обычным путём ещё не попасть.
class SchedulePromptPrefs {
  SchedulePromptPrefs._();

  static const String _key = 'schedule_prompt_seen_v1';
  static const String _pendingKey = 'schedule_prompt_pending_v1';

  /// Сигнал «подписку только что активировали»: выставляется экраном
  /// результата оплаты при успешной привязке карты. Показ попапа ждёт
  /// создания карточки исполнителя, а между оплатой и карточкой
  /// пользователь может перезапустить приложение — поэтому сигнал
  /// дублируется на диск (см. [setPending]/[pendingStored]).
  static bool pending = false;

  /// Поднять сигнал: в памяти сразу, на диске — в фоне.
  static Future<void> setPending() async {
    pending = true;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setBool(_pendingKey, true);
    } catch (_) {/* не критично: сигнал в памяти уже поднят */}
  }

  /// Дисковая копия сигнала — переживает перезапуск приложения.
  static Future<bool> pendingStored() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      return p.getBool(_pendingKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearPendingStored() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.remove(_pendingKey);
    } catch (_) {/* не критично */}
  }

  static Future<bool> seen() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      return p.getBool(_key) ?? false;
    } catch (_) {
      return false; // нет хранилища — покажем попап, не критично
    }
  }

  static Future<void> markSeen() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setBool(_key, true);
    } catch (_) {/* не критично */}
  }
}

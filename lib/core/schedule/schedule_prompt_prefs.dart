import 'package:shared_preferences/shared_preferences.dart';

/// Видел ли пользователь попап «Заполните график работы». Показывается
/// один раз за всё время — после первой активации подписки (привязки
/// карты = старта триала), чтобы новый исполнитель сразу отметил рабочие
/// дни и начал находиться в поиске по дате.
class SchedulePromptPrefs {
  SchedulePromptPrefs._();

  static const String _key = 'schedule_prompt_seen_v1';

  /// Сигнал «подписку только что активировали»: выставляется экраном
  /// результата оплаты при успешной привязке карты, читается корневым
  /// экраном и карточкой исполнителя после первого кадра. Живёт только
  /// в памяти — «показан ли уже попап» хранится отдельно (persisted).
  static bool pending = false;

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

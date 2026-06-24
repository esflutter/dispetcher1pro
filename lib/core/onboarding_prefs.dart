import 'package:shared_preferences/shared_preferences.dart';

/// Видел ли пользователь онбординг. Нужен, чтобы гость (без входа) при повторном
/// запуске попадал сразу в каталог заказов, а не смотрел онбординг каждый раз.
class OnboardingPrefs {
  OnboardingPrefs._();

  static const String _key = 'onboarding_seen_v1';

  static Future<bool> seen() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      return p.getBool(_key) ?? false;
    } catch (_) {
      return false; // нет хранилища — покажем онбординг, не критично
    }
  }

  static Future<void> markSeen() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setBool(_key, true);
    } catch (_) {/* не критично */}
  }
}

import 'package:shared_preferences/shared_preferences.dart';

/// Локальный суточный лимит запросов кода входа с этого устройства.
///
/// Закрывает «бытовое» злоупотребление: человек вводит в наше приложение
/// десятки чужих номеров подряд (каждая СМС — деньги). Хакера с прямыми
/// запросами к серверу этот счётчик не остановит — но того режут серверные
/// лимиты (10 запросов с IP — GoTrue, 5 СМС/час на номер и 300 СМС/час на
/// сервис — наш СМС-хук); локальный лимит добивает именно сценарий
/// «с телефона через приложение».
///
/// Хранится в SharedPreferences → сбрасывается переустановкой приложения.
/// Приемлемо: в связке с серверными лимитами повторная установка ради
/// ещё десятка СМС делает «развлечение» слишком муторным.
class OtpDeviceLimit {
  OtpDeviceLimit._();

  /// Честному пользователю хватает с запасом (опечатка, повтор, второй
  /// вход за день — обычно 1–3 запроса). Меняя, помни про собственные
  /// прогоны тестов с эмулятора — они тоже расходуют счётчик.
  static const int maxPerDay = 10;
  static const String _key = 'otp_request_times_ms';

  /// `true` — можно отправлять; `false` — суточный лимит исчерпан.
  static Future<bool> allowed() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return _fresh(prefs).length < maxPerDay;
  }

  /// Зафиксировать факт запроса кода. Звать ПОСЛЕ успешной отправки,
  /// чтобы сетевые сбои не съедали лимит впустую.
  static Future<void> record() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<int> fresh = _fresh(prefs)
      ..add(DateTime.now().millisecondsSinceEpoch);
    await prefs.setStringList(
      _key,
      fresh.map((int t) => t.toString()).toList(),
    );
  }

  /// Отметки запросов за последние 24 часа (старые отбрасываются —
  /// «скользящее окно», а не календарные сутки).
  static List<int> _fresh(SharedPreferences prefs) {
    final int dayAgo = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    return (prefs.getStringList(_key) ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .where((int t) => t > dayAgo)
        .toList();
  }
}

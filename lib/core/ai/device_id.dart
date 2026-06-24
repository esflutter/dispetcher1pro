import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Стабильный идентификатор устройства для гостевого режима ассистента.
///
/// У гостя (без входа) нет учётной записи, поэтому дневной лимит запросов к
/// ассистенту считается по этому id. Генерируется один раз и хранится локально;
/// при входе в аккаунт перестаёт использоваться (лимит считается по аккаунту).
class DeviceId {
  DeviceId._();

  static const String _key = 'guest_device_id_v1';
  static String? _cached;

  /// Возвращает локальный id устройства, создавая его при первом обращении.
  static Future<String> get() async {
    if (_cached != null) return _cached!;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      String? id = p.getString(_key);
      if (id == null || id.isEmpty) {
        id = _generate();
        await p.setString(_key, id);
      }
      _cached = id;
      return id;
    } catch (_) {
      // Нет хранилища — отдаём разовый id (лимит просто не переживёт перезапуск).
      return _cached ??= _generate();
    }
  }

  /// UUID v4 из криптостойкого генератора — без внешних зависимостей.
  static String _generate() {
    final Random r = Random.secure();
    final List<int> b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // версия 4
    b[8] = (b[8] & 0x3f) | 0x80; // вариант
    String hex(int from, int to) {
      final StringBuffer sb = StringBuffer();
      for (int i = from; i < to; i++) {
        sb.write(b[i].toRadixString(16).padLeft(2, '0'));
      }
      return sb.toString();
    }

    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}

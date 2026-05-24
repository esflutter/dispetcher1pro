import 'dart:math';

/// Идемпотентный ключ для INSERT-операций (`services.client_uid`). UUID
/// v4 на `Random.secure` — без зависимости от пакета `uuid`. Клиент
/// держит этот ключ в state экрана и передаёт ОДИН и тот же
/// `client_uid` при повторных попытках отправки. Серверный partial
/// unique index не даст создать дубль (см. миграцию
/// `orders_services_client_uid_idempotency`).
String generateClientUid() {
  final Random rnd = Random.secure();
  final List<int> b = List<int>.generate(16, (_) => rnd.nextInt(256));
  // RFC 4122 v4: версия в b[6] = 0100xxxx, variant в b[8] = 10xxxxxx.
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int v) => v.toRadixString(16).padLeft(2, '0');
  final StringBuffer sb = StringBuffer();
  for (int i = 0; i < 16; i++) {
    if (i == 4 || i == 6 || i == 8 || i == 10) sb.write('-');
    sb.write(hex(b[i]));
  }
  return sb.toString();
}

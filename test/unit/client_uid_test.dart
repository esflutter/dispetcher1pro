import 'package:flutter_test/flutter_test.dart';
import 'package:dispatcher_1/core/utils/client_uid.dart';

/// UUID v4 для идемпотентности INSERT-операций. Если сетевой флап после
/// успешного INSERT приведёт к retry с тем же UID, серверный partial
/// unique index (см. миграцию `orders_services_client_uid_idempotency`)
/// вернёт `23505` и клиент подтянет уже созданную запись.
///
/// Тут проверяем формат — он критичен: серверный constraint на TEXT
/// без regex-проверки, но мы зашиваем правильный v4-вариант, чтобы
/// при ревью БД не получить странные значения.

void main() {
  group('generateClientUid', () {
    test('формат RFC 4122 v4: длина 36, дефисы в правильных позициях',
        () {
      final String uid = generateClientUid();
      expect(uid.length, 36);
      expect(uid[8], '-');
      expect(uid[13], '-');
      expect(uid[18], '-');
      expect(uid[23], '-');
    });

    test('версия = 4 (14-й символ ровно "4")', () {
      for (int i = 0; i < 50; i++) {
        final String uid = generateClientUid();
        expect(uid[14], '4',
            reason: 'iter $i: uid=$uid; 14-й символ должен быть "4"');
      }
    });

    test('variant bits корректные (19-й символ в {8, 9, a, b})', () {
      const Set<String> validVariants = <String>{'8', '9', 'a', 'b'};
      for (int i = 0; i < 50; i++) {
        final String uid = generateClientUid();
        expect(validVariants.contains(uid[19]), isTrue,
            reason: 'iter $i: uid=$uid; 19-й символ должен быть 8/9/a/b');
      }
    });

    test('только hex-символы + дефисы', () {
      final RegExp re = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      for (int i = 0; i < 50; i++) {
        final String uid = generateClientUid();
        expect(re.hasMatch(uid), isTrue,
            reason: 'iter $i: uid=$uid не матчит canonical UUID v4');
      }
    });

    test('1000 вызовов — все уникальны (коллизии маловероятны)', () {
      final Set<String> seen = <String>{};
      for (int i = 0; i < 1000; i++) {
        final String uid = generateClientUid();
        expect(seen.add(uid), isTrue, reason: 'duplicate UID на iter $i');
      }
    });
  });
}

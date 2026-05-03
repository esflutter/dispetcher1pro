import 'package:flutter_test/flutter_test.dart';
import 'package:dispatcher_1/core/my_orders/models.dart';

/// Unit-тесты маппинга строкового статуса БД в `MyMatchStatus`.
/// Покрывают каждый известный статус + fallback на rejectedByExecutor.
///
/// Если бизнес-логика поменяет набор статусов (например, появится
/// новый `disputed`), этот тест провалится и потребует осознанного
/// обновления — защита от молчаливой регрессии в FSM.

void main() {
  group('MyMatchStatus.fromDb', () {
    test('awaiting_customer', () {
      expect(MyMatchStatus.fromDb('awaiting_customer'),
          MyMatchStatus.awaitingCustomer);
    });

    test('awaiting_executor', () {
      expect(MyMatchStatus.fromDb('awaiting_executor'),
          MyMatchStatus.awaitingExecutor);
    });

    test('accepted', () {
      expect(MyMatchStatus.fromDb('accepted'), MyMatchStatus.accepted);
    });

    test('completed', () {
      expect(MyMatchStatus.fromDb('completed'), MyMatchStatus.completed);
    });

    test('rejected_by_customer', () {
      expect(MyMatchStatus.fromDb('rejected_by_customer'),
          MyMatchStatus.rejectedByCustomer);
    });

    test('rejected_by_executor', () {
      expect(MyMatchStatus.fromDb('rejected_by_executor'),
          MyMatchStatus.rejectedByExecutor);
    });

    test('expired', () {
      expect(MyMatchStatus.fromDb('expired'), MyMatchStatus.expired);
    });

    test('неизвестный статус → fallback rejectedByExecutor', () {
      expect(MyMatchStatus.fromDb('something_new'),
          MyMatchStatus.rejectedByExecutor);
    });
  });

  group('MyMatchStatus геттеры', () {
    test('isActive', () {
      expect(MyMatchStatus.awaitingCustomer.isActive, isTrue);
      expect(MyMatchStatus.awaitingExecutor.isActive, isTrue);
      expect(MyMatchStatus.accepted.isActive, isTrue);
      expect(MyMatchStatus.completed.isActive, isFalse);
      expect(MyMatchStatus.rejectedByCustomer.isActive, isFalse);
      expect(MyMatchStatus.rejectedByExecutor.isActive, isFalse);
      expect(MyMatchStatus.expired.isActive, isFalse);
    });

    test('isDone (только completed)', () {
      expect(MyMatchStatus.completed.isDone, isTrue);
      expect(MyMatchStatus.accepted.isDone, isFalse);
    });

    test('isRejected (rejected_*/expired)', () {
      expect(MyMatchStatus.rejectedByCustomer.isRejected, isTrue);
      expect(MyMatchStatus.rejectedByExecutor.isRejected, isTrue);
      expect(MyMatchStatus.expired.isRejected, isTrue);
      expect(MyMatchStatus.accepted.isRejected, isFalse);
      expect(MyMatchStatus.completed.isRejected, isFalse);
    });
  });
}

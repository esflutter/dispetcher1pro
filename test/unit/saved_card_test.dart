import 'package:flutter_test/flutter_test.dart';
import 'package:dispatcher_1/core/payments/models.dart';

/// Unit-тесты для модели сохранённой карты. Покрывают:
///   - парсинг строки из БД (`SavedCard.fromRow`),
///   - геттер `isExpired` для разных форматов поля `expiry_year`
///     (4-значный «2024», 2-значный «24», null/невалидный),
///   - геттер `displayLast4` для bank_card и yoo_money.
///
/// Запуск: `flutter test test/unit/saved_card_test.dart`.

void main() {
  group('SavedCard.isExpired', () {
    test('null expiry → не истекла (yoo_money/прочее)', () {
      const SavedCard c = SavedCard(
        id: '1', kind: 'yoo_money', last4: null, brand: null,
        expiryMonth: null, expiryYear: null, title: null,
      );
      expect(c.isExpired, isFalse);
    });

    test('expiry далеко в будущем → не истекла', () {
      final SavedCard c = SavedCard(
        id: '1', kind: 'bank_card', last4: '4804', brand: 'Visa',
        expiryMonth: '12', expiryYear: '${DateTime.now().year + 5}', title: null,
      );
      expect(c.isExpired, isFalse);
    });

    test('expiry в прошлом → истекла', () {
      const SavedCard c = SavedCard(
        id: '1', kind: 'bank_card', last4: '4804', brand: 'Visa',
        expiryMonth: '01', expiryYear: '2020', title: null,
      );
      expect(c.isExpired, isTrue);
    });

    test('2-значный год (24) обрабатывается как 2024', () {
      const SavedCard c = SavedCard(
        id: '1', kind: 'bank_card', last4: '4804', brand: 'Visa',
        expiryMonth: '01', expiryYear: '20', title: null,
      );
      // 2020 < сейчас → должна быть истекшей.
      expect(c.isExpired, isTrue);
    });

    test('текущий месяц текущего года → не истекла (формально активна)', () {
      final DateTime now = DateTime.now();
      final SavedCard c = SavedCard(
        id: '1', kind: 'bank_card', last4: '4804', brand: 'Visa',
        expiryMonth: now.month.toString().padLeft(2, '0'),
        expiryYear: now.year.toString(),
        title: null,
      );
      expect(c.isExpired, isFalse);
    });

    test('невалидные строки → не истекла (fail-safe)', () {
      const SavedCard c = SavedCard(
        id: '1', kind: 'bank_card', last4: '4804', brand: 'Visa',
        expiryMonth: 'abc', expiryYear: 'xyz', title: null,
      );
      expect(c.isExpired, isFalse);
    });
  });

  group('SavedCard.displayLast4', () {
    test('bank_card → last4', () {
      const SavedCard c = SavedCard(
        id: '1', kind: 'bank_card', last4: '4804', brand: 'Visa',
        expiryMonth: '12', expiryYear: '2030', title: null,
      );
      expect(c.displayLast4, '4804');
    });

    test('yoo_money → последние 4 цифры из title', () {
      const SavedCard c = SavedCard(
        id: '1', kind: 'yoo_money', last4: null, brand: null,
        expiryMonth: null, expiryYear: null,
        title: 'YooMoney wallet 410011758831136',
      );
      expect(c.displayLast4, '1136');
    });

    test('пустые поля → fallback ••••', () {
      const SavedCard c = SavedCard(
        id: '1', kind: null, last4: null, brand: null,
        expiryMonth: null, expiryYear: null, title: null,
      );
      expect(c.displayLast4, '••••');
    });
  });

  group('SavedCard.fromRow', () {
    test('парсит все поля из БД', () {
      final SavedCard c = SavedCard.fromRow(<String, dynamic>{
        'id': 'pm-id',
        'kind': 'bank_card',
        'card_last4': '4804',
        'card_brand': 'Visa',
        'card_expiry_month': '12',
        'card_expiry_year': '2030',
        'title': 'Bank card *4804',
      });
      expect(c.id, 'pm-id');
      expect(c.kind, 'bank_card');
      expect(c.last4, '4804');
      expect(c.brand, 'Visa');
      expect(c.expiryMonth, '12');
      expect(c.expiryYear, '2030');
      expect(c.isExpired, isFalse);
    });
  });
}

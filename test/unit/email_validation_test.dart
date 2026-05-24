import 'package:flutter_test/flutter_test.dart';
import 'package:dispatcher_1/core/utils/email_validation.dart';

/// Единая валидация email во всём приложении исполнителя. До унификации
/// в `edit_profile_screen` и `edit_executor_card_screen` были разные
/// regex'ы — один строгий, второй пропускал `a@@b.c`. Теперь оба
/// форм-эдитора зовут эту функцию.

void main() {
  group('isValidEmail', () {
    test('пустая строка → true (поле необязательное)', () {
      expect(isValidEmail(''), isTrue);
      expect(isValidEmail('   '), isTrue);
    });

    test('валидные email', () {
      expect(isValidEmail('user@example.com'), isTrue);
      expect(isValidEmail('User.Name+tag@sub.example.com'), isTrue);
      expect(isValidEmail('a@b.co'), isTrue);
      expect(isValidEmail('with-dash@host-name.io'), isTrue);
      expect(isValidEmail('123@example.com'), isTrue);
      expect(isValidEmail('user@example.museum'), isTrue);
    });

    test('двойной @ → invalid', () {
      expect(isValidEmail('a@@b.c'), isFalse);
    });

    test('без @ → invalid', () {
      expect(isValidEmail('user.example.com'), isFalse);
    });

    test('без TLD → invalid', () {
      expect(isValidEmail('user@example'), isFalse);
      expect(isValidEmail('user@.com'), isFalse);
    });

    test('TLD длиной 1 → invalid', () {
      expect(isValidEmail('user@example.c'), isFalse);
    });

    test('пробелы внутри → invalid', () {
      expect(isValidEmail('user name@example.com'), isFalse);
      expect(isValidEmail('user@example .com'), isFalse);
    });

    test('кириллица → invalid (наш regex ASCII-only)', () {
      // Спецификация: в проде разрешаем только ASCII-почту для simplicity.
      expect(isValidEmail('пользователь@example.com'), isFalse);
    });

    test('trim перед проверкой — концевые пробелы ОК', () {
      expect(isValidEmail('  user@example.com  '), isTrue);
    });
  });
}

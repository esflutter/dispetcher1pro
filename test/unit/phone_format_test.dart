import 'package:flutter_test/flutter_test.dart';
import 'package:dispatcher_1/core/auth/phone_format.dart';

/// Нормализация телефонов в E.164 и обратный показ в UI-формате.
/// Бэк (Supabase Auth) принимает только `+7XXXXXXXXXX`, а юзер вводит
/// что попало — клавиатура, копипаст, набор с пробелами/дефисами.

void main() {
  group('PhoneFormat.toE164', () {
    test('10 цифр → +7XXXXXXXXXX', () {
      expect(PhoneFormat.toE164('9991234567'), '+79991234567');
    });

    test('11 цифр с 7 в начале', () {
      expect(PhoneFormat.toE164('79991234567'), '+79991234567');
    });

    test('11 цифр с 8 в начале (Россия legacy)', () {
      expect(PhoneFormat.toE164('89991234567'), '+79991234567');
    });

    test('с пробелами и дефисами', () {
      expect(PhoneFormat.toE164('+7 999 123-45-67'), '+79991234567');
      expect(PhoneFormat.toE164('8 (999) 123-45-67'), '+79991234567');
    });

    test('с буквами вокруг — игнорируем не-цифры', () {
      expect(PhoneFormat.toE164('тел: +7 999 1234567'), '+79991234567');
    });

    test('меньше 10 цифр → FormatException', () {
      expect(() => PhoneFormat.toE164('123'), throwsFormatException);
      expect(() => PhoneFormat.toE164(''), throwsFormatException);
    });

    test('больше 11 цифр → FormatException', () {
      expect(() => PhoneFormat.toE164('+7999123456789'),
          throwsFormatException);
    });

    test('11 цифр НЕ с 7/8 → FormatException', () {
      // Не российский номер с длиной 11 — мы такие не принимаем.
      expect(() => PhoneFormat.toE164('19991234567'), throwsFormatException);
    });
  });

  group('PhoneFormat.toPretty', () {
    test('+7XXXXXXXXXX → +7 XXX XXX-XX-XX', () {
      expect(PhoneFormat.toPretty('+79991234567'), '+7 999 123-45-67');
    });

    test('неподдерживаемый формат → возвращает как есть', () {
      expect(PhoneFormat.toPretty('+1234'), '+1234');
      expect(PhoneFormat.toPretty(''), '');
      expect(PhoneFormat.toPretty('not a phone'), 'not a phone');
    });

    test('roundtrip toE164→toPretty стабильный', () {
      const String e164 = '+79991234567';
      final String pretty = PhoneFormat.toPretty(e164);
      final String back = PhoneFormat.toE164(pretty);
      expect(back, e164);
    });
  });
}

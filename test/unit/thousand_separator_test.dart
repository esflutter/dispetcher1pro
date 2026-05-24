import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dispatcher_1/core/utils/thousand_separator_formatter.dart';

/// Форматтер числового поля «Цена» (рубли). Расставляет пробелы каждые
/// 3 разряда справа, начиная с 4-значных значений. Лимит цифр —
/// `maxDigits` (по умолчанию 9, то есть до 999 999 999 ₽).
///
/// Эти тесты ловят регрессии:
///   - правила «когда ставим пробелы» (не до 4 цифр включительно).
///   - обрезку при превышении лимита.
///   - очистку нецифровых символов.

TextEditingValue _val(String s) =>
    TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));

void main() {
  group('ThousandSeparatorFormatter', () {
    test('пусто → пусто', () {
      const f = ThousandSeparatorFormatter();
      expect(f.formatEditUpdate(_val(''), _val('')).text, '');
    });

    test('до 3 цифр — без пробелов', () {
      const f = ThousandSeparatorFormatter();
      expect(f.formatEditUpdate(_val(''), _val('1')).text, '1');
      expect(f.formatEditUpdate(_val(''), _val('12')).text, '12');
      expect(f.formatEditUpdate(_val(''), _val('123')).text, '123');
    });

    test('4 цифры — пробел 1 000', () {
      const f = ThousandSeparatorFormatter();
      expect(f.formatEditUpdate(_val(''), _val('1000')).text, '1 000');
      expect(f.formatEditUpdate(_val(''), _val('9999')).text, '9 999');
    });

    test('5-7 цифр', () {
      const f = ThousandSeparatorFormatter();
      expect(f.formatEditUpdate(_val(''), _val('10000')).text, '10 000');
      expect(f.formatEditUpdate(_val(''), _val('100000')).text, '100 000');
      expect(f.formatEditUpdate(_val(''), _val('1000000')).text, '1 000 000');
    });

    test('лимит maxDigits — обрезает лишнее', () {
      const f = ThousandSeparatorFormatter(maxDigits: 5);
      // 6 цифр: оставит 5 → 12 345.
      expect(f.formatEditUpdate(_val(''), _val('123456')).text, '12 345');
    });

    test('нецифры — игнорируются', () {
      const f = ThousandSeparatorFormatter();
      expect(f.formatEditUpdate(_val(''), _val('1a2b3c4')).text, '1 234');
      expect(f.formatEditUpdate(_val(''), _val('-1000')).text, '1 000');
      expect(f.formatEditUpdate(_val(''), _val('1 000')).text, '1 000');
    });

    test('selection всегда в конце форматированной строки', () {
      const f = ThousandSeparatorFormatter();
      final TextEditingValue out =
          f.formatEditUpdate(_val(''), _val('10000'));
      expect(out.selection.baseOffset, '10 000'.length);
      expect(out.selection.isCollapsed, isTrue);
    });
  });
}

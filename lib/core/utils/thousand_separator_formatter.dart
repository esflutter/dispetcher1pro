import 'package:flutter/services.dart';

/// Форматтер ввода числового поля: оставляет только цифры, ограничивает
/// количество цифр [maxDigits] и, начиная с 4 цифр (1 000), расставляет
/// пробелы каждые 3 разряда справа. 1 000, 10 000, 100 000, 1 000 000 —
/// с пробелами.
class ThousandSeparatorFormatter extends TextInputFormatter {
  const ThousandSeparatorFormatter({this.maxDigits = 9});

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > maxDigits) {
      digits = digits.substring(0, maxDigits);
    }
    final String formatted;
    if (digits.length < 4) {
      formatted = digits;
    } else {
      final StringBuffer buf = StringBuffer();
      for (int i = 0; i < digits.length; i++) {
        final int fromRight = digits.length - i;
        if (i > 0 && fromRight % 3 == 0) buf.write(' ');
        buf.write(digits[i]);
      }
      formatted = buf.toString();
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

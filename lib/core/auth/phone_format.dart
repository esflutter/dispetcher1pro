/// Утилиты для нормализации телефона в E.164 и обратного преобразования
/// в UI-формат. Бэкенд (Supabase) принимает только `+7XXXXXXXXXX`,
/// пользователь видит `+7 XXX XXX-XX-XX`.
class PhoneFormat {
  PhoneFormat._();

  /// Приводит пользовательский ввод к E.164 для России: `+7XXXXXXXXXX`.
  /// Принимает `9991234567`, `89991234567`, `+7 (999) 123-45-67` и т.п.
  static String toE164(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) return '+7$digits';
    if (digits.length == 11 && (digits[0] == '7' || digits[0] == '8')) {
      return '+7${digits.substring(1)}';
    }
    throw const FormatException('Номер должен содержать 10 или 11 цифр');
  }

  /// Возвращает номер в формате `+7 XXX XXX-XX-XX` для отображения в UI.
  /// Принимает E.164 (`+7XXXXXXXXXX`). Если формат не распознан —
  /// возвращает исходную строку как есть.
  static String toPretty(String e164) {
    final m = RegExp(r'^\+7(\d{3})(\d{3})(\d{2})(\d{2})$').firstMatch(e164);
    if (m == null) return e164;
    return '+7 ${m.group(1)} ${m.group(2)}-${m.group(3)}-${m.group(4)}';
  }
}

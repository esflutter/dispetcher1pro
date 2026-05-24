import 'package:flutter_test/flutter_test.dart';

/// Полноценный smoke-тест приложения с инициализацией Supabase/Realtime
/// требует env-переменных и mock'ов всех бэкенд-зависимостей. До их
/// настройки оставляем здесь sanity-проверку — что test framework
/// поднимается, а реальное покрытие даёт `test/unit/*`.
void main() {
  test('test framework boots', () {
    expect(1 + 1, 2);
  });
}

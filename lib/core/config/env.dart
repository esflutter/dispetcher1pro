/// Секреты проекта (URL Supabase, anon-ключ и т.п.).
///
/// Значения подставляются на этапе сборки через `--dart-define`
/// (см. `run_dev.sh` / `.vscode/launch.json`) и становятся compile-time
/// константами. В исходниках и в Git их НЕТ.
///
/// Правила:
/// 1. Ничего секретного в этом файле не пишем — только имена переменных.
/// 2. `service_role`-ключ Supabase сюда НЕ попадает ни при каких условиях:
///    он бэкенд-уровня и в клиентское приложение включаться не должен.
/// 3. `anon`-ключ — публичный по дизайну Supabase (его всё равно можно
///    достать из APK). Настоящая защита — RLS-политики на стороне БД.
class Env {
  const Env._();

  /// URL self-hosted Supabase (например, https://your-subdomain.beget.app).
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL');

  /// Публичный anon-ключ Supabase (JWT).
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// true, если оба ключа заданы. Если запускаем без них — приложение
  /// продолжит работать на моках (пока бэкенд не подключён).
  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Падает на старте, если забыли передать ключи в релизной сборке.
  /// Вызывать в `main()` только для release-билдов.
  static void assertConfigured() {
    if (!hasSupabaseConfig) {
      throw StateError(
        'Supabase не сконфигурирован. Передайте --dart-define=SUPABASE_URL=... '
        'и --dart-define=SUPABASE_ANON_KEY=... при сборке.',
      );
    }
  }
}

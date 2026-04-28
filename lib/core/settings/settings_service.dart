import 'package:supabase_flutter/supabase_flutter.dart';

/// Глобальные настройки из таблицы `public.settings`. Загружаются один
/// раз при первом обращении и держатся в памяти. RLS пропускает чтение
/// `key`/`value` всем authenticated, запись — service_role.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  SupabaseClient get _client => Supabase.instance.client;

  Map<String, dynamic>? _cache;

  Future<void> _load() async {
    if (_cache != null) return;
    try {
      final List<Map<String, dynamic>> rows =
          await _client.from('settings').select('key, value');
      _cache = <String, dynamic>{
        for (final Map<String, dynamic> r in rows) r['key'] as String: r['value'],
      };
    } catch (_) {
      _cache = const <String, dynamic>{};
    }
  }

  /// Прогревает кэш настроек на старте приложения. Вызывается из `main()`
  /// fire-and-forget вместе с CatalogService.warmup() — после этого все
  /// геттеры возвращают значения мгновенно, без сетевого запроса.
  Future<void> warmup() => _load();

  Future<int> subscriptionMonthlyPriceRub() async {
    await _load();
    return (_cache!['subscription.monthly_price_rub'] as num?)?.toInt() ?? 1000;
  }

  Future<int> serviceSlotPriceRub() async {
    await _load();
    return (_cache!['service_slot.price_rub'] as num?)?.toInt() ?? 1000;
  }

  Future<int> orderDailyLimit() async {
    await _load();
    return (_cache!['order.daily_limit'] as num?)?.toInt() ?? 30;
  }

  Future<String> termsCurrentVersion() async {
    await _load();
    return (_cache!['terms.current_version'] as String?) ?? '1.0';
  }
}

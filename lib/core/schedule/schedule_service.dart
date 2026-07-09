import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/catalog/catalog_service.dart';
import 'package:dispatcher_1/core/catalog/models.dart';

/// Sparse-storage модель графика: `schedule_day_overrides` содержит
/// только дни, отличающиеся от дефолта. Как трактуется день БЕЗ записи —
/// решает серверная настройка `schedule.unmarked_day_available`
/// (см. SettingsService.unmarkedDayAvailable): true — рабочий (легаси),
/// false — нерабочий, пока исполнитель явно не отметит его рабочим.
/// Параметры дня без собственных настроек берутся из карточки
/// исполнителя (executor_cards).
class ScheduleService {
  ScheduleService._();
  static final ScheduleService instance = ScheduleService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Загружает все мои override'ы. Ключ — дата (UTC midnight),
  /// чтобы Map.lookup по DateTime работал.
  Future<Map<DateTime, ScheduleDayOverride>> loadMyOverrides({
    DateTime? from,
    DateTime? to,
  }) async {
    final User? user = _client.auth.currentUser;
    if (user == null) return <DateTime, ScheduleDayOverride>{};
    await CatalogService.instance.listActiveMachinery();

    PostgrestFilterBuilder<List<Map<String, dynamic>>> q = _client
        .from('schedule_day_overrides')
        .select(
          'day, accepting, is_day_off, time_from, time_to, whole_day, '
          'radius_km, location_address, location_lat, location_lng, '
          'machinery_ids, category_ids',
        )
        .eq('user_id', user.id);

    if (from != null) {
      q = q.gte('day', _isoDate(from));
    }
    if (to != null) {
      q = q.lte('day', _isoDate(to));
    }

    final List<Map<String, dynamic>> rows = await q;
    await CatalogService.instance.listActiveCategories();
    final Map<int, String> machineryById = <int, String>{
      for (final MachineryRef m
          in CatalogService.instance.cachedMachinery ?? const <MachineryRef>[])
        m.id: m.title,
    };
    final Map<int, String> categoryById = <int, String>{
      for (final CategoryRef c
          in CatalogService.instance.cachedCategories ?? const <CategoryRef>[])
        c.id: c.title,
    };

    final Map<DateTime, ScheduleDayOverride> out =
        <DateTime, ScheduleDayOverride>{};
    for (final Map<String, dynamic> r in rows) {
      final DateTime day = DateTime.parse(r['day'] as String).toLocal();
      final List<int> mIds = List<int>.from(r['machinery_ids'] as List);
      final List<int> cIds = List<int>.from(r['category_ids'] as List);
      out[DateTime(day.year, day.month, day.day)] = ScheduleDayOverride(
        day: day,
        accepting: r['accepting'] as bool,
        // Отсутствие поля (сервер без миграции 107) трактуем как
        // «выходной» — так вели себя старые сборки, где accepting=false
        // всегда означал выходной. Легаси-строки на сервере бэкфилнуты
        // в is_day_off=true, это только подстраховка.
        isDayOff: (r['is_day_off'] as bool?) ?? true,
        timeFrom: r['time_from'] as String?,
        timeTo: r['time_to'] as String?,
        wholeDay: r['whole_day'] as bool,
        radiusKm: r['radius_km'] as int?,
        locationAddress: r['location_address'] as String?,
        locationLat: (r['location_lat'] as num?)?.toDouble(),
        locationLng: (r['location_lng'] as num?)?.toDouble(),
        machineryTitles: CatalogService.instance
            .machineryIdsInCatalogOrder(mIds)
            .map((int id) => machineryById[id] ?? '')
            .where((String t) => t.isNotEmpty)
            .toList(),
        categoryTitles: cIds
            .map((int id) => categoryById[id] ?? '')
            .where((String t) => t.isNotEmpty)
            .toList(),
      );
    }
    return out;
  }

  /// UPSERT override'а на конкретную дату.
  ///
  /// [isDayOff] различает «выходной» (true) и «закрыт приём заказов»
  /// (false при accepting=false — принятые заказы дня остаются видимыми).
  /// null — колонку не шлём: при UPDATE существующей записи сохраняется
  /// прежнее значение, при INSERT срабатывает серверный дефолт (false).
  Future<void> upsertOverride({
    required DateTime day,
    required bool accepting,
    bool? isDayOff,
    String? timeFrom,
    String? timeTo,
    bool wholeDay = false,
    int? radiusKm,
    String? locationAddress,
    double? locationLat,
    double? locationLng,
    List<String> machineryTitles = const <String>[],
    List<String> categoryTitles = const <String>[],
  }) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    final List<MachineryRef> machinery =
        await CatalogService.instance.listActiveMachinery();
    final List<CategoryRef> categories =
        await CatalogService.instance.listActiveCategories();
    final Map<String, int> machineryByTitle = <String, int>{
      for (final MachineryRef m in machinery) m.title: m.id,
    };
    final Map<String, int> categoryByTitle = <String, int>{
      for (final CategoryRef c in categories) c.title: c.id,
    };
    final List<int> machineryIds = <int>[];
    for (final String t in machineryTitles) {
      final int? id = machineryByTitle[t];
      if (id == null) {
        // Справочник техники изменился (переименовали/удалили) — title
        // больше не резолвится в id. Молча отфильтровывали — у пользователя
        // часть техники пропадала из override'а без объяснения. Логируем,
        // чтобы это всплыло в отладке/телеметрии.
        if (kDebugMode) {
          debugPrint(
              '[ScheduleService] machinery title not in catalog: "$t"');
        }
        continue;
      }
      machineryIds.add(id);
    }
    final List<int> categoryIds = <int>[];
    for (final String t in categoryTitles) {
      final int? id = categoryByTitle[t];
      if (id == null) {
        if (kDebugMode) {
          debugPrint('[ScheduleService] category title not in catalog: "$t"');
        }
        continue;
      }
      categoryIds.add(id);
    }

    final Map<String, dynamic> row = <String, dynamic>{
      'user_id': user.id,
      'day': _isoDate(day),
      'accepting': accepting,
      'time_from': timeFrom == null ? null : '$timeFrom:00',
      'time_to': timeTo == null ? null : '$timeTo:00',
      'whole_day': wholeDay,
      'radius_km': radiusKm,
      'location_address': locationAddress,
      'location_lat': locationLat,
      'location_lng': locationLng,
      'machinery_ids': machineryIds,
      'category_ids': categoryIds,
    };
    if (isDayOff != null) {
      row['is_day_off'] = isDayOff;
    }
    await _client.from('schedule_day_overrides').upsert(row);
  }

  /// Возвращает день к дефолту (рабочий, параметры из карточки исполнителя).
  Future<void> resetToDefault(DateTime day) async {
    final User? user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from('schedule_day_overrides')
        .delete()
        .eq('user_id', user.id)
        .eq('day', _isoDate(day));
  }

  /// Атомарно отмечает день нерабочим: накатывает override
  /// (`accepting=false`) и переводит все accepted-мэтчи исполнителя на
  /// заказы, чей период покрывает [day], в `rejected_by_executor`.
  /// RPC `mark_executor_day_off` делает второе UPDATE — первое
  /// (UPSERT override) клиент уже сам отправил через [upsertOverride].
  /// См. миграцию `cancel_matches_on_executor_day_off`.
  Future<void> cancelAcceptedMatchesOnDay(DateTime day) async {
    await _client.rpc<dynamic>(
      'mark_executor_day_off',
      params: <String, dynamic>{'p_day': _isoDate(day)},
    );
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class ScheduleDayOverride {
  const ScheduleDayOverride({
    required this.day,
    required this.accepting,
    required this.isDayOff,
    required this.timeFrom,
    required this.timeTo,
    required this.wholeDay,
    required this.radiusKm,
    required this.locationAddress,
    required this.locationLat,
    required this.locationLng,
    required this.machineryTitles,
    required this.categoryTitles,
  });

  final DateTime day;
  final bool accepting;

  /// true — выходной (день серый, заказы не показываются); false при
  /// accepting=false — «закрыт приём»: новые заказы не приходят, но
  /// принятые на этот день остаются видимыми в графике.
  final bool isDayOff;
  final String? timeFrom; // 'HH:mm:ss'
  final String? timeTo;
  final bool wholeDay;
  final int? radiusKm; // 10/20/50
  final String? locationAddress;
  final double? locationLat;
  final double? locationLng;
  final List<String> machineryTitles;
  final List<String> categoryTitles;
}

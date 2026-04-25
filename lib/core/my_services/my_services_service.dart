import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/catalog/catalog_service.dart';
import 'package:dispatcher_1/core/catalog/models.dart';

import 'models.dart';

/// Чтение/запись моих услуг (`public.services` с RLS `executor_id = auth.uid()`).
/// Конвертация названий техники/категорий ↔ id опирается на кэш в
/// [CatalogService] — его директорий достаточно за глаза (9 категорий,
/// 14 типов техники).
class MyServicesService {
  MyServicesService._();
  static final MyServicesService instance = MyServicesService._();

  SupabaseClient get _client => Supabase.instance.client;
  CatalogService get _catalog => CatalogService.instance;

  Future<List<MyServiceSummary>> listMine() async {
    final User? user = _client.auth.currentUser;
    if (user == null) return <MyServiceSummary>[];
    await _ensureDirectories();
    final List<Map<String, dynamic>> rows = await _client
        .from('services')
        .select(
          'id, title, description, machinery_ids, category_ids, '
          'price_per_hour, price_per_day, min_hours, is_paid',
        )
        .eq('executor_id', user.id)
        .eq('is_archived', false)
        .order('created_at', ascending: false);
    return rows.map(_summaryFromRow).toList();
  }

  Future<MyServiceDetail?> getMine(String id) async {
    final User? user = _client.auth.currentUser;
    if (user == null) return null;
    await _ensureDirectories();
    final Map<String, dynamic>? r = await _client
        .from('services')
        .select(
          'id, title, description, machinery_ids, category_ids, '
          'price_per_hour, price_per_day, min_hours, photos, '
          'location_address, location_lat, location_lng, radius_km, '
          'is_paid, is_archived',
        )
        .eq('id', id)
        .eq('executor_id', user.id)
        .maybeSingle();
    if (r == null) return null;
    return _detailFromRow(r);
  }

  /// Создание новой услуги. На момент вызова пользователь уже "оплатил" слот
  /// (в dev-режиме без реальной оплаты — is_paid ставится в true сразу).
  Future<String> create(ServiceDraft d) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    final Map<String, dynamic> payload = await _draftToRow(d);
    payload['executor_id'] = user.id;
    payload['is_paid'] = true;
    final Map<String, dynamic> row = await _client
        .from('services')
        .insert(payload)
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> update(String id, ServiceDraft d) async {
    final Map<String, dynamic> payload = await _draftToRow(d);
    await _client.from('services').update(payload).eq('id', id);
  }

  /// Мягкое удаление: `is_archived = true`. Из ленты выпадает, но
  /// исторические `order_matches` продолжают ссылаться на услугу.
  Future<void> archive(String id) async {
    await _client.from('services').update(<String, dynamic>{
      'is_archived': true,
    }).eq('id', id);
  }

  // ---------------------------------------------------------------
  // internals
  // ---------------------------------------------------------------

  Future<void> _ensureDirectories() async {
    await _catalog.listActiveMachinery();
    await _catalog.listActiveCategories();
  }

  MyServiceSummary _summaryFromRow(Map<String, dynamic> r) {
    final List<int> mIds = List<int>.from(r['machinery_ids'] as List);
    final List<int> cIds = List<int>.from(r['category_ids'] as List);
    return MyServiceSummary(
      id: r['id'] as String,
      title: r['title'] as String,
      description: r['description'] as String?,
      machineryIds: mIds,
      categoryIds: cIds,
      machineryTitles: _resolveMachinery(mIds),
      categoryTitles: _resolveCategories(cIds),
      pricePerHour: _toDouble(r['price_per_hour']),
      pricePerDay: _toDouble(r['price_per_day']),
      minHours: r['min_hours'] as int?,
      isPaid: r['is_paid'] as bool,
    );
  }

  MyServiceDetail _detailFromRow(Map<String, dynamic> r) {
    final List<int> mIds = List<int>.from(r['machinery_ids'] as List);
    final List<int> cIds = List<int>.from(r['category_ids'] as List);
    return MyServiceDetail(
      id: r['id'] as String,
      title: r['title'] as String,
      description: r['description'] as String?,
      machineryIds: mIds,
      categoryIds: cIds,
      machineryTitles: _resolveMachinery(mIds),
      categoryTitles: _resolveCategories(cIds),
      pricePerHour: _toDouble(r['price_per_hour']),
      pricePerDay: _toDouble(r['price_per_day']),
      minHours: r['min_hours'] as int?,
      photos: List<String>.from(r['photos'] as List),
      locationAddress: r['location_address'] as String?,
      locationLat: (r['location_lat'] as num?)?.toDouble(),
      locationLng: (r['location_lng'] as num?)?.toDouble(),
      radiusKm: r['radius_km'] as int?,
      isPaid: r['is_paid'] as bool,
      isArchived: r['is_archived'] as bool,
    );
  }

  Future<Map<String, dynamic>> _draftToRow(ServiceDraft d) async {
    final List<MachineryRef> machinery = await _catalog.listActiveMachinery();
    final List<CategoryRef> categories = await _catalog.listActiveCategories();
    final Map<String, int> machineryByTitle = <String, int>{
      for (final MachineryRef m in machinery) m.title: m.id,
    };
    final Map<String, int> categoryByTitle = <String, int>{
      for (final CategoryRef c in categories) c.title: c.id,
    };
    final List<int> machineryIds = d.machineryTitles
        .map((String t) => machineryByTitle[t])
        .whereType<int>()
        .toList();
    final List<int> categoryIds = d.categoryTitles
        .map((String t) => categoryByTitle[t])
        .whereType<int>()
        .toList();
    return <String, dynamic>{
      'title': d.title,
      'description': d.description,
      'machinery_ids': machineryIds,
      'category_ids': categoryIds,
      'price_per_hour': d.pricePerHour,
      'price_per_day': d.pricePerDay,
      'min_hours': d.minHours,
      'photos': d.photos,
      'location_address': d.locationAddress,
      'radius_km': d.radiusKm,
    };
  }

  List<String> _resolveMachinery(List<int> ids) {
    final List<MachineryRef> cache =
        CatalogService.instance.cachedMachinery ?? const <MachineryRef>[];
    final Map<int, String> byId = <int, String>{
      for (final MachineryRef m in cache) m.id: m.title,
    };
    return ids
        .map((int id) => byId[id] ?? '')
        .where((String t) => t.isNotEmpty)
        .toList();
  }

  List<String> _resolveCategories(List<int> ids) {
    final List<CategoryRef> cache =
        CatalogService.instance.cachedCategories ?? const <CategoryRef>[];
    final Map<int, String> byId = <int, String>{
      for (final CategoryRef c in cache) c.id: c.title,
    };
    return ids
        .map((int id) => byId[id] ?? '')
        .where((String t) => t.isNotEmpty)
        .toList();
  }

  double? _toDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

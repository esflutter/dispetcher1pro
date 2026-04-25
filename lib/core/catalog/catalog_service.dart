import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Чтение каталога из Supabase: справочники, лента заказов,
/// карточка одного заказа и карточка заказчика. Отклик на заказ —
/// отдельный метод [respondToOrder] (INSERT в `order_matches`).
class _ExecAggregate {
  final Set<int> machineryIds = <int>{};
  final Set<int> categoryIds = <int>{};
  double? minPriceHour;
  double? minPriceDay;

  void addMachinery(List<int> ids) => machineryIds.addAll(ids);
  void addCategory(List<int> ids) => categoryIds.addAll(ids);
}

class CatalogService {
  CatalogService._();
  static final CatalogService instance = CatalogService._();

  SupabaseClient get _client => Supabase.instance.client;

  // ---------------------------------------------------------------
  // Справочники + in-memory кэш (живёт до перезапуска приложения)
  // ---------------------------------------------------------------

  List<MachineryRef>? _machineryCache;
  List<CategoryRef>? _categoryCache;

  /// Последний результат [listActiveMachinery] (или null, если ещё не
  /// загружали). Нужен для синхронного резолвинга id→title в моделях.
  List<MachineryRef>? get cachedMachinery => _machineryCache;

  /// То же для категорий.
  List<CategoryRef>? get cachedCategories => _categoryCache;
  Map<int, String> get _machineryIdToTitle => <int, String>{
        for (final MachineryRef m in _machineryCache ?? const <MachineryRef>[])
          m.id: m.title,
      };
  Map<String, int> get _machineryTitleToId => <String, int>{
        for (final MachineryRef m in _machineryCache ?? const <MachineryRef>[])
          m.title: m.id,
      };
  Map<int, String> get _categoryIdToTitle => <int, String>{
        for (final CategoryRef c in _categoryCache ?? const <CategoryRef>[])
          c.id: c.title,
      };
  Map<String, int> get _categoryTitleToId => <String, int>{
        for (final CategoryRef c in _categoryCache ?? const <CategoryRef>[])
          c.title: c.id,
      };

  Future<List<MachineryRef>> listActiveMachinery() async {
    if (_machineryCache != null) return _machineryCache!;
    final List<Map<String, dynamic>> rows = await _client
        .from('machinery_types')
        .select('id, title')
        .eq('is_active', true)
        .order('sort_order');
    _machineryCache = rows.map(MachineryRef.fromRow).toList();
    return _machineryCache!;
  }

  Future<List<CategoryRef>> listActiveCategories() async {
    if (_categoryCache != null) return _categoryCache!;
    final List<Map<String, dynamic>> rows = await _client
        .from('categories')
        .select('id, title')
        .eq('is_active', true)
        .order('sort_order');
    _categoryCache = rows.map(CategoryRef.fromRow).toList();
    return _categoryCache!;
  }

  Future<void> _primeDirectories() async {
    await Future.wait<void>(<Future<void>>[
      listActiveMachinery(),
      listActiveCategories(),
    ]);
  }

  // ---------------------------------------------------------------
  // Лента заказов
  // ---------------------------------------------------------------

  Future<List<OrderListItem>> listPublishedOrders({
    Set<String> machineryTitles = const <String>{},
    Set<String> categoryTitles = const <String>{},
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? addressContains,
    int limit = 50,
  }) async {
    await _primeDirectories();

    final List<int> machineryIds = machineryTitles
        .map((String t) => _machineryTitleToId[t])
        .whereType<int>()
        .toList();
    final List<int> categoryIds = categoryTitles
        .map((String t) => _categoryTitleToId[t])
        .whereType<int>()
        .toList();

    // Собираем фильтр в PostgrestFilterBuilder (до .order/.limit), чтобы
    // можно было последовательно навешивать условия.
    PostgrestFilterBuilder<List<Map<String, dynamic>>> q = _client
        .from('orders')
        .select(
          'id, display_number, title, address, date_from, date_to, '
          'time_from, time_to, exact_date, whole_day, machinery_ids, '
          'published_at, '
          'customer:profiles!orders_customer_id_fkey('
          'id, name, avatar_url, rating_as_customer, review_count_as_customer)',
        )
        .eq('status', 'published');

    if (machineryIds.isNotEmpty) {
      q = q.overlaps('machinery_ids', machineryIds);
    }
    if (categoryIds.isNotEmpty) {
      q = q.overlaps('category_ids', categoryIds);
    }

    final String? s = search?.trim();
    if (s != null && s.isNotEmpty) {
      final String esc = s.replaceAll(',', ' '); // запятая ломает or-синтаксис
      q = q.or('title.ilike.%$esc%,address.ilike.%$esc%');
    }
    if (dateFrom != null) {
      q = q.gte('date_from', _isoDate(dateFrom));
    }
    if (dateTo != null) {
      // Заказ начинается не позже выбранной верхней даты диапазона.
      q = q.lte('date_from', _isoDate(dateTo));
    }
    if (addressContains != null && addressContains.trim().isNotEmpty) {
      final String esc = addressContains.trim().replaceAll(',', ' ');
      q = q.ilike('address', '%$esc%');
    }

    final List<Map<String, dynamic>> rows =
        await q.order('published_at', ascending: false).limit(limit);
    return rows.map(_orderListItemFromRow).toList();
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  OrderListItem _orderListItemFromRow(Map<String, dynamic> r) {
    final List<int> machineryIds = List<int>.from(r['machinery_ids'] as List);
    final List<String> titles = machineryIds
        .map((int id) => _machineryIdToTitle[id] ?? '')
        .where((String t) => t.isNotEmpty)
        .toList();
    final dynamic customerRaw = r['customer'];
    final CustomerSummary cust = customerRaw is Map<String, dynamic>
        ? CustomerSummary.fromRow(customerRaw)
        : const CustomerSummary(
            id: '',
            name: 'Пользователь',
            ratingAsCustomer: 0,
            reviewCountAsCustomer: 0,
          );
    return OrderListItem(
      id: r['id'] as String,
      displayNumber: r['display_number'] as int,
      title: r['title'] as String,
      address: r['address'] as String,
      dateFrom: DateTime.parse(r['date_from'] as String),
      dateTo: r['date_to'] == null
          ? null
          : DateTime.parse(r['date_to'] as String),
      timeFrom: r['time_from'] as String?,
      timeTo: r['time_to'] as String?,
      exactDate: r['exact_date'] as bool,
      wholeDay: r['whole_day'] as bool,
      machineryTitles: titles,
      publishedAt: DateTime.parse(r['published_at'] as String),
      customer: cust,
    );
  }

  // ---------------------------------------------------------------
  // Детали одного заказа
  // ---------------------------------------------------------------

  Future<OrderDetail?> getOrderDetail(String orderId) async {
    await _primeDirectories();
    final Map<String, dynamic>? r = await _client
        .from('orders')
        .select(
          'id, display_number, title, description, address, latitude, '
          'longitude, date_from, date_to, time_from, time_to, exact_date, '
          'whole_day, machinery_ids, category_ids, works, photos, '
          'published_at, '
          'customer:profiles!orders_customer_id_fkey('
          'id, name, avatar_url, rating_as_customer, review_count_as_customer)',
        )
        .eq('id', orderId)
        .maybeSingle();
    if (r == null) return null;

    final List<int> machineryIds = List<int>.from(r['machinery_ids'] as List);
    final List<int> categoryIds = List<int>.from(r['category_ids'] as List);
    final List<String> machineryTitles = machineryIds
        .map((int id) => _machineryIdToTitle[id] ?? '')
        .where((String t) => t.isNotEmpty)
        .toList();
    final List<String> categoryTitles = categoryIds
        .map((int id) => _categoryIdToTitle[id] ?? '')
        .where((String t) => t.isNotEmpty)
        .toList();

    final List<dynamic> worksRaw = (r['works'] as List?) ?? const <dynamic>[];
    final List<WorkItem> works = worksRaw
        .whereType<Map<String, dynamic>>()
        .map(WorkItem.fromJson)
        .toList();

    final dynamic customerRaw = r['customer'];
    final CustomerSummary cust = customerRaw is Map<String, dynamic>
        ? CustomerSummary.fromRow(customerRaw)
        : const CustomerSummary(
            id: '',
            name: 'Пользователь',
            ratingAsCustomer: 0,
            reviewCountAsCustomer: 0,
          );

    return OrderDetail(
      id: r['id'] as String,
      displayNumber: r['display_number'] as int,
      title: r['title'] as String,
      description: r['description'] as String?,
      address: r['address'] as String,
      latitude: (r['latitude'] as num?)?.toDouble(),
      longitude: (r['longitude'] as num?)?.toDouble(),
      dateFrom: DateTime.parse(r['date_from'] as String),
      dateTo: r['date_to'] == null
          ? null
          : DateTime.parse(r['date_to'] as String),
      timeFrom: r['time_from'] as String?,
      timeTo: r['time_to'] as String?,
      exactDate: r['exact_date'] as bool,
      wholeDay: r['whole_day'] as bool,
      machineryTitles: machineryTitles,
      categoryTitles: categoryTitles,
      works: works,
      photos: List<String>.from(r['photos'] as List),
      publishedAt: DateTime.parse(r['published_at'] as String),
      customer: cust,
    );
  }

  // ---------------------------------------------------------------
  // Каталог исполнителей (видит заказчик)
  // ---------------------------------------------------------------

  Future<List<ExecutorCardListItem>> listPublishedExecutors({
    Set<String> machineryTitles = const <String>{},
    Set<String> categoryTitles = const <String>{},
    String? search,
    int limit = 50,
  }) async {
    await _primeDirectories();

    final List<int> machineryIds = machineryTitles
        .map((String t) => _machineryTitleToId[t])
        .whereType<int>()
        .toList();
    final List<int> categoryIds = categoryTitles
        .map((String t) => _categoryTitleToId[t])
        .whereType<int>()
        .toList();

    PostgrestFilterBuilder<List<Map<String, dynamic>>> q = _client
        .from('executor_cards')
        .select(
          'user_id, location_address, radius_km, '
          'profile:profiles!executor_cards_user_id_fkey('
          'id, name, avatar_url, legal_status, experience_years, '
          'rating_as_executor, review_count_as_executor)',
        )
        .eq('is_published', true);

    final String? s = search?.trim();
    if (s != null && s.isNotEmpty) {
      // Поиск по имени исполнителя через related-таблицу.
      final String esc = s.replaceAll(',', ' ');
      q = q.ilike('profile.name', '%$esc%');
    }

    final List<Map<String, dynamic>> cards =
        await q.order('updated_at', ascending: false).limit(limit);

    if (cards.isEmpty) return <ExecutorCardListItem>[];

    final List<String> userIds =
        cards.map((Map<String, dynamic> r) => r['user_id'] as String).toList();
    final List<Map<String, dynamic>> services = await _client
        .from('services')
        .select(
          'executor_id, machinery_ids, category_ids, '
          'price_per_hour, price_per_day',
        )
        .inFilter('executor_id', userIds)
        .eq('is_paid', true)
        .eq('is_archived', false);

    // Aggregate by executor.
    final Map<String, _ExecAggregate> byUser =
        <String, _ExecAggregate>{};
    for (final Map<String, dynamic> s in services) {
      final String uid = s['executor_id'] as String;
      final _ExecAggregate agg =
          byUser.putIfAbsent(uid, _ExecAggregate.new);
      agg.addMachinery(List<int>.from(s['machinery_ids'] as List));
      agg.addCategory(List<int>.from(s['category_ids'] as List));
      agg.minPriceHour = _min(agg.minPriceHour, _toDouble(s['price_per_hour']));
      agg.minPriceDay = _min(agg.minPriceDay, _toDouble(s['price_per_day']));
    }

    final List<ExecutorCardListItem> out = <ExecutorCardListItem>[];
    for (final Map<String, dynamic> c in cards) {
      final String uid = c['user_id'] as String;
      final Map<String, dynamic> p =
          c['profile'] as Map<String, dynamic>;
      final _ExecAggregate agg =
          byUser[uid] ?? _ExecAggregate();
      // Если задан фильтр по технике/категориям — отсекаем тех, у кого
      // нет ни одной услуги, попадающей под фильтр.
      if (machineryIds.isNotEmpty &&
          !machineryIds.any(agg.machineryIds.contains)) {
        continue;
      }
      if (categoryIds.isNotEmpty &&
          !categoryIds.any(agg.categoryIds.contains)) {
        continue;
      }
      out.add(ExecutorCardListItem(
        userId: uid,
        name: (p['name'] as String?) ?? 'Пользователь',
        avatarUrl: p['avatar_url'] as String?,
        ratingAsExecutor: _toDouble(p['rating_as_executor']) ?? 0,
        reviewCountAsExecutor:
            (p['review_count_as_executor'] as int?) ?? 0,
        legalStatus: p['legal_status'] as String?,
        experienceYears: p['experience_years'] as int?,
        locationAddress: c['location_address'] as String?,
        radiusKm: c['radius_km'] as int?,
        machineryTitles: agg.machineryIds
            .map((int id) => _machineryIdToTitle[id] ?? '')
            .where((String t) => t.isNotEmpty)
            .toList(),
        categoryTitles: agg.categoryIds
            .map((int id) => _categoryIdToTitle[id] ?? '')
            .where((String t) => t.isNotEmpty)
            .toList(),
        minPricePerHour: agg.minPriceHour,
        minPricePerDay: agg.minPriceDay,
      ));
    }
    return out;
  }

  Future<ExecutorCardListItem?> getExecutorById(String userId) async {
    final List<ExecutorCardListItem> all =
        await listPublishedExecutors(limit: 100);
    for (final ExecutorCardListItem e in all) {
      if (e.userId == userId) return e;
    }
    return null;
  }

  double? _toDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  double? _min(double? a, double? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a < b ? a : b;
  }

  // ---------------------------------------------------------------
  // Карточка заказчика
  // ---------------------------------------------------------------

  Future<CustomerProfile?> getCustomer(String userId) async {
    final Map<String, dynamic>? r = await _client
        .from('profiles')
        .select(
          'id, name, avatar_url, legal_status, about, '
          'rating_as_customer, review_count_as_customer',
        )
        .eq('id', userId)
        .maybeSingle();
    if (r == null) return null;
    return CustomerProfile.fromRow(r);
  }

  /// Заказы конкретного заказчика — для списка на его карточке.
  /// По умолчанию только `published` (чтобы не утекали черновики/архив).
  Future<List<OrderListItem>> listCustomerOrders(String userId,
      {int limit = 50}) async {
    await _primeDirectories();
    final List<Map<String, dynamic>> rows = await _client
        .from('orders')
        .select(
          'id, display_number, title, address, date_from, date_to, '
          'time_from, time_to, exact_date, whole_day, machinery_ids, '
          'published_at, '
          'customer:profiles!orders_customer_id_fkey('
          'id, name, avatar_url, rating_as_customer, review_count_as_customer)',
        )
        .eq('customer_id', userId)
        .eq('status', 'published')
        .order('published_at', ascending: false)
        .limit(limit);
    return rows.map(_orderListItemFromRow).toList();
  }

  /// Последние отзывы о заказчике (subject='customer').
  Future<List<ReviewItem>> listCustomerReviews(String userId,
      {int limit = 20}) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('reviews')
        .select(
          'id, rating, text, created_at, '
          'author:profiles!reviews_author_id_fkey(name)',
        )
        .eq('target_id', userId)
        .eq('subject', 'customer')
        .eq('is_hidden', false)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(ReviewItem.fromRow).toList();
  }

  // ---------------------------------------------------------------
  // Отклик на заказ
  // ---------------------------------------------------------------

  /// Мои активные (`is_archived=false`, `is_paid=true`) услуги — маппинг
  /// названия техники → id услуги. Нужно для отклика: по выбранной технике
  /// находим service_id, который уйдёт в `order_matches`.
  Future<Map<String, String>> listMyActiveServicesByMachinery() async {
    await _primeDirectories();
    final User? user = _client.auth.currentUser;
    if (user == null) return <String, String>{};
    final List<Map<String, dynamic>> rows = await _client
        .from('services')
        .select('id, machinery_ids')
        .eq('executor_id', user.id)
        .eq('is_archived', false)
        .eq('is_paid', true);
    final Map<String, String> out = <String, String>{};
    for (final Map<String, dynamic> r in rows) {
      final List<int> ids = List<int>.from(r['machinery_ids'] as List);
      if (ids.isEmpty) continue;
      final String? title = _machineryIdToTitle[ids.first];
      if (title != null) out[title] = r['id'] as String;
    }
    return out;
  }

  /// Есть ли у меня активный (не терминальный) отклик на этот заказ.
  /// Используется, чтобы на экране заказа кнопка сразу стала "Вы уже
  /// откликнулись".
  Future<bool> hasActiveMatchForOrder(String orderId) async {
    final User? user = _client.auth.currentUser;
    if (user == null) return false;
    final Map<String, dynamic>? row = await _client
        .from('order_matches')
        .select('id')
        .eq('order_id', orderId)
        .eq('executor_id', user.id)
        .not(
          'status',
          'in',
          '(completed,rejected_by_customer,rejected_by_executor,expired)',
        )
        .maybeSingle();
    return row != null;
  }

  /// INSERT в `order_matches` (initiated_by='executor', status='awaiting_customer').
  /// Цена автоматически снапшотится триггером из `services(service_id)`.
  /// Возвращает id созданного мэтча.
  Future<String> respondToOrder({
    required String orderId,
    required String serviceId,
  }) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    final Map<String, dynamic> row = await _client
        .from('order_matches')
        .insert(<String, dynamic>{
          'order_id': orderId,
          'executor_id': user.id,
          'service_id': serviceId,
          'initiated_by': 'executor',
          'status': 'awaiting_customer',
        })
        .select('id')
        .single();
    return row['id'] as String;
  }
}

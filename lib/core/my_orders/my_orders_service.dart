import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/catalog/catalog_service.dart';
import 'package:dispatcher_1/core/catalog/models.dart';

import 'models.dart';

/// Заказчик подтвердил другого исполнителя раньше (race на UNIQUE-индексе
/// `order_matches_single_accepted`). UI должен показать сообщение
/// «На этот заказ уже выбрали другого исполнителя».
class MatchAlreadyTakenException implements Exception {
  const MatchAlreadyTakenException();
  @override
  String toString() => 'Match already taken';
}

/// Чтение/обновление моих откликов (`order_matches` WHERE executor_id = me).
/// FSM-переходы статуса валидирует триггер `validate_match_transition`
/// в БД — клиент только пишет целевой статус.
class MyOrdersService {
  MyOrdersService._();
  static final MyOrdersService instance = MyOrdersService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<MyOrderMatch>> listMine({int limit = 100}) async {
    final User? user = _client.auth.currentUser;
    if (user == null) return <MyOrderMatch>[];

    await CatalogService.instance.listActiveMachinery();

    final List<Map<String, dynamic>> rows = await _client
        .from('order_matches')
        .select(
          'id, order_id, status, created_at, '
          'agreed_price_per_hour, agreed_price_per_day, agreed_min_hours, '
          'order:orders!order_matches_order_id_fkey('
          'id, display_number, title, address, date_from, date_to, '
          'time_from, time_to, exact_date, whole_day, machinery_ids, '
          'customer:profiles!orders_customer_id_fkey('
          'id, name, rating_as_customer, review_count_as_customer)), '
          'service:services!order_matches_service_id_fkey(machinery_ids)',
        )
        .eq('executor_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit);

    return rows.map(_fromRow).toList();
  }

  /// Отзывает отклик (`awaiting_customer` → `rejected_by_executor`).
  /// Отказ после `accepted` запрещён FSM-триггером.
  Future<void> withdraw(String matchId) async {
    await _client
        .from('order_matches')
        .update(<String, dynamic>{'status': 'rejected_by_executor'})
        .eq('id', matchId);
  }

  /// Подтвердить мэтч (`awaiting_executor` → `accepted`).
  /// Бросает [MatchAlreadyTakenException], если на этот заказ уже
  /// проставлен другой accepted-мэтч (заказчик одновременно подтвердил
  /// другого исполнителя). UNIQUE-индекс `order_matches_single_accepted`
  /// возвращает 23505 — клиент должен показать понятное сообщение.
  Future<void> acceptMatch(String matchId) async {
    try {
      await _client
          .from('order_matches')
          .update(<String, dynamic>{'status': 'accepted'})
          .eq('id', matchId);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const MatchAlreadyTakenException();
      }
      rethrow;
    }
  }

  /// Отказаться от заказа, которого мы ждали подтверждать
  /// (`awaiting_executor` → `rejected_by_executor`).
  Future<void> declineMatch(String matchId) async {
    await _client
        .from('order_matches')
        .update(<String, dynamic>{'status': 'rejected_by_executor'})
        .eq('id', matchId);
  }

  /// Контакты заказчика (телефон/email) — доступны только после
  /// `accepted`/`completed` через RLS-политику на `profiles_private`.
  /// Возвращает `null`, если нет доступа.
  Future<({String? phone, String? email})?> getCustomerContacts(
      String customerId) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('profiles_private')
          .select('phone, email')
          .eq('id', customerId)
          .maybeSingle();
      if (row == null) return null;
      return (
        phone: row['phone'] as String?,
        email: row['email'] as String?,
      );
    } on PostgrestException {
      return null;
    }
  }

  // ---------------------------------------------------------------

  MyOrderMatch _fromRow(Map<String, dynamic> r) {
    final Map<String, dynamic> order = r['order'] as Map<String, dynamic>;
    final Map<String, dynamic> customer =
        order['customer'] as Map<String, dynamic>;

    final List<MachineryRef> cache =
        CatalogService.instance.cachedMachinery ?? const <MachineryRef>[];
    final Map<int, String> machineryById = <int, String>{
      for (final MachineryRef m in cache) m.id: m.title,
    };
    final List<int> machineryIds =
        List<int>.from(order['machinery_ids'] as List);
    final List<String> machineryTitles = machineryIds
        .map((int id) => machineryById[id] ?? '')
        .where((String t) => t.isNotEmpty)
        .toList();

    // Та техника, по которой шёл отклик (одна на услугу) — нужна для
    // подписи блока «Цена». Если service был удалён или в схеме хоть
    // и допустимо несколько id'шников, берём первую.
    final Map<String, dynamic>? service =
        r['service'] as Map<String, dynamic>?;
    String? serviceMachineryTitle;
    if (service != null) {
      final List<int> sIds =
          List<int>.from(service['machinery_ids'] as List);
      if (sIds.isNotEmpty) {
        serviceMachineryTitle = machineryById[sIds.first];
      }
    }

    return MyOrderMatch(
      matchId: r['id'] as String,
      orderId: r['order_id'] as String,
      orderDisplayNumber: order['display_number'] as int,
      status: MyMatchStatus.fromDb(r['status'] as String),
      createdAt: DateTime.parse(r['created_at'] as String),
      agreedPricePerHour: _toDouble(r['agreed_price_per_hour']),
      agreedPricePerDay: _toDouble(r['agreed_price_per_day']),
      agreedMinHours: r['agreed_min_hours'] as int?,
      orderTitle: order['title'] as String,
      orderAddress: order['address'] as String,
      orderDateFrom: DateTime.parse(order['date_from'] as String),
      orderDateTo: order['date_to'] == null
          ? null
          : DateTime.parse(order['date_to'] as String),
      orderTimeFrom: order['time_from'] as String?,
      orderTimeTo: order['time_to'] as String?,
      orderExactDate: order['exact_date'] as bool,
      orderWholeDay: order['whole_day'] as bool,
      orderMachineryTitles: machineryTitles,
      serviceMachineryTitle: serviceMachineryTitle,
      customerId: customer['id'] as String,
      customerName: (customer['name'] as String?) ?? 'Пользователь',
      customerRating: _toDouble(customer['rating_as_customer']) ?? 0,
      customerReviewCount:
          (customer['review_count_as_customer'] as int?) ?? 0,
    );
  }

  double? _toDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

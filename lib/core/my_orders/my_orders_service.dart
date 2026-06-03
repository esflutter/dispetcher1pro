import 'package:flutter/foundation.dart';
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

/// Этот исполнитель уже откликался на этот заказ — дальнейший отклик
/// блокирует UNIQUE-индекс `order_matches_non_completed_unique`.
/// Сценарий: исполнитель отозвал свой отклик (или заказчик его отклонил),
/// и теперь хочет откликнуться повторно. По бизнес-правилу повторный
/// отклик запрещён — UI показывает «Вы уже откликались на этот заказ»,
/// чтобы сообщение отличалось от общего «Заказ занят».
class AlreadyRespondedException implements Exception {
  const AlreadyRespondedException();
  @override
  String toString() => 'Already responded to this order';
}

/// Сервер отклонил подтверждение приглашения, потому что у исполнителя не
/// выполнены условия для работы: неактивна подписка, не пройдена верификация
/// или не опубликована карточка. Несёт готовый к показу русский текст —
/// триггер `enforce_executor_engage_requires_subscription` бросает технические
/// коды (`subscription_inactive` и т.п.), которые нельзя показывать как есть.
class MatchEngageBlockedException implements Exception {
  const MatchEngageBlockedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Чтение/обновление моих откликов (`order_matches` WHERE executor_id = me).
/// FSM-переходы статуса валидирует триггер `validate_match_transition`
/// в БД — клиент только пишет целевой статус.
class MyOrdersService {
  MyOrdersService._();
  static final MyOrdersService instance = MyOrdersService._();

  /// Глобальный «маяк» для оповещения экранов «Мои заказы» о том, что
  /// данные мэтчей могли поменяться извне — например, исполнитель
  /// пометил день нерабочим в графике, и accepted-мэтчи на этот день
  /// уехали в `rejected_by_executor`. Сторонний код просто увеличивает
  /// `value`; экран «Мои заказы» подписан и при изменении вызывает
  /// `_refresh()` без необходимости делать pull-to-refresh.
  static final ValueNotifier<int> changeBeacon = ValueNotifier<int>(0);

  /// Сигнализирует подписчикам [changeBeacon] о том, что списки мэтчей
  /// нужно перетянуть из БД.
  static void bumpChangeBeacon() {
    changeBeacon.value = changeBeacon.value + 1;
  }

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<MyOrderMatch>> listMine({int limit = 100}) async {
    final User? user = _client.auth.currentUser;
    if (user == null) return <MyOrderMatch>[];

    await CatalogService.instance.listActiveMachinery();

    await CatalogService.instance.listActiveCategories();

    final List<Map<String, dynamic>> rows = await _client
        .from('order_matches')
        .select(
          'id, order_id, status, created_at, updated_at, status_changed_at, '
          'agreed_price_per_hour, agreed_price_per_day, agreed_min_hours, '
          'order:orders!order_matches_order_id_fkey('
          'id, display_number, title, description, address, '
          'date_from, date_to, time_from, time_to, exact_date, whole_day, '
          'published_at, '
          'machinery_ids, category_ids, works, photos, '
          'customer:profiles!orders_customer_id_fkey('
          'id, name, avatar_url, rating_as_customer, review_count_as_customer)), '
          'service:services!order_matches_service_id_fkey(machinery_ids)',
        )
        .eq('executor_id', user.id)
        // Сортируем по моменту смены статуса. `status_changed_at`
        // обновляется ТОЛЬКО при OLD.status != NEW.status (триггер
        // `set_match_status_changed_at`), поэтому правки цены или
        // других полей не сбрасывают «таймер» и не поднимают карточку
        // наверх. Раньше использовали `updated_at`, который moddatetime
        // обновляет на любой UPDATE.
        .order('status_changed_at', ascending: false)
        .limit(limit);

    // Изолируем битую строку: если у одной записи нет вложенного заказа
    // или сломано поле, не роняем весь список — пропускаем только её.
    final List<MyOrderMatch> out = <MyOrderMatch>[];
    for (final Map<String, dynamic> r in rows) {
      try {
        out.add(_fromRow(r));
      } catch (_) {/* битая строка — пропускаем, остальные показываем */}
    }
    return out;
  }

  /// Исполнитель отзывает свой отклик из `awaiting_customer`. FSM-
  /// триггер `validate_match_transition` разрешает переход
  /// `awaiting_customer → rejected_by_executor` (миграция
  /// `allow_withdraw_from_awaiting_customer`). В UI это рендерится как
  /// «Отклонён» — корректно отражает, что инициатор отказа — исполнитель.
  /// `expired` использовать нельзя: семантически это «снят с публикации»
  /// (заказ удалили / истёк дедлайн), а не отозванный отклик.
  /// `.select().single()` обязательна, чтобы «не нашлось ни одной строки»
  /// (RLS отказал, FSM не пустил) выбрасывало исключение, а не было silent no-op.
  Future<void> withdraw(String matchId) async {
    await _client
        .from('order_matches')
        .update(<String, dynamic>{'status': 'rejected_by_executor'})
        .eq('id', matchId)
        .select('id')
        .single();
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
          .eq('id', matchId)
          .select('id')
          .single();
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const MatchAlreadyTakenException();
      }
      final String? blocked = _engageBlockMessage(e.message);
      if (blocked != null) {
        throw MatchEngageBlockedException(blocked);
      }
      rethrow;
    }
  }

  /// Сопоставляет технические коды серверных проверок «может ли исполнитель
  /// браться за заказ» с человеческими сообщениями. Возвращает `null`, если
  /// ошибка не про эти проверки (тогда вызывающий пробрасывает её дальше).
  static String? _engageBlockMessage(String serverMessage) {
    if (serverMessage.contains('subscription_inactive')) {
      return 'Подписка неактивна. Продлите её, чтобы принимать заказы.';
    }
    if (serverMessage.contains('executor_not_verified')) {
      return 'Аккаунт ещё не верифицирован — дождитесь проверки документов.';
    }
    if (serverMessage.contains('card_not_published')) {
      return 'Опубликуйте карточку исполнителя, чтобы принимать заказы.';
    }
    return null;
  }

  /// Отказаться от заказа, которого мы ждали подтверждать
  /// (`awaiting_executor` → `rejected_by_executor`).
  Future<void> declineMatch(String matchId) async {
    await _client
        .from('order_matches')
        .update(<String, dynamic>{'status': 'rejected_by_executor'})
        .eq('id', matchId)
        .select('id')
        .single();
  }

  /// Уже ли текущий исполнитель оставил отзыв на этот мэтч (subject =
  /// 'customer'). Локальный кэш `_reviewedOrders` сбрасывается при
  /// Hot Restart / переустановке, и без БД-проверки экран снова
  /// показывал кнопку «Оставить отзыв» — а INSERT ловился UNIQUE-индексом
  /// `reviews_unique_author_per_match_subject` (миграция
  /// `unique_review_per_author_match_subject`) с непонятной ошибкой.
  Future<bool> hasMyReviewOnMatch(String matchId) async {
    final User? user = _client.auth.currentUser;
    if (user == null) return false;
    final Map<String, dynamic>? r = await _client
        .from('reviews')
        .select('id')
        .eq('match_id', matchId)
        .eq('author_id', user.id)
        .eq('subject', 'customer')
        .maybeSingle();
    return r != null;
  }

  /// Свежий снапшот рейтинга/количества отзывов заказчика. Нужен после
  /// того, как исполнитель оставил отзыв заказчику и вернулся на
  /// экран деталей: триггер `recalculate_profile_rating` уже пересчитал
  /// `profiles.rating_as_customer` и `review_count_as_customer`, но
  /// открытый экран держит снапшот, полученный при изначальной загрузке.
  /// Возвращает `null`, если профиль не найден.
  Future<({double rating, int reviewCount})?> getCustomerRatingSnapshot(
      String customerId) async {
    final Map<String, dynamic>? r = await _client
        .from('profiles')
        .select('rating_as_customer, review_count_as_customer')
        .eq('id', customerId)
        .maybeSingle();
    if (r == null) return null;
    return (
      rating: _toDouble(r['rating_as_customer']) ?? 0,
      reviewCount: (r['review_count_as_customer'] as int?) ?? 0,
    );
  }

  /// Контакты заказчика (телефон/email) — доступны только после
  /// `accepted`/`completed`. Идёт через RPC `get_partner_contacts`, который
  /// на сервере проверяет, что вызывающий действительно партнёр по заказу,
  /// и отдаёт РОВНО phone+email (остальная приватная строка — токен карты,
  /// дата рождения, даты подписки — недоступна). Возвращает `null` без доступа.
  Future<({String? phone, String? email})?> getCustomerContacts(
      String customerId) async {
    try {
      final List<dynamic> rows = await _client.rpc(
        'get_partner_contacts',
        params: <String, dynamic>{
          'target_ids': <String>[customerId],
        },
      ) as List<dynamic>;
      if (rows.isEmpty) return null;
      final Map<String, dynamic> row = rows.first as Map<String, dynamic>;
      return (
        phone: row['phone'] as String?,
        email: row['email'] as String?,
      );
    } on PostgrestException {
      return null;
    }
  }

  /// Bulk-вариант — один RPC на список customerId вместо отдельного запроса
  /// на каждого. Раньше «Мои заказы» исполнителя делал 20 параллельных
  /// запросов для 20 заказов; теперь — один. Сервер сам отфильтрует тех,
  /// с кем у текущего пользователя нет подтверждённого заказа.
  Future<Map<String, ({String? phone, String? email})>>
      getCustomerContactsBulk(Iterable<String> customerIds) async {
    final List<String> ids = customerIds.toSet().toList();
    if (ids.isEmpty) return <String, ({String? phone, String? email})>{};
    try {
      final List<dynamic> rows = await _client.rpc(
        'get_partner_contacts',
        params: <String, dynamic>{'target_ids': ids},
      ) as List<dynamic>;
      return <String, ({String? phone, String? email})>{
        for (final dynamic r in rows)
          (r as Map<String, dynamic>)['id'] as String: (
            phone: r['phone'] as String?,
            email: r['email'] as String?,
          ),
      };
    } on PostgrestException {
      return <String, ({String? phone, String? email})>{};
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
    final List<CategoryRef> catCache =
        CatalogService.instance.cachedCategories ?? const <CategoryRef>[];
    final Map<int, String> categoryById = <int, String>{
      for (final CategoryRef c in catCache) c.id: c.title,
    };
    final List<int> machineryIds =
        List<int>.from((order['machinery_ids'] as List?) ?? const <dynamic>[]);
    final List<String> machineryTitles = machineryIds
        .map((int id) => machineryById[id] ?? '')
        .where((String t) => t.isNotEmpty)
        .toList();
    final List<int> categoryIds =
        List<int>.from((order['category_ids'] as List?) ?? const <dynamic>[]);
    final List<String> categoryTitles = categoryIds
        .map((int id) => categoryById[id] ?? '')
        .where((String t) => t.isNotEmpty)
        .toList();

    // `orders.works` — jsonb-массив `{name, volume?, unit?}`. На UI
    // нужен набор строк типа «Выемка грунта — 40 м³». Юниты в БД
    // ASCII-формат (`m`/`m2`/`m3`); рендерим в кириллицу.
    final List<dynamic> worksRaw =
        (order['works'] as List<dynamic>?) ?? const <dynamic>[];
    final List<String> works = worksRaw
        .whereType<Map<String, dynamic>>()
        .map(_formatWorkLine)
        .where((String s) => s.isNotEmpty)
        .toList();

    final List<String> photos = ((order['photos'] as List?) ?? const <dynamic>[])
        .whereType<String>()
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

    // `published_at` может быть NULL только у заказов в `draft` — но
    // мэтча на черновик быть не может (RLS не отдаст), поэтому в реальной
    // выборке поле всегда заполнено. Для безопасности fallback'имся на
    // `created_at` мэтча, чтобы UI не упал на DateTime.parse(null).
    final String? publishedAtRaw = order['published_at'] as String?;
    final DateTime publishedAt = publishedAtRaw != null
        ? DateTime.parse(publishedAtRaw)
        : DateTime.parse(r['created_at'] as String).toLocal();

    return MyOrderMatch(
      matchId: r['id'] as String,
      orderId: r['order_id'] as String,
      orderDisplayNumber: order['display_number'] as int,
      status: MyMatchStatus.fromDb(r['status'] as String),
      createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      statusChangedAt: DateTime.parse(
        // status_changed_at — приоритетный таймстемп смены статуса.
        // updated_at — fallback для строк, обработанных до миграции
        // `subscription_audit_fixes` (значения совпадают, потому что
        // backfill в миграции их выровнял).
        (r['status_changed_at'] ?? r['updated_at']) as String,
      ),
      orderPublishedAt: publishedAt,
      agreedPricePerHour: _toDouble(r['agreed_price_per_hour']),
      agreedPricePerDay: _toDouble(r['agreed_price_per_day']),
      agreedMinHours: r['agreed_min_hours'] as int?,
      orderTitle: order['title'] as String,
      orderAddress: order['address'] as String,
      orderDateFrom: DateTime.parse(order['date_from'] as String).toLocal(),
      orderDateTo: order['date_to'] == null
          ? null
          : DateTime.parse(order['date_to'] as String).toLocal(),
      orderTimeFrom: order['time_from'] as String?,
      orderTimeTo: order['time_to'] as String?,
      orderExactDate: order['exact_date'] as bool,
      orderWholeDay: order['whole_day'] as bool,
      orderMachineryTitles: machineryTitles,
      orderCategoryTitles: categoryTitles,
      orderDescription: (order['description'] as String?) ?? '',
      orderWorks: works,
      orderPhotos: photos,
      serviceMachineryTitle: serviceMachineryTitle,
      customerId: customer['id'] as String,
      customerName: (customer['name'] as String?) ?? 'Пользователь',
      customerAvatarUrl: customer['avatar_url'] as String?,
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

  /// Один элемент `orders.works` → строка для UI. Совместим с
  /// аналогичной функцией в `customer_orders_service.dart` у заказчика.
  static String _formatWorkLine(Map<String, dynamic> w) {
    final String name = (w['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return '';
    // volume хранится как string maxLength=10 после миграции
    // `orders_works_volume_text_with_dimensions` (юзер вводит «40»
    // или «10x30x5»). Старые записи могли быть числовыми — поддерживаем оба.
    final dynamic vRaw = w['volume'];
    final String? volStr = vRaw is String
        ? (vRaw.isEmpty ? null : vRaw)
        : vRaw is num
            ? (vRaw == vRaw.toInt() ? vRaw.toInt().toString() : vRaw.toString())
            : null;
    final String? unit = w['unit'] as String?;
    if (volStr == null) return name;
    final String unitUi = switch (unit) {
      'm' => 'м',
      'm2' => 'м²',
      'm3' => 'м³',
      _ => '',
    };
    return '$name — $volStr $unitUi'.trim();
  }
}

// DTO для справочников и сущностей каталога. Имена полей совпадают с
// колонками PostgreSQL, преобразование из `Map<String, dynamic>` живёт в
// фабриках `fromRow`.

/// Сводка моей активной услуги для отклика на заказ. У одного исполнителя
/// может быть несколько услуг с одной и той же техникой (разные тарифы),
/// поэтому отклик — по конкретной услуге, а не по технике.
class MyActiveService {
  const MyActiveService({
    required this.id,
    required this.title,
    required this.machineryTitle,
    required this.pricePerHour,
    required this.pricePerDay,
    required this.minHours,
  });
  final String id;
  final String title;
  final String machineryTitle;
  final double? pricePerHour;
  final double? pricePerDay;
  final int? minHours;
}

class MachineryRef {
  const MachineryRef({required this.id, required this.title});
  final int id;
  final String title;

  factory MachineryRef.fromRow(Map<String, dynamic> r) => MachineryRef(
        id: r['id'] as int,
        title: r['title'] as String,
      );
}

class CategoryRef {
  const CategoryRef({required this.id, required this.title});
  final int id;
  final String title;

  factory CategoryRef.fromRow(Map<String, dynamic> r) => CategoryRef(
        id: r['id'] as int,
        title: r['title'] as String,
      );
}

/// Мини-профиль заказчика для карточек ленты.
class CustomerSummary {
  const CustomerSummary({
    required this.id,
    required this.name,
    required this.ratingAsCustomer,
    required this.reviewCountAsCustomer,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final double ratingAsCustomer;
  final int reviewCountAsCustomer;

  factory CustomerSummary.fromRow(Map<String, dynamic> r) => CustomerSummary(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? 'Пользователь',
        avatarUrl: r['avatar_url'] as String?,
        ratingAsCustomer: _num(r['rating_as_customer']),
        reviewCountAsCustomer: (r['review_count_as_customer'] as int?) ?? 0,
      );
}

/// Запись заказа для списка. Названия техники уже разрезолвлены
/// в сервисе, UI их просто показывает.
class OrderListItem {
  const OrderListItem({
    required this.id,
    required this.displayNumber,
    required this.title,
    required this.address,
    this.latitude,
    this.longitude,
    required this.dateFrom,
    required this.dateTo,
    required this.timeFrom,
    required this.timeTo,
    required this.exactDate,
    required this.wholeDay,
    required this.machineryTitles,
    required this.publishedAt,
    required this.customer,
  });

  final String id;
  final int displayNumber;
  final String title;
  final String address;
  /// Координаты адреса заказа из DaData (заполняются при создании заказа
  /// в приложении заказчика). null для старых заказов, созданных до
  /// подключения DaData — на карте такие маркеры разлетаются по
  /// детерминированному моку (см. `mockMoscowCoordsForId`).
  final double? latitude;
  final double? longitude;
  final DateTime dateFrom;
  final DateTime? dateTo;
  final String? timeFrom;
  final String? timeTo;
  final bool exactDate;
  final bool wholeDay;
  final List<String> machineryTitles;
  final DateTime publishedAt;
  final CustomerSummary customer;
}

/// Один элемент спецификации работ заказа (например, "Выемка грунта: 40 м³").
/// Хранится в `orders.works` как jsonb-массив; схема фиксируется в БД
/// (CHECK с `jsonb_matches_schema`): `{name, volume(number), unit(m|m2|m3)}`.
class WorkItem {
  const WorkItem({required this.name, this.volume, this.unit});
  final String name;
  /// Свободный текст до 10 символов: «22», «30», «10x30x5» и т.п.
  /// До миграции жил как `double?`; для legacy-данных fromJson
  /// сконвертирует число в строку.
  final String? volume;
  final String? unit; // 'm' / 'm2' / 'm3'

  factory WorkItem.fromJson(Map<String, dynamic> j) {
    final dynamic v = j['volume'];
    final String? volStr = v is String
        ? v
        : v is num
            ? (v == v.truncateToDouble() ? v.toInt().toString() : v.toString())
            : null;
    return WorkItem(
      name: (j['name'] as String?) ?? '',
      volume: volStr,
      unit: j['unit'] as String?,
    );
  }
}

/// Полные детали одного заказа.
class OrderDetail {
  const OrderDetail({
    required this.id,
    required this.displayNumber,
    required this.title,
    required this.description,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.dateFrom,
    required this.dateTo,
    required this.timeFrom,
    required this.timeTo,
    required this.exactDate,
    required this.wholeDay,
    required this.machineryTitles,
    required this.categoryTitles,
    required this.works,
    required this.photos,
    required this.publishedAt,
    required this.customer,
  });

  final String id;
  final int displayNumber;
  final String title;
  final String? description;
  final String address;
  final double? latitude;
  final double? longitude;
  final DateTime dateFrom;
  final DateTime? dateTo;
  final String? timeFrom;
  final String? timeTo;
  final bool exactDate;
  final bool wholeDay;
  final List<String> machineryTitles;
  final List<String> categoryTitles;
  final List<WorkItem> works;
  final List<String> photos;
  final DateTime publishedAt;
  final CustomerSummary customer;
}

/// Публичный профиль заказчика + его юридический статус (для карточки).
class CustomerProfile {
  const CustomerProfile({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.legalStatus,
    required this.ratingAsCustomer,
    required this.reviewCountAsCustomer,
    required this.about,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String? legalStatus; // individual / self_employed / ip / legal_entity
  final double ratingAsCustomer;
  final int reviewCountAsCustomer;
  final String? about;

  factory CustomerProfile.fromRow(Map<String, dynamic> r) => CustomerProfile(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? 'Пользователь',
        avatarUrl: r['avatar_url'] as String?,
        legalStatus: r['legal_status'] as String?,
        ratingAsCustomer: _num(r['rating_as_customer']),
        reviewCountAsCustomer: (r['review_count_as_customer'] as int?) ?? 0,
        about: r['about'] as String?,
      );
}

/// Запись каталога исполнителей (видит заказчик при поиске).
/// Для каждой публичной карточки в `executor_cards` плюс данные из
/// `profiles` и aggregate по `services` (техника/категории/мин. цена).
class ExecutorCardListItem {
  const ExecutorCardListItem({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.ratingAsExecutor,
    required this.reviewCountAsExecutor,
    required this.legalStatus,
    required this.experienceYears,
    required this.about,
    required this.locationAddress,
    required this.radiusKm,
    required this.machineryTitles,
    required this.categoryTitles,
    required this.minPricePerHour,
    required this.minPricePerDay,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final double ratingAsExecutor;
  final int reviewCountAsExecutor;
  final String? legalStatus;
  final int? experienceYears;
  /// `profiles.about` исполнителя — короткий рассказ о себе для карточки
  /// в каталоге. У dispetcher это поле уже было; в claude его не было,
  /// и при попытке отобразить «о себе» получали пусто.
  final String? about;
  final String? locationAddress;
  final int? radiusKm;
  final List<String> machineryTitles;
  final List<String> categoryTitles;
  final double? minPricePerHour;
  final double? minPricePerDay;
}

/// Один отзыв для отображения на карточке заказчика/исполнителя.
class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.rating,
    required this.text,
    required this.authorName,
    required this.createdAt,
  });

  final String id;
  final int rating;
  final String? text;
  final String authorName;
  final DateTime createdAt;

  factory ReviewItem.fromRow(Map<String, dynamic> r) {
    final dynamic authorRaw = r['author'];
    final String authorName = authorRaw is Map<String, dynamic>
        ? (authorRaw['name'] as String?) ?? 'Пользователь'
        : 'Пользователь';
    return ReviewItem(
      id: r['id'] as String,
      rating: r['rating'] as int,
      text: r['text'] as String?,
      authorName: authorName,
      createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    );
  }
}

double _num(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

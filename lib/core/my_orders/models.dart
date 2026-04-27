// DTO для "Моих заказов" исполнителя. Источник — `order_matches` JOIN
// `orders` + `profiles` (заказчик). Статусы БД отображаются на enum UI.

enum MyMatchStatus {
  /// Мы откликнулись, ждём ответа заказчика.
  awaitingCustomer,

  /// Заказчик принял, ждёт нашего финального подтверждения.
  awaitingExecutor,

  /// Обе стороны согласились — мэтч активен.
  accepted,

  /// Работа выполнена.
  completed,

  /// Заказчик отклонил наш отклик.
  rejectedByCustomer,

  /// Мы сами отказались (до accept).
  rejectedByExecutor,

  /// Истёк срок / заказ снят.
  expired;

  bool get isActive =>
      this == awaitingCustomer ||
      this == awaitingExecutor ||
      this == accepted;

  bool get isDone => this == completed;

  bool get isRejected =>
      this == rejectedByCustomer ||
      this == rejectedByExecutor ||
      this == expired;

  static MyMatchStatus fromDb(String code) => switch (code) {
        'awaiting_customer' => awaitingCustomer,
        'awaiting_executor' => awaitingExecutor,
        'accepted' => accepted,
        'completed' => completed,
        'rejected_by_customer' => rejectedByCustomer,
        'rejected_by_executor' => rejectedByExecutor,
        'expired' => expired,
        _ => rejectedByExecutor, // fallback, не должно случаться
      };
}

/// Один отклик исполнителя, обогащённый данными заказа и заказчика.
class MyOrderMatch {
  const MyOrderMatch({
    required this.matchId,
    required this.orderId,
    required this.orderDisplayNumber,
    required this.status,
    required this.createdAt,
    required this.agreedPricePerHour,
    required this.agreedPricePerDay,
    required this.agreedMinHours,
    // Поля заказа:
    required this.orderTitle,
    required this.orderAddress,
    required this.orderDateFrom,
    required this.orderDateTo,
    required this.orderTimeFrom,
    required this.orderTimeTo,
    required this.orderExactDate,
    required this.orderWholeDay,
    required this.orderMachineryTitles,
    required this.orderCategoryTitles,
    required this.orderDescription,
    required this.orderWorks,
    required this.orderPhotos,
    required this.serviceMachineryTitle,
    // Заказчик:
    required this.customerId,
    required this.customerName,
    required this.customerRating,
    required this.customerReviewCount,
  });

  final String matchId;
  final String orderId;

  /// `orders.display_number` — числовой человеко-читаемый номер,
  /// который заказчик видит в своих заказах. Показывается одинаково
  /// у обеих сторон, чтобы можно было ссылаться на «заказ №00012345».
  final int orderDisplayNumber;

  final MyMatchStatus status;
  final DateTime createdAt;
  final double? agreedPricePerHour;
  final double? agreedPricePerDay;
  final int? agreedMinHours;

  final String orderTitle;
  final String orderAddress;
  final DateTime orderDateFrom;
  final DateTime? orderDateTo;
  final String? orderTimeFrom;
  final String? orderTimeTo;
  final bool orderExactDate;
  final bool orderWholeDay;
  final List<String> orderMachineryTitles;

  /// Категории услуг заказа (резолвлены title из `categories`). Нужны
  /// в деталях, чтобы исполнитель видел вид работ (например,
  /// «Земляные работы», «Демонтаж»).
  final List<String> orderCategoryTitles;

  /// Текстовое описание заказа из формы заказчика. Пустое — блок
  /// в деталях не показывается.
  final String orderDescription;

  /// Спецификация работ заказа (`orders.works` jsonb-массив):
  /// строки уже отформатированы для UI («Выемка грунта — 40 м³»).
  final List<String> orderWorks;

  /// URL фото заказа из storage. Пустой — блок «Фото» скрыт.
  final List<String> orderPhotos;

  /// Техника услуги, по которой шёл отклик. Одна на мэтч (правило
  /// «1 услуга = 1 техника»). Используется как подпись к блоку «Цена»
  /// на экране деталей. `null`, если услугу удалили.
  final String? serviceMachineryTitle;

  final String customerId;
  final String customerName;
  final double customerRating;
  final int customerReviewCount;
}

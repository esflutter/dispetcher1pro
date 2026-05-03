/// Сохранённая карта пользователя (источник — `saved_payment_methods`,
/// заполняется webhook'ом `yookassa-webhook` при `payment.succeeded` с
/// флагом `save_payment_method=true`). Удалить карту через API
/// YooKassa нельзя — мы помечаем у себя `is_active=false`.
class SavedCard {
  const SavedCard({
    required this.id,
    required this.kind,
    required this.last4,
    required this.brand,
    required this.expiryMonth,
    required this.expiryYear,
    required this.title,
  });

  /// `payment_method_id` из YooKassa. Передаётся обратно в
  /// `yookassa-create-payment` для повторного списания.
  final String id;

  /// Тип сохранённого метода: `bank_card`, `yoo_money` (кошелёк),
  /// `sberbank` (СберПэй) и т.п. — копия `payment_method.type` YooKassa.
  /// Для `bank_card` есть `last4`/`brand`; для `yoo_money` их нет —
  /// кошелёк идентифицируется только хвостом номера счёта в `title`.
  final String? kind;

  final String? last4;
  final String? brand;
  final String? expiryMonth;
  final String? expiryYear;
  final String? title;

  bool get isBankCard => kind == 'bank_card' || (last4 != null && last4!.isNotEmpty);
  bool get isYooMoney => kind == 'yoo_money';

  /// Хвост идентификатора метода — для карт это `card_last4`, для
  /// YooMoney-кошелька берём последние 4 цифры из `title`
  /// («YooMoney wallet 410011758831136» → «1136»). Если ничего
  /// нет — fallback `••••`, чтобы UI не падал.
  String get displayLast4 {
    if (last4 != null && last4!.isNotEmpty) return last4!;
    if (isYooMoney && title != null) {
      final RegExpMatch? m = RegExp(r'(\d{4})\D*$').firstMatch(title!);
      if (m != null) return m.group(1)!;
    }
    return '••••';
  }

  String get displayExpiry =>
      (expiryMonth != null && expiryYear != null)
          ? '$expiryMonth/${expiryYear!.length >= 2 ? expiryYear!.substring(expiryYear!.length - 2) : expiryYear}'
          : '';

  /// Карта истекла — не сработает при оплате/авто-продлении.
  /// `expiry_year` хранится как строка («2024»/«24» — оба варианта).
  /// Сравниваем с текущим (год, месяц): карта истекла если
  /// `(year, month) < now.(year, month)`. Пустые поля → не истекла
  /// (для yoo_money и подобных, где expiry не имеет смысла).
  bool get isExpired {
    if (expiryMonth == null || expiryYear == null) return false;
    final int? mo = int.tryParse(expiryMonth!);
    final int? yrRaw = int.tryParse(expiryYear!);
    if (mo == null || yrRaw == null) return false;
    final int yr = yrRaw < 100 ? 2000 + yrRaw : yrRaw;
    final DateTime now = DateTime.now();
    if (yr < now.year) return true;
    if (yr > now.year) return false;
    return mo < now.month;
  }

  factory SavedCard.fromRow(Map<String, dynamic> r) => SavedCard(
        id: r['id'] as String,
        kind: r['kind'] as String?,
        last4: r['card_last4'] as String?,
        brand: r['card_brand'] as String?,
        expiryMonth: r['card_expiry_month'] as String?,
        expiryYear: r['card_expiry_year'] as String?,
        title: r['title'] as String?,
      );
}

/// Тип покупки. Совпадает с `payments.kind` в БД и с полем `kind` в
/// `yookassa-create-payment`.
enum PaymentKind {
  /// Подписка исполнителя на 30 дней (490 ₽).
  subscription,

  /// Оплата публикации одной услуги (99 ₽).
  serviceSlot,

  /// Привязка карты — техническая транзакция на 1 ₽ с обязательным
  /// `save_payment_method=true`. Webhook сразу делает рефанд той же
  /// суммы, юзер по факту ничего не платит, но получает привязанную
  /// карту в `saved_payment_methods` для будущих оплат без редиректа.
  cardBinding,
}

extension PaymentKindCode on PaymentKind {
  String get code {
    switch (this) {
      case PaymentKind.subscription:
        return 'subscription';
      case PaymentKind.serviceSlot:
        return 'service_slot';
      case PaymentKind.cardBinding:
        return 'card_binding';
    }
  }
}

/// Результат вызова `yookassa-create-payment`.
class PaymentCreateResult {
  const PaymentCreateResult({
    required this.paymentId,
    required this.yookassaPaymentId,
    required this.status,
    required this.confirmationUrl,
    required this.amount,
  });

  /// UUID нашей записи в `payments`. Используется для поллинга статуса.
  final String paymentId;
  final String yookassaPaymentId;

  /// `pending` (ждём webhook), `succeeded` (мгновенно списано с
  /// сохранённой карты), `canceled` (отказано сразу).
  final String status;

  /// URL формы оплаты YooKassa. `null` если списание прошло мгновенно
  /// сохранённой картой и редирект не нужен.
  final String? confirmationUrl;

  final int amount;

  bool get needsRedirect => confirmationUrl != null;
  bool get isAlreadySucceeded => status == 'succeeded';

  /// YooKassa возвращает `canceled`. Наш бэкенд маппит это в `failed`
  /// перед записью в БД (там check-constraint), но в API ответа функция
  /// прокидывает оригинальное значение.
  bool get isFailed => status == 'canceled' || status == 'failed';
}

/// Терминальный статус платежа после поллинга. Совпадает с
/// допустимыми значениями `payments.status` в БД (constraint:
/// pending/succeeded/failed/refunded).
enum PaymentStatus {
  pending,
  succeeded,
  failed,
  refunded,
  unknown,
}

extension PaymentStatusFromString on String {
  PaymentStatus toPaymentStatus() {
    switch (this) {
      case 'pending':
        return PaymentStatus.pending;
      case 'succeeded':
        return PaymentStatus.succeeded;
      case 'failed':
      case 'canceled': // YooKassa-нативный статус — на всякий случай
        return PaymentStatus.failed;
      case 'refunded':
        return PaymentStatus.refunded;
      default:
        return PaymentStatus.unknown;
    }
  }
}

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/payments/models.dart';

/// Таймаут на одиночный вызов YooKassa Edge Function. На реальной сети
/// функция возвращает ответ за 1-3 сек; 20 сек — потолок при медленном
/// мобильном инете. Без таймаута зависшая функция замораживала кнопку
/// «Оплатить» на минуту+, и пользователь успевал закрыть приложение.
const Duration _kPaymentTimeout = Duration(seconds: 20);

/// Клиент для платёжных Edge Functions YooKassa.
///
/// Все методы требуют активной Supabase-сессии (анон-юзеру оплаты не
/// разрешены). Авторизация прокидывается через `supabase_flutter`,
/// который сам добавляет `Authorization: Bearer <user JWT>` к
/// `client.functions.invoke(...)`.
class PaymentService {
  PaymentService._();
  static final PaymentService instance = PaymentService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Создать платёж в YooKassa.
  ///
  /// - [kind] — `subscription` или `serviceSlot`.
  /// - [serviceId] — обязателен для `serviceSlot` (иначе функция вернёт
  ///   400 «service_id required»).
  /// - [paymentMethodId] — если передан, списание идёт с уже сохранённой
  ///   карты без редиректа (мгновенно или с 3DS-челленджем).
  /// - [saveCard] — если `true`, при успешной оплате карта сохранится в
  ///   `saved_payment_methods`. Игнорируется если `paymentMethodId`.
  /// - [returnUrl] — куда вернёт YooKassa после оплаты. Передаём наш
  ///   deep-link или web-страницу-заглушку.
  Future<PaymentCreateResult> createPayment({
    required PaymentKind kind,
    String? serviceId,
    String? paymentMethodId,
    bool saveCard = false,
    String? returnUrl,
    bool activateTrial = false,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'kind': kind.code,
      'service_id': ?serviceId,
      'payment_method_id': ?paymentMethodId,
      if (saveCard) 'save_card': true,
      'return_url': ?returnUrl,
      // Edge Function активирует подписку (paid_until=now+30d, trial_used,
      // auto_renew, payment_method_id) в webhook'е после succeeded —
      // ТОЛЬКО при kind='card_binding'. Для других kind флаг
      // игнорируется на сервере. См. supabase/functions/yookassa-webhook
      // (activateTrial).
      if (activateTrial) 'activate_trial': true,
    };

    final FunctionResponse resp = await _client.functions
        .invoke(
          'yookassa-create-payment',
          body: body,
        )
        .timeout(_kPaymentTimeout, onTimeout: () {
      throw const PaymentError(
        'timeout',
        'Платёжный сервис не отвечает. Проверьте интернет и попробуйте снова.',
      );
    });
    final dynamic data = resp.data;
    if (data is! Map) {
      throw const PaymentError('bad_response',
          'Не удалось разобрать ответ сервера оплаты');
    }
    if (data['error'] != null) {
      throw PaymentError('server', (data['error'] as Object?).toString());
    }
    // Defensive cast: при 5xx Edge Function может вернуть Map без ключей
    // payment_id/yookassa_payment_id/amount (например, ответ от прокси
    // вместо самой функции). Без `as String?` здесь упадём NoSuchMethodError
    // мимо catch-блоков UI и пользователь увидит generic-ошибку без
    // понятного сообщения.
    final String? paymentId = data['payment_id'] as String?;
    final String? yookassaId = data['yookassa_payment_id'] as String?;
    final num? amount = data['amount'] as num?;
    if (paymentId == null || yookassaId == null || amount == null) {
      throw const PaymentError('bad_response',
          'Платёжный сервис вернул некорректный ответ. Попробуйте снова.');
    }
    return PaymentCreateResult(
      paymentId: paymentId,
      yookassaPaymentId: yookassaId,
      status: (data['status'] as String?) ?? 'pending',
      confirmationUrl: data['confirmation_url'] as String?,
      amount: amount.toInt(),
    );
  }

  /// Список активных сохранённых карт текущего юзера.
  Future<List<SavedCard>> listCards() async {
    final FunctionResponse resp = await _client.functions
        .invoke(
          'yookassa-list-cards',
          method: HttpMethod.get,
        )
        .timeout(_kPaymentTimeout, onTimeout: () {
      throw const PaymentError(
        'timeout',
        'Сервис платежей недоступен. Попробуйте позже.',
      );
    });
    final dynamic data = resp.data;
    if (data is! Map) return const <SavedCard>[];
    final List<dynamic>? rows = data['cards'] as List<dynamic>?;
    if (rows == null) return const <SavedCard>[];
    return rows
        .map((dynamic r) => SavedCard.fromRow(r as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// «Удалить» сохранённую карту — помечает у нас `is_active=false`.
  Future<void> deleteCard(String paymentMethodId) async {
    final FunctionResponse resp = await _client.functions
        .invoke(
          'yookassa-delete-card',
          body: <String, dynamic>{'payment_method_id': paymentMethodId},
        )
        .timeout(_kPaymentTimeout, onTimeout: () {
      throw const PaymentError(
        'timeout',
        'Не удалось удалить карту: сервис платежей не отвечает.',
      );
    });
    final dynamic data = resp.data;
    if (data is Map && data['error'] != null) {
      throw PaymentError('server', (data['error'] as Object?).toString());
    }
  }

  /// Был ли у текущего юзера хотя бы один успешный платёж (включая
  /// уже зарефанженные — например, технические `card_binding` 1 ₽).
  /// Используется в `SubscriptionScreen`, чтобы показывать кнопку
  /// «Способы оплаты» не только когда есть привязанные карты, но и
  /// когда юзер хоть раз оплачивал что-то платное (логично давать ему
  /// доступ в раздел управления способами оплаты, даже если карты
  /// сейчас отвязаны).
  Future<bool> hasAnySucceededPayment() async {
    final User? user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('payments')
          .select('id')
          .eq('user_id', user.id)
          .inFilter('status', const <String>['succeeded', 'refunded'])
          .limit(1);
      return rows.isNotEmpty;
    } on PostgrestException {
      return false;
    }
  }

  /// Прочитать актуальный статус платежа из нашей БД (RLS пропускает
  /// SELECT по `user_id = auth.uid()`).
  Future<PaymentStatus> getPaymentStatus(String paymentId) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('payments')
          .select('status')
          .eq('id', paymentId)
          .maybeSingle();
      if (row == null) return PaymentStatus.unknown;
      return ((row['status'] as String?) ?? '').toPaymentStatus();
    } on PostgrestException {
      return PaymentStatus.unknown;
    }
  }

  /// Поллинг статуса платежа до терминального состояния. Используется
  /// на экране результата оплаты после возврата из браузера.
  ///
  /// Резолвится:
  ///   - `succeeded` / `canceled` — финал
  ///   - `pending` после `timeout` — статус не успел дойти до нас,
  ///     показываем «в обработке», результат уточнится на следующем
  ///     заходе на экран подписки.
  Future<PaymentStatus> pollPaymentStatus(
    String paymentId, {
    Duration interval = const Duration(milliseconds: 1500),
    Duration timeout = const Duration(seconds: 90),
    bool Function()? isCancelled,
  }) async {
    // Пустой id пробивает PostgREST как `id=eq.` → 22P02 invalid uuid,
    // `getPaymentStatus` ловит и возвращает unknown — без этой ветки цикл
    // молотил бы 90 с впустую (deep-link без id, ошибка маршрута).
    if (paymentId.isEmpty) return PaymentStatus.unknown;
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      // Чтобы цикл прерывался при unmount экрана PaymentResultScreen
      // (раньше после ухода с экрана продолжали слать ~50 запросов).
      if (isCancelled != null && isCancelled()) return PaymentStatus.pending;
      final PaymentStatus s = await getPaymentStatus(paymentId);
      if (s == PaymentStatus.succeeded ||
          s == PaymentStatus.failed ||
          s == PaymentStatus.refunded) {
        return s;
      }
      await Future<void>.delayed(interval);
    }
    return PaymentStatus.pending;
  }
}

/// Ошибки уровня PaymentService — в UI обычно показываем `message`,
/// `code` для логов/аналитики.
class PaymentError implements Exception {
  const PaymentError(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'PaymentError($code): $message';
}

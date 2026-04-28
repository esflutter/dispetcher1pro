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
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'kind': kind.code,
      'service_id': ?serviceId,
      'payment_method_id': ?paymentMethodId,
      if (saveCard) 'save_card': true,
      'return_url': ?returnUrl,
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
    return PaymentCreateResult(
      paymentId: data['payment_id'] as String,
      yookassaPaymentId: data['yookassa_payment_id'] as String,
      status: (data['status'] as String?) ?? 'pending',
      confirmationUrl: data['confirmation_url'] as String?,
      amount: (data['amount'] as num).toInt(),
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
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
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

import 'package:flutter_test/flutter_test.dart';
import 'package:dispatcher_1/core/payments/models.dart';

/// Маппинг строкового статуса платежа из БД и кода PaymentKind на
/// строку для серверной Edge Function `yookassa-create-payment`.
/// Эти контракты завязаны с серверным кодом — расхождение немедленно
/// ломает оплату.

void main() {
  group('PaymentStatusFromString.toPaymentStatus', () {
    test('известные статусы', () {
      expect('pending'.toPaymentStatus(), PaymentStatus.pending);
      expect('succeeded'.toPaymentStatus(), PaymentStatus.succeeded);
      expect('failed'.toPaymentStatus(), PaymentStatus.failed);
      expect('refunded'.toPaymentStatus(), PaymentStatus.refunded);
    });

    test('canceled (YooKassa-нативный) → failed', () {
      // YooKassa отдаёт `canceled`, наш бэк маппит в `failed` перед БД,
      // но если строка прилетит как есть — клиент тоже должен понять.
      expect('canceled'.toPaymentStatus(), PaymentStatus.failed);
    });

    test('неизвестная строка → unknown', () {
      expect(''.toPaymentStatus(), PaymentStatus.unknown);
      expect('something_else'.toPaymentStatus(), PaymentStatus.unknown);
    });

    test('case-sensitive (Supabase возвращает строго lowercase)', () {
      expect('Succeeded'.toPaymentStatus(), PaymentStatus.unknown);
      expect('SUCCEEDED'.toPaymentStatus(), PaymentStatus.unknown);
    });
  });

  group('PaymentKindCode.code', () {
    test('все три варианта матчат серверный контракт', () {
      // Сервер ждёт ровно эти строки (см. enum kind в edge function).
      expect(PaymentKind.subscription.code, 'subscription');
      expect(PaymentKind.serviceSlot.code, 'service_slot');
      expect(PaymentKind.cardBinding.code, 'card_binding');
    });
  });
}

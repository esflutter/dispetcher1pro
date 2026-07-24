import 'package:flutter_test/flutter_test.dart';

import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/payments/payment_rules.dart';

void main() {
  group('payment price gate', () {
    test('subscription and service cannot be paid without a displayed price',
        () {
      expect(
        isPaymentPriceReady(
          kind: PaymentKind.subscription,
          amount: null,
          activateTrial: false,
          renewalAmount: null,
        ),
        isFalse,
      );
      expect(
        isPaymentPriceReady(
          kind: PaymentKind.serviceSlot,
          amount: null,
          activateTrial: false,
          renewalAmount: null,
        ),
        isFalse,
      );
    });

    test('trial requires its future renewal amount', () {
      expect(
        isPaymentPriceReady(
          kind: PaymentKind.cardBinding,
          amount: 1,
          activateTrial: true,
          renewalAmount: null,
        ),
        isFalse,
      );
      expect(
        isPaymentPriceReady(
          kind: PaymentKind.cardBinding,
          amount: 1,
          activateTrial: true,
          renewalAmount: 490,
        ),
        isTrue,
      );
    });
  });

  group('card saving', () {
    test('one-time service does not save a new card by default', () {
      expect(
        shouldSaveNewCard(
          kind: PaymentKind.serviceSlot,
          hasSelectedSavedCard: false,
          activateTrial: false,
          saveServiceCard: false,
        ),
        isFalse,
      );
    });

    test('explicit service choice, binding and subscription save the card', () {
      expect(
        shouldSaveNewCard(
          kind: PaymentKind.serviceSlot,
          hasSelectedSavedCard: false,
          activateTrial: false,
          saveServiceCard: true,
        ),
        isTrue,
      );
      expect(
        shouldSaveNewCard(
          kind: PaymentKind.cardBinding,
          hasSelectedSavedCard: false,
          activateTrial: false,
          saveServiceCard: false,
        ),
        isTrue,
      );
      expect(
        shouldSaveNewCard(
          kind: PaymentKind.subscription,
          hasSelectedSavedCard: false,
          activateTrial: false,
          saveServiceCard: false,
        ),
        isTrue,
      );
    });

    test('an already saved card is never saved again', () {
      expect(
        shouldSaveNewCard(
          kind: PaymentKind.subscription,
          hasSelectedSavedCard: true,
          activateTrial: false,
          saveServiceCard: false,
        ),
        isFalse,
      );
    });
  });
}

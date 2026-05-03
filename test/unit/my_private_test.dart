import 'package:flutter_test/flutter_test.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';

/// Unit-тесты для парсинга `MyPrivate.fromRow` и геттеров подписки.
///
/// Покрывают:
///   - корректный парсинг полей подписки (`paid_until`, `trial_until`,
///     `trial_used`, `auto_renew`, `payment_method_id`);
///   - граничные случаи (null-значения);
///   - геттеры `subscriptionActive` и `subscriptionInTrial`.

void main() {
  group('MyPrivate.fromRow', () {
    test('минимальный валидный объект (нет подписки)', () {
      final MyPrivate p = MyPrivate.fromRow(<String, dynamic>{
        'phone': '+71234567890',
        'email': null,
        'date_of_birth': null,
        'subscription_paid_until': null,
        'subscription_trial_until': null,
        'subscription_auto_renew': false,
        'subscription_trial_used': false,
        'subscription_payment_method_id': null,
        'verification_reject_reason': null,
      });
      expect(p.subscriptionPaidUntil, isNull);
      expect(p.subscriptionTrialUntil, isNull);
      expect(p.subscriptionTrialUsed, isFalse);
      expect(p.subscriptionAutoRenew, isFalse);
      expect(p.subscriptionPaymentMethodId, isNull);
      expect(p.subscriptionActive, isFalse);
      expect(p.subscriptionInTrial, isFalse);
    });

    test('активный триал', () {
      final DateTime future = DateTime.now().add(const Duration(days: 25));
      final MyPrivate p = MyPrivate.fromRow(<String, dynamic>{
        'phone': '+71234567890',
        'email': null,
        'date_of_birth': null,
        'subscription_paid_until': future.toIso8601String(),
        'subscription_trial_until': future.toIso8601String(),
        'subscription_auto_renew': true,
        'subscription_trial_used': true,
        'subscription_payment_method_id': 'pm-id',
        'verification_reject_reason': null,
      });
      expect(p.subscriptionActive, isTrue);
      expect(p.subscriptionInTrial, isTrue);
    });

    test('обычная подписка (триал кончился)', () {
      final DateTime past = DateTime.now().subtract(const Duration(days: 5));
      final DateTime future = DateTime.now().add(const Duration(days: 25));
      final MyPrivate p = MyPrivate.fromRow(<String, dynamic>{
        'phone': '+71234567890',
        'email': null,
        'date_of_birth': null,
        'subscription_paid_until': future.toIso8601String(),
        'subscription_trial_until': past.toIso8601String(),
        'subscription_auto_renew': true,
        'subscription_trial_used': true,
        'subscription_payment_method_id': 'pm-id',
        'verification_reject_reason': null,
      });
      expect(p.subscriptionActive, isTrue);
      // trial_until в прошлом — триал уже не активен, но подписка платная.
      expect(p.subscriptionInTrial, isFalse);
    });

    test('подписка истекла', () {
      final DateTime past = DateTime.now().subtract(const Duration(days: 1));
      final MyPrivate p = MyPrivate.fromRow(<String, dynamic>{
        'phone': '+71234567890',
        'email': null,
        'date_of_birth': null,
        'subscription_paid_until': past.toIso8601String(),
        'subscription_trial_until': past.toIso8601String(),
        'subscription_auto_renew': false,
        'subscription_trial_used': true,
        'subscription_payment_method_id': null,
        'verification_reject_reason': null,
      });
      expect(p.subscriptionActive, isFalse);
      expect(p.subscriptionInTrial, isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:dispatcher_1/core/settings/settings_service.dart';

void main() {
  group('payment price from settings', () {
    test('accepts positive whole rubles as number or string', () {
      expect(parsePaymentPriceRub(390), 390);
      expect(parsePaymentPriceRub(99.0), 99);
      expect(parsePaymentPriceRub('390'), 390);
      expect(parsePaymentPriceRub(' 99 '), 99);
    });

    test('never invents or rounds an unavailable/invalid price', () {
      expect(parsePaymentPriceRub(null), isNull);
      expect(parsePaymentPriceRub(''), isNull);
      expect(parsePaymentPriceRub('not-a-number'), isNull);
      expect(parsePaymentPriceRub(0), isNull);
      expect(parsePaymentPriceRub(-1), isNull);
      expect(parsePaymentPriceRub(390.5), isNull);
      expect(parsePaymentPriceRub(double.infinity), isNull);
    });
  });
}

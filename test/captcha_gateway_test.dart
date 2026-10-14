import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/auth/auth_service.dart';
import 'package:dispatcher_1/core/auth/captcha_service.dart';

void main() {
  test('русское сообщение сервера показывается как есть', () {
    expect(
      authErrorToRu(const AuthException('${ruMessagePrefix}Сейчас не удаётся отправить код. Попробуйте позже.')),
      'Сейчас не удаётся отправить код. Попробуйте позже.',
    );
  });

  test('обычные ошибки по-прежнему переводятся', () {
    expect(authErrorToRu(const AuthException('otp_device_daily_limit')),
        contains('слишком много кодов'));
  });

  test('страница капчи: невидимый режим, ключ клиента, канал сообщений', () {
    final String html = SmartCaptcha.html();
    expect(html, contains('invisible:true'));
    expect(html, contains("sitekey:'${SmartCaptcha.siteKey}'"));
    expect(html, contains('CaptchaChannel'));
    expect(html, contains('smartcaptcha.cloud.yandex.ru/captcha.js'));
    expect(SmartCaptcha.siteKey, startsWith('ysc1_'));
  });
}

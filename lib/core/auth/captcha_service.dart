import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Проверка «я не робот» (Yandex SmartCaptcha) перед запросом кода входа.
///
/// Зачем: 11.10.2026 СМС-бомбер слил баланс RedSMS через открытый запрос кода.
/// Пропуск от капчи одноразовый, проверяется на сервере (функция request-code)
/// ещё до отправки СМС. Почти всегда проверка невидимая: окно с заданием
/// появляется, только если Яндекс заподозрил робота.
///
/// Ключ клиента публичный (его видит любой сайт с капчей), секрета тут нет.
class SmartCaptcha {
  SmartCaptcha._();

  static const String siteKey = 'ysc1_cb1L8aI2XR7eO4iFAMhSYdkn8ux0SuHCZLxpBSZGe3dff6d5';

  /// Сайт из списка разрешённых в консоли Яндекса: окно проверки открывается
  /// как страница с этим адресом.
  static const String baseUrl = 'https://jokaynapesbem.beget.app/';

  /// Сколько ждём пропуск: слабый интернет не должен подвешивать вход.
  static const Duration timeout = Duration(seconds: 25);

  /// Подмена в тестах: возвращает готовый пропуск без окна.
  @visibleForTesting
  static Future<String?> Function(BuildContext context)? debugOverride;

  /// Возвращает пропуск или null, если проверку не удалось выполнить
  /// (нет сети, окно закрыто, превышено время).
  static Future<String?> solve(BuildContext context) async {
    final Future<String?> Function(BuildContext)? override = debugOverride;
    if (override != null) return override(context);
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      useRootNavigator: true,
      builder: (BuildContext ctx) => const _CaptchaDialog(),
    );
  }

  /// Страница с невидимой капчей. Сообщения в приложение:
  /// token — пропуск; visible/hidden — показать/спрятать задание;
  /// error — проверка не загрузилась.
  @visibleForTesting
  static String html() => '''
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;background:transparent}#c{display:flex;justify-content:center}</style>
<script src="https://smartcaptcha.cloud.yandex.ru/captcha.js?render=onload&onload=onCaptchaLoad" defer></script>
</head><body><div id="c"></div><script>
function post(t,v){ try{ CaptchaChannel.postMessage(JSON.stringify({t:t,v:v||""})); }catch(e){} }
window.onCaptchaLoad=function(){
  try{
    var id=window.smartCaptcha.render('c',{sitekey:'$siteKey',invisible:true,hideShield:true,
      callback:function(tok){post('token',tok);}});
    window.smartCaptcha.subscribe(id,'challenge-visible',function(){post('visible');});
    window.smartCaptcha.subscribe(id,'challenge-hidden',function(){post('hidden');});
    window.smartCaptcha.subscribe(id,'network-error',function(){post('error');});
    window.smartCaptcha.subscribe(id,'javascript-error',function(){post('error');});
    window.smartCaptcha.execute(id);
  }catch(e){post('error');}
};
</script></body></html>''';
}

class _CaptchaDialog extends StatefulWidget {
  const _CaptchaDialog();

  @override
  State<_CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<_CaptchaDialog> {
  late final WebViewController _controller;
  Timer? _timer;
  bool _challengeVisible = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('CaptchaChannel', onMessageReceived: _onMessage)
      ..loadHtmlString(SmartCaptcha.html(), baseUrl: SmartCaptcha.baseUrl);
    _timer = Timer(SmartCaptcha.timeout, () => _finish(null));
  }

  void _onMessage(JavaScriptMessage message) {
    try {
      final Map<String, dynamic> m =
          jsonDecode(message.message) as Map<String, dynamic>;
      switch (m['t']) {
        case 'token':
          final String token = (m['v'] as String?) ?? '';
          _finish(token.isEmpty ? null : token);
        case 'visible':
          // Человеку нужно решить задание — даём больше времени.
          _timer?.cancel();
          _timer = Timer(const Duration(minutes: 3), () => _finish(null));
          if (mounted) setState(() => _challengeVisible = true);
        case 'hidden':
          if (mounted) setState(() => _challengeVisible = false);
        case 'error':
          _finish(null);
      }
    } catch (_) {
      _finish(null);
    }
  }

  void _finish(String? token) {
    if (_done || !mounted) return;
    _done = true;
    _timer?.cancel();
    Navigator.of(context, rootNavigator: true).pop(token);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Окно с браузером должно иметь размер, иначе проверка не запустится:
    // пока задания нет, держим его крошечным, а человеку показываем «Проверяем…».
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_challengeVisible) ...[
                const SizedBox(height: 8),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 12),
                const Text('Проверяем…', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: _challengeVisible ? double.infinity : 1,
                height: _challengeVisible ? 420 : 1,
                child: WebViewWidget(controller: _controller),
              ),
              if (_challengeVisible)
                TextButton(
                  onPressed: () => _finish(null),
                  child: const Text('Отмена'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'router.dart';

/// Сервис обработки deep links вида `dispatcher1pro://...`.
///
/// Сейчас единственный кейс — возврат из браузерной формы YooKassa:
/// `dispatcher1pro://payment/result?id=<paymentId>`. Когда юзер
/// нажимает «Вернуться на сайт» в YooKassa, браузер видит
/// зарегистрированную custom-схему и передаёт URL ОС, та запускает
/// MainActivity (Android) / открывает приложение (iOS), а пакет
/// `app_links` поднимает этот URL в Flutter — здесь мы переводим его
/// в роут go_router'а.
///
/// Обрабатываются ДВА источника:
///   1. Initial link — когда приложение было закрыто и его открыли
///      переходом по ссылке (вызываем `getInitialLink()` один раз
///      после старта).
///   2. Stream — когда приложение уже было в фоне (юзер вернулся из
///      браузера в существующую сессию приложения).
class DeepLinks {
  DeepLinks._();
  static final DeepLinks instance = DeepLinks._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  /// Подключаемся к стриму ссылок и обрабатываем initial-ссылку.
  /// Безопасно вызывать несколько раз — повторные вызовы no-op.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Начальная ссылка (приложение открылось переходом по ссылке).
    try {
      final Uri? initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (e) {
      debugPrint('[DeepLinks] getInitialLink error: $e');
    }

    // Подписка на runtime-ссылки (приложение было в фоне).
    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) => debugPrint('[DeepLinks] stream error: $e'),
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  void _handle(Uri uri) {
    debugPrint('[DeepLinks] got: $uri');
    // Принимаем только нашу схему — игнорируем чужое.
    if (uri.scheme != 'dispatcher1pro') return;

    // dispatcher1pro://payment/result?id=<uuid> или ?payment_id=<uuid>
    // (Edge Function `yookassa-create-payment` добавляет payment_id
    // автоматически к return_url; клиент локально использует id).
    // host = 'payment', pathSegments = ['result']
    if (uri.host == 'payment' && uri.pathSegments.contains('result')) {
      final String? paymentId =
          uri.queryParameters['id'] ?? uri.queryParameters['payment_id'];
      final String target = paymentId == null || paymentId.isEmpty
          ? '/subscription/payment/result'
          : '/subscription/payment/result?id=${Uri.encodeComponent(paymentId)}';
      // Используем глобальный appRouter — у нас на старте всегда уже
      // что-то отрисовано (splash/onboarding/shell), так что go() сработает.
      appRouter.go(target);
      return;
    }
  }
}

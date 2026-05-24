import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Ключ в SharedPreferences для последнего обработанного initial-link'а.
  /// На Android `getInitialLink()` возвращает один и тот же URL после
  /// каждого hot restart (Intent остаётся на Activity до его явной
  /// замены), поэтому без сравнения с прошлым значением экран статуса
  /// оплаты появлялся при каждом перезапуске приложения.
  static const String _kLastInitialKey = 'deep_links.last_initial';

  /// Подключаемся к стриму ссылок и обрабатываем initial-ссылку.
  /// Безопасно вызывать несколько раз — повторные вызовы no-op.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Начальная ссылка (приложение открылось переходом по ссылке).
    try {
      final Uri? initial = await _appLinks.getInitialLink();
      if (initial != null && await _shouldHandleInitial(initial)) {
        _handle(initial);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DeepLinks] getInitialLink error: $e');
      }
    }

    // Подписка на runtime-ссылки (приложение было в фоне). Стрим
    // эмитит ТОЛЬКО свежие интенты, поэтому здесь дедупликация не
    // нужна — каждый вызов `_handle` относится к новому переходу.
    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) {
        if (kDebugMode) debugPrint('[DeepLinks] stream error: $e');
      },
    );
  }

  /// Сравнивает initial-link с последним обработанным. Возвращает true,
  /// если ссылка новая (или storage недоступен — тогда лучше обработать,
  /// чем потерять реальный платёж). Сразу же запоминает текущую ссылку.
  Future<bool> _shouldHandleInitial(Uri uri) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String current = uri.toString();
      final String? last = prefs.getString(_kLastInitialKey);
      if (last == current) {
        if (kDebugMode) {
          debugPrint('[DeepLinks] skip duplicate initial: $current');
        }
        return false;
      }
      await prefs.setString(_kLastInitialKey, current);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[DeepLinks] prefs error: $e');
      return true;
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  void _handle(Uri uri) {
    if (kDebugMode) debugPrint('[DeepLinks] got: $uri');
    // Принимаем только нашу схему — игнорируем чужое.
    if (uri.scheme != 'dispatcher1pro') return;

    // dispatcher1pro://payment/result?id=<uuid> или ?payment_id=<uuid>.
    // Edge Function `payment-return` отдаёт HTML, который перекидывает
    // браузер на этот deep link — id может быть пустым, тогда мы
    // ищем последний `pending` платёж юзера сами (см. fallback ниже).
    if (uri.host == 'payment' && uri.pathSegments.contains('result')) {
      // Не блокируем `_handle`: ищем платёж в БД асинхронно, а пока
      // открываем экран результата с тем id, что есть.
      unawaited(_routeToResult(uri));
      return;
    }
  }

  /// Резолвит payment_id (из URL или последнего pending в БД) и
  /// делает `appRouter.go` на экран результата с нужными query-полями.
  Future<void> _routeToResult(Uri uri) async {
    String? paymentId =
        uri.queryParameters['id'] ?? uri.queryParameters['payment_id'];
    // Fallback: HTML-страница `payment-return` приходит БЕЗ id (YooKassa
    // не подставляет наш payment_id в return_url). Тянем последний
    // pending-платёж текущего юзера — RLS пропускает только записи
    // `user_id = auth.uid()`, чужой платёж сюда не попадёт.
    if (paymentId == null || paymentId.isEmpty) {
      paymentId = await _findLatestPendingPaymentId();
    }
    final String bindingTail =
        uri.queryParameters['binding'] == '1' ? '&binding=1' : '';
    final String? rp = uri.queryParameters['return'];
    final String returnTail = rp != null && rp.isNotEmpty
        ? '&return=${Uri.encodeComponent(rp)}'
        : '';
    final String target = paymentId == null || paymentId.isEmpty
        ? '/subscription/payment/result'
        : '/subscription/payment/result'
            '?id=${Uri.encodeComponent(paymentId)}$bindingTail$returnTail';
    appRouter.go(target);
  }

  Future<String?> _findLatestPendingPaymentId() async {
    try {
      final SupabaseClient client = Supabase.instance.client;
      final User? user = client.auth.currentUser;
      if (user == null) return null;
      // Окно 10 минут — гарантирует, что мы подхватим тот pending,
      // который юзер только что создал из приложения и пошёл оплачивать
      // в браузер. Старые «трупы» pending'ов от брошенных оплат
      // (например, юзер закрыл вкладку, не введя реквизиты) могут лежать
      // часами; без фильтра по времени fallback подхватывал такой pending
      // и polling висел бесконечно — этот платёж в YooKassa не активен,
      // webhook никогда не прилетит, status навсегда останется pending.
      final DateTime cutoff =
          DateTime.now().toUtc().subtract(const Duration(minutes: 10));
      final Map<String, dynamic>? row = await client
          .from('payments')
          .select('id')
          .eq('user_id', user.id)
          .eq('status', 'pending')
          .gte('created_at', cutoff.toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row == null ? null : row['id'] as String?;
    } catch (e) {
      if (kDebugMode) debugPrint('[DeepLinks] pending lookup error: $e');
      return null;
    }
  }
}

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Управление FCM-токеном текущего пользователя.
///
/// - После OTP-логина: запросить разрешение на пуши (Android 13+, iOS),
///   получить FCM-токен и записать в `device_tokens`.
/// - На `onTokenRefresh` — обновить запись.
/// - При logout — пометить токен как `invalidated_at` и удалить локально.
///
/// Защита от шторма параллельных вызовов:
/// - single-flight: одновременная регистрация ждёт первую.
/// - дедуп 5 минут: повторный вызов в этом окне — no-op.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _initialized = false;
  Future<void>? _inFlight;
  DateTime? _lastRegisteredAt;
  StreamSubscription<String>? _tokenRefreshSub;

  /// Подписаться на `onTokenRefresh` один раз при старте приложения,
  /// после `Firebase.initializeApp`. Любая ошибка `_upsertToken` гасится
  /// — токен подтянется на следующей попытке.
  void initTokenRefreshListener() {
    if (_initialized) return;
    _initialized = true;
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (String token) async {
        try {
          await _upsertToken(token);
        } catch (e) {
          if (kDebugMode) debugPrint('[push] tokenRefresh upsert failed: $e');
        }
      },
    );
  }

  /// Регистрация для текущего пользователя — после OTP-логина или при
  /// холодном старте с валидной сессией.
  Future<void> registerForCurrentUser() async {
    // Дедуп: повторный вызов в течение 5 мин — no-op.
    final DateTime? last = _lastRegisteredAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 5)) {
      return;
    }
    // Single-flight: если другая регистрация идёт — ждём её.
    final Future<void>? existing = _inFlight;
    if (existing != null) {
      await existing;
      return;
    }
    final Completer<void> done = Completer<void>();
    _inFlight = done.future;
    try {
      await _doRegister();
      _lastRegisteredAt = DateTime.now();
    } catch (e) {
      if (kDebugMode) debugPrint('[push] registerForCurrentUser failed: $e');
    } finally {
      _inFlight = null;
      done.complete();
    }
  }

  Future<void> _doRegister() async {
    final SupabaseClient sb = Supabase.instance.client;
    if (sb.auth.currentSession == null) return;

    // Запрос разрешения. Android 13+ покажет системный диалог; старые
    // версии Android — no-op (разрешение дано на установке).
    NotificationSettings? settings;
    try {
      settings = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true)
          // 60с: системный диалог разрешения читает ЧЕЛОВЕК — 5с обрывали
          // future до его ответа, и токен терялся до следующего запуска.
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      // На прошивках без сервисов Google запрос может зависнуть —
      // не блокируем флоу, просто прекращаем регистрацию.
      if (kDebugMode) debugPrint('[push] requestPermission failed: $e');
      return;
    }

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      // Юзер явно отказал. Не пишем токен — пуш всё равно не покажется.
      return;
    }

    // iOS: СНАЧАЛА дождаться APNs-токена. Если запросить FCM-токен раньше,
    // firebase_messaging бросает `apns-token-not-set`, исключение гасится
    // ниже — и токен не сохраняется НИКОГДА. Симптом ровно такой, какой был
    // на проде: в базе десятки android-токенов и ни одного ios.
    // APNs-токен выдаётся системой асинхронно после разрешения, поэтому
    // опрашиваем его несколько раз с короткой паузой; если так и не пришёл
    // (нет сети, симулятор, отозванный профиль) — выходим молча, попытка
    // повторится при следующем запуске и на onTokenRefresh.
    if (Platform.isIOS) {
      String? apns;
      for (int attempt = 0; attempt < 5 && apns == null; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        try {
          apns = await FirebaseMessaging.instance
              .getAPNSToken()
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          if (kDebugMode) debugPrint('[push] getAPNSToken failed: $e');
        }
      }
      if (apns == null) {
        if (kDebugMode) debugPrint('[push] APNs-токен не выдан — регистрацию отложили');
        return;
      }
    }

    // Получаем FCM-токен. Может зависнуть на устройствах без GMS —
    // ограничиваем 15 секундами.
    String? token;
    try {
      token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      if (kDebugMode) debugPrint('[push] getToken failed: $e');
      return;
    }
    if (token == null || token.isEmpty) return;

    await _upsertToken(token);
  }

  Future<void> _upsertToken(String token) async {
    final SupabaseClient sb = Supabase.instance.client;
    final String? userId = sb.auth.currentUser?.id;
    if (userId == null) return;

    // Upsert по UNIQUE(token). Если токен уже привязан к этому юзеру —
    // просто обновим last_seen_at. Если был у другого юзера на этом
    // устройстве — переключим на текущего и сбросим invalidated_at.
    await sb.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      // Платформу определяем по факту — на iPhone токен помечаем 'ios'.
      'platform': Platform.isIOS ? 'ios' : 'android',
      // Это приложение исполнителя — пуши с target_app='executor' идут сюда,
      // с target_app='customer' — отсекаются на сервере. Пуши без target_app
      // (отзывы, блокировка аккаунта) идут в оба.
      'app': 'executor',
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      'invalidated_at': null,
    }, onConflict: 'token');
  }

  /// При logout: пометить текущий токен этого устройства как `invalidated`,
  /// чтобы сервер не слал пуши предыдущему юзеру. Локально — удалить
  /// токен FCM, чтобы при следующем входе пришёл свежий.
  Future<void> clearForCurrentUser() async {
    _lastRegisteredAt = null;

    String? token;
    try {
      token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Если getToken не отвечает — переходим к удалению локально.
    }

    if (token != null && token.isNotEmpty) {
      try {
        final SupabaseClient sb = Supabase.instance.client;
        await sb
            .from('device_tokens')
            .update(<String, dynamic>{
              'invalidated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('token', token)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        if (kDebugMode) debugPrint('[push] clear (update) failed: $e');
      }
    }

    // Удалить локальный токен — следующий getToken вернёт новый.
    try {
      await FirebaseMessaging.instance
          .deleteToken()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Не критично — токен либо удалится, либо в любом случае
      // протухнет после inactivity-cron на сервере (90 дней).
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _initialized = false;
  }
}

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../router.dart';
import '../../features/shell/main_shell.dart';

/// Обработка пушей на клиенте.
///
/// Три сценария:
/// 1. Foreground (приложение открыто) — FCM SDK сам баннер не показывает.
///    Рисуем локальный через flutter_local_notifications.
/// 2. Background (свернуто, не убито) — FCM показывает в системной шторке,
///    тап вызывает `onMessageOpenedApp`. Маршрутизируем по `data.route`.
/// 3. Cold-start (приложение убито, юзер тапнул пуш) — `getInitialMessage`
///    возвращает RemoteMessage. Откладываем navigation на microtask, чтобы
///    GoRouter сначала отработал первичный redirect (splash → нужный экран).
class PushHandler {
  PushHandler._();
  static final PushHandler instance = PushHandler._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// ID канала на Android. Должен совпадать с тем, что мы создаём
  /// `createNotificationChannel` ниже. В payload FCM сервер канал не
  /// указывает — Android берёт default из манифеста (см. AndroidManifest).
  static const String _channelId = 'default';
  static const String _channelName = 'Уведомления';

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Канал на Android 8+: без него любой пуш (FCM или локальный) молча
    // отбрасывается. Создание идемпотентно — можно вызывать каждый старт.
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Основные уведомления приложения',
      importance: Importance.high,
      playSound: true,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Инициализация flutter_local_notifications. Иконка — launcher icon
    // приложения (она же сработает в статус-баре для пуша).
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    // Foreground пуши идут сюда. По умолчанию FCM SDK их НЕ показывает
    // как баннер — рисуем локальный с тем же payload.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Тап по пушу когда приложение в фоне (но не убито).
    FirebaseMessaging.onMessageOpenedApp.listen(_routeFromMessage);

    // Cold-start: приложение было убито, юзер тапнул пуш — он нас разбудил.
    final RemoteMessage? initial =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // Откладываем на microtask — иначе GoRouter затрёт наш push своим
      // первичным redirect-ом (splash → home/auth).
      scheduleMicrotask(() => _routeFromMessage(initial));
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final RemoteNotification? n = message.notification;
    if (n == null) return;

    // Стабильный id локального уведомления: при повторной доставке одного и
    // того же пуша FCM сохраняет messageId, поэтому второй баннер ПЕРЕЗАПИШЕТ
    // первый, а не появится дублем. message.hashCode давал каждому приходу
    // новый id → один пуш мог показаться двумя одинаковыми баннерами.
    final int localId =
        message.messageId?.hashCode ?? Object.hash(n.title, n.body);
    await _local.show(
      localId,
      n.title,
      n.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      // Payload передаём строкой (JSON) — другой формат не поддерживается.
      // При тапе по локальному баннеру попадём в _onLocalTap.
      payload: jsonEncode(message.data),
    );
  }

  void _routeFromMessage(RemoteMessage message) {
    final dynamic route = message.data['route'];
    if (route is String && route.isNotEmpty) {
      // Сервер кладёт готовый deep-link, например `/orders/<id>` или
      // `/profile/reviews`. Роутер сам разрулит:
      //   /orders/:id → OrderDetailRouteScreen → MyOrdersScreen откроет детали.
      //   /profile/reviews → ReviewsScreen.
      _safePush(route);
    }
  }

  void _onLocalTap(NotificationResponse resp) {
    final String? payload = resp.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final dynamic data = jsonDecode(payload);
      if (data is Map<String, dynamic>) {
        final dynamic route = data['route'];
        if (route is String && route.isNotEmpty) {
          _safePush(route);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[push] local tap parse failed: $e');
    }
  }

  void _safePush(String route) {
    try {
      // БЕЗ СЕССИИ (пуш остался в шторке после выхода / принудительного
      // разлогина) переход внутрь приложения давал пустые экраны и ложное
      // «не найдено» — выглядело как потеря аккаунта. Ведём на вход.
      if (Supabase.instance.client.auth.currentSession == null) {
        appRouter.go('/auth/phone');
        return;
      }
      // Корневые табы MainShell (/orders, /catalog, /profile) — это
      // НЕ отдельные экраны, а вкладки внутри shell. Если по пушу
      // делать appRouter.push('/orders'), GoRouter создаёт ВТОРУЮ
      // копию MyOrdersScreen ПОВЕРХ shell, без bottomNavigationBar,
      // с дефолтным Material back arrow вместо нашей вёрстки.
      // Поэтому такие маршруты переводим в переключение таба.
      //
      // Старые пуши до миграции 017 имели route='/orders' — этот
      // фолбэк закрывает их корректно.
      if (route == '/orders') {
        MainShell.selectedTab.value = 1;
        appRouter.go('/shell');
        return;
      }
      if (route == '/catalog') {
        MainShell.selectedTab.value = 0;
        appRouter.go('/shell');
        return;
      }
      if (route == '/profile') {
        MainShell.selectedTab.value = 2;
        appRouter.go('/shell');
        return;
      }
      // Пуш об истечении подписки кладёт route='/subscription', но в
      // роутере есть только конкретные подэкраны — ведём на управление
      // подпиской, иначе тап попадал в заглушку «ссылка устарела».
      if (route == '/subscription') {
        appRouter.push('/subscription/manage');
        return;
      }
      // Остальные маршруты (`/orders/<id>`, `/catalog/order/<id>`,
      // `/profile/reviews`, `/profile/notifications-settings` и т.п.)
      // открываются как полно-экранные с back-кнопкой.
      appRouter.push(route);
    } catch (e) {
      if (kDebugMode) debugPrint('[push] safePush failed for "$route": $e');
    }
  }
}

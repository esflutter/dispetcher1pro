import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../router.dart';
import '../profile/profile_service.dart';
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
  // v2: старый канал 'default' на части устройств застрял без звука (Android
  // фиксирует настройки канала при первом создании и не даёт их менять). Новый
  // id заставляет систему создать канал заново — с правильными звуком и важностью.
  static const String _channelId = 'default_v2';
  static const String _channelName = 'Уведомления';

  bool _initialized = false;

  /// Маршрут из пуша, которым было открыто УБИТОЕ приложение (cold start).
  /// НЕ навигируем по нему сразу: сплэш сначала доводит пользователя до
  /// базового экрана (`/shell`), а потом сам открывает этот маршрут поверх
  /// через [consumeColdStartRoute]. Иначе таймер сплэша (через 1.5 c делает
  /// безусловный `go('/shell')`) затирал только что открытый экран, и тап
  /// по пушу из шторки приземлял пользователя на главную вместо нужного
  /// экрана. `null` — обычный старт без пуша.
  static String? pendingColdStartRoute;

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
      enableVibration: true,
    );
    final AndroidFlutterLocalNotificationsPlugin? androidImpl =
        _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    // Удаляем старый беззвучный канал 'default' (его настройки уже не изменить),
    // затем создаём новый — со звуком и вибрацией.
    await androidImpl?.deleteNotificationChannel('default');
    await androidImpl?.createNotificationChannel(channel);

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
    // Сразу НЕ навигируем: запоминаем маршрут, его откроет сплэш поверх
    // уже установленного `/shell` (см. [pendingColdStartRoute]). Раньше
    // здесь был немедленный push через microtask — но сессия восстанавливается
    // ещё до первого кадра, push успевал лечь поверх сплэша, и таймер сплэша
    // через 1.5 c затирал его переходом на главную.
    final RemoteMessage? initial =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      final dynamic route = initial.data['route'];
      if (route is String && route.isNotEmpty) {
        pendingColdStartRoute = route;
      }
    }
  }

  /// Открывает отложенный cold-start маршрут поверх уже установленного
  /// базового экрана. Зовётся сплэшем сразу после `go('/shell')` — только
  /// когда есть валидная сессия и регистрация завершена. Сессия к этому
  /// моменту точно восстановлена, поэтому цикл ожидания внутри [_safePush]
  /// завершится на первой итерации.
  Future<void> consumeColdStartRoute() async {
    final String? route = pendingColdStartRoute;
    pendingColdStartRoute = null;
    if (route == null || route.isEmpty) return;
    await _safePush(route);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // Пуш о верификации/блокировке пришёл, пока приложение открыто (в т.ч.
    // когда пользователь стоит на экране профиля). Дёргаем «маячок» профиля,
    // чтобы статус («Верификация в процессе» → «Документы одобрены») обновился
    // живьём, без перезахода. Верификация/блокировка ведут на /profile или
    // /executor-card.
    final dynamic fgRoute = message.data['route'];
    if (fgRoute is String &&
        (fgRoute.startsWith('/profile') || fgRoute.startsWith('/executor-card'))) {
      ProfileService.changeBeacon.value++;
    }

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
      unawaited(_safePush(route));
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
          unawaited(_safePush(route));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[push] local tap parse failed: $e');
    }
  }

  Future<void> _safePush(String route) async {
    try {
      // Холодный старт от пуша: Supabase и сессия восстанавливаются
      // асинхронно, в первый момент сессии ещё нет — раньше из-за этого
      // залогиненного пользователя по тапу уводило на экран входа. Ждём
      // появления сессии до ~4с (терпим к ещё не готовому клиенту); и только
      // если её действительно нет (вышел / разлогинен) — ведём на вход.
      Session? session;
      for (int i = 0; i < 40; i++) {
        try {
          session = Supabase.instance.client.auth.currentSession;
        } catch (_) {
          session = null; // Supabase ещё не инициализирован
        }
        if (session != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (session == null) {
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

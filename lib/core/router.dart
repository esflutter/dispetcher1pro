import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/otp_verification_screen.dart';
import '../features/auth/phone_input_screen.dart';
import '../features/auth/registration_screen.dart';
import '../features/catalog/catalog_categories_screen.dart';
import '../features/catalog/catalog_filter_screen.dart';
import '../features/catalog/customer_card_screen.dart';
import '../features/catalog/no_internet_screen.dart';
import '../features/catalog/order_detail_screen.dart' as catalog_detail;
import '../features/catalog/order_feed_screen.dart';
import '../features/catalog/order_on_map_screen.dart';
import '../features/catalog/orders_map_screen.dart';
import '../features/executor_card/edit_executor_card_screen.dart';
import '../features/executor_card/executor_card_screen.dart';
import '../features/notifications/notifications_inbox_screen.dart';
import '../features/profile/notifications_settings_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/orders/my_orders_screen.dart';
import '../features/orders/order_detail_route_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/reviews_screen.dart';
import '../features/schedule/day_settings_screen.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/services/create_service_screen.dart';
import '../features/services/my_services_screen.dart';
import '../features/services/service_detail_screen.dart';
import '../features/shell/main_shell.dart';
import '../features/subscription/add_card_screen.dart';
import '../features/subscription/payment_result_screen.dart';
import '../features/subscription/subscription_manage_screen.dart';
import '../features/subscription/subscription_screen.dart';
import '../features/support/chat_screen.dart';
import '../features/support/support_home_screen.dart';

/// Главный роутер приложения «Диспетчер №1».
/// Иерархия:
///   /splash → /onboarding → /auth/* → /shell (MainShell с табами)
///   Внутренние страницы (executor-card, services, schedule, subscription, profile/edit и т.п.)
///   открываются поверх shell обычным push.
final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  // Когда приложение запускается холодным стартом по deep-link
  // `dispatcher1pro://...`, ОС передаёт URI как initial location в Flutter.
  // GoRouter получает его раньше, чем `DeepLinks._handle` успеет
  // переписать роут через `appRouter.go(...)` — без redirect юзер
  // упирается в errorBuilder с «Маршрут не найден». Здесь
  // переписываем такие URI в нормальные внутренние пути.
  redirect: (BuildContext context, GoRouterState state) {
    final String uriStr = state.uri.toString();
    if (!uriStr.startsWith('dispatcher1pro://')) return null;
    final Uri uri = Uri.parse(uriStr);
    if (uri.host == 'payment' && uri.pathSegments.contains('result')) {
      final String? paymentId =
          uri.queryParameters['id'] ?? uri.queryParameters['payment_id'];
      final String bindingTail =
          uri.queryParameters['binding'] == '1' ? '&binding=1' : '';
      // `return` — куда увести юзера после «Готово»/«Закрыть» на
      // экране результата (см. PaymentResultScreen.returnPath).
      // Прокидывается paywall'ом в return_url ЮКассы, а оттуда —
      // обратно в deep-link при возврате из браузера.
      final String? rp = uri.queryParameters['return'];
      final String returnTail =
          rp != null && rp.isNotEmpty ? '&return=${Uri.encodeComponent(rp)}' : '';
      if (paymentId == null || paymentId.isEmpty) {
        return '/subscription/payment/result';
      }
      return '/subscription/payment/result'
          '?id=${Uri.encodeComponent(paymentId)}$bindingTail$returnTail';
    }
    return null;
  },
  routes: <RouteBase>[
    GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),

    // Авторизация
    GoRoute(path: '/auth/phone', builder: (_, _) => const PhoneInputScreen()),
    GoRoute(path: '/auth/otp', builder: (_, _) => const OtpVerificationScreen()),
    GoRoute(path: '/auth/registration', builder: (_, _) => const RegistrationScreen()),

    // Главный shell с нижней навигацией
    GoRoute(path: '/shell', builder: (_, _) => const MainShell()),

    // Каталог
    GoRoute(path: '/catalog', builder: (_, _) => const CatalogCategoriesScreen()),
    GoRoute(
      path: '/catalog/feed/:categoryId',
      builder: (_, state) => OrderFeedScreen(
        categoryId: state.pathParameters['categoryId'] ?? '',
        categoryTitle: (state.extra as String?) ?? 'Категория',
      ),
    ),
    GoRoute(
      path: '/catalog/order/:id',
      builder: (_, state) => catalog_detail.OrderDetailScreen(
        orderId: state.pathParameters['id'] ?? '',
      ),
    ),
    GoRoute(path: '/catalog/filter', builder: (_, _) => const CatalogFilterScreen()),
    GoRoute(
      path: '/catalog/customer/:id',
      builder: (_, state) => CustomerCardScreen(
        customerId: state.pathParameters['id'] ?? '',
      ),
    ),
    GoRoute(
      path: '/catalog/orders-map',
      builder: (_, _) => const OrdersMapFullScreen(),
    ),
    GoRoute(
      path: '/catalog/order/:id/map',
      builder: (_, state) => OrderOnMapScreen(
        orderId: state.pathParameters['id'] ?? '',
      ),
    ),
    GoRoute(path: '/catalog/no-internet', builder: (_, _) => const NoInternetScreen()),

    // Заказы исполнителя
    GoRoute(path: '/orders', builder: (_, _) => const MyOrdersScreen()),
    // Deep-link от пуша на конкретный заказ — обёртка кладёт id в
    // pendingOrderDeepLink, переключает таб «Мои заказы» и MyOrdersScreen
    // сам открывает детали через свою привычную логику.
    GoRoute(
      path: '/orders/:id',
      builder: (_, GoRouterState state) => OrderDetailRouteScreen(
        orderId: state.pathParameters['id'] ?? '',
      ),
    ),

    // Профиль
    GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
    GoRoute(path: '/profile/edit', builder: (_, _) => const EditProfileScreen()),
    GoRoute(path: '/profile/reviews', builder: (_, _) => const ReviewsScreen()),
    GoRoute(
      path: '/profile/notifications-settings',
      builder: (_, _) => const NotificationsSettingsScreen(),
    ),

    // Inbox уведомлений
    GoRoute(
      path: '/notifications',
      builder: (_, _) => const NotificationsInboxScreen(),
    ),

    // Карточка исполнителя
    GoRoute(path: '/executor-card', builder: (_, _) => const ExecutorCardScreen()),
    GoRoute(path: '/executor-card/edit', builder: (_, _) => const EditExecutorCardScreen()),

    // Мои услуги
    GoRoute(path: '/services', builder: (_, _) => const MyServicesScreen()),
    GoRoute(
      path: '/services/create',
      builder: (_, state) {
        // Из чата ассистента в extra может прилететь готовый черновик —
        // тогда форма открывается уже заполненной (см. handoff в chat_bubble).
        final extra = state.extra;
        final draft = (extra is Map && extra['ai_draft'] is Map<String, dynamic>)
            ? extra['ai_draft'] as Map<String, dynamic>
            : null;
        return CreateServiceScreen(aiDraft: draft);
      },
    ),
    GoRoute(
      path: '/services/:id',
      builder: (_, state) =>
          ServiceDetailScreen(serviceId: state.pathParameters['id'] ?? ''),
    ),
    GoRoute(
      path: '/services/:id/edit',
      builder: (_, state) =>
          CreateServiceScreen(serviceId: state.pathParameters['id']),
    ),

    // Мой график
    GoRoute(path: '/schedule', builder: (_, _) => const ScheduleScreen()),
    GoRoute(
      path: '/schedule/day',
      builder: (_, state) {
        final extra = state.extra as Map<String, Object?>?;
        return DaySettingsScreen(
          dayLabel: (extra?['dayLabel'] as String?) ?? 'Сегодня',
          initialState:
              (extra?['initialState'] as DayState?) ?? DayState.noOrders,
          initial:
              (extra?['initial'] as DaySettings?) ?? const DaySettings(),
        );
      },
    ),

    // Подписка
    GoRoute(path: '/subscription', builder: (_, _) => const SubscriptionScreen()),
    GoRoute(
      path: '/subscription/manage',
      builder: (_, _) => const SubscriptionManageScreen(),
    ),
    GoRoute(path: '/subscription/cards', builder: (_, _) => const CardsScreen()),
    // Роут `/subscription/payment` удалён: выбор способа оплаты теперь
    // живёт внутри paywall'ов (Subscription/ExecutorCard/Service) как
    // шторка, которая едет поверх маркетинговой карточки. Сами paywall'ы
    // открываются из вызывающих экранов через `Navigator.push(MaterialPageRoute(...))`.
    GoRoute(
      path: '/subscription/payment/result',
      builder: (_, GoRouterState state) {
        final String paymentId = state.uri.queryParameters['id'] ?? '';
        final bool binding =
            state.uri.queryParameters['binding'] == '1';
        final String? returnPath = state.uri.queryParameters['return'];
        return PaymentResultScreen(
          paymentId: paymentId,
          binding: binding,
          returnPath: (returnPath == null || returnPath.isEmpty)
              ? null
              : returnPath,
        );
      },
    ),

    // ИИ-ассистент (бывшая «поддержка» — унифицировано под /assistant*)
    GoRoute(path: '/assistant', builder: (_, _) => const SupportHomeScreen()),
    GoRoute(
      path: '/assistant/chat',
      builder: (context, state) {
        final extra = state.extra;
        String? initial;
        if (extra is Map && extra['initial'] is String) {
          initial = extra['initial'] as String;
        }
        return ChatScreen(initialMessage: initial);
      },
    ),
  ],
  errorBuilder: (context, state) {
    // Фолбэк: если ОС передала `dispatcher1pro://...` deep-link как
    // initial location, а top-level redirect его почему-то пропустил
    // (бывало с holodным стартом на Android), ловим здесь и сразу
    // же на следующем кадре уводим на правильный внутренний путь —
    // юзер видит спиннер вместо «Маршрут не найден» и тут же экран
    // результата оплаты.
    final Uri uri = state.uri;
    if (uri.scheme == 'dispatcher1pro' &&
        uri.host == 'payment' &&
        uri.pathSegments.contains('result')) {
      final String? paymentId =
          uri.queryParameters['id'] ?? uri.queryParameters['payment_id'];
      final String bindingTail =
          uri.queryParameters['binding'] == '1' ? '&binding=1' : '';
      final String? rp = uri.queryParameters['return'];
      final String returnTail =
          rp != null && rp.isNotEmpty ? '&return=${Uri.encodeComponent(rp)}' : '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (paymentId != null && paymentId.isNotEmpty) {
          appRouter.go(
            '/subscription/payment/result'
            '?id=${Uri.encodeComponent(paymentId)}$bindingTail$returnTail',
          );
        } else {
          appRouter.go('/subscription/payment/result');
        }
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // Фолбэк для любого другого неизвестного route (например, тап по
    // старому пушу с устаревшей структурой `/orders/<id>` на APK, где
    // этот маршрут ещё не зарегистрирован). Показываем понятный экран
    // с кнопкой «На главный», а не сырое «Маршрут не найден».
    return _RouteNotFoundScreen(uri: state.uri);
  },
);

class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen({required this.uri});
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF333333),
        foregroundColor: Colors.white,
        title: const Text('Ссылка устарела'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.link_off, size: 64, color: Color(0xFF999999)),
            const SizedBox(height: 16),
            const Text(
              'Эта ссылка из старой версии приложения',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Откройте «Уведомления» в приложении — там можно увидеть свежие события и перейти к нужному заказу.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF666666)),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9900),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14),
              ),
              onPressed: () => appRouter.go('/shell'),
              child: const Text('На главный'),
            ),
          ],
        ),
      ),
    );
  }
}

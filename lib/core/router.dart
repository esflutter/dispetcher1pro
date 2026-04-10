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
import '../features/executor_card/verification_documents_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/orders/my_orders_screen.dart';
import '../features/orders/order_detail_screen.dart' as my_order_detail;
import '../features/orders/review_screen.dart';
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
import '../features/subscription/payment_screen.dart';
import '../features/subscription/subscription_screen.dart';
import '../features/subscription/tariffs_screen.dart';
import '../features/support/chat_screen.dart';
import '../features/support/support_home_screen.dart';

/// Главный роутер приложения «Диспетчер №1».
/// Иерархия:
///   /splash → /onboarding → /auth/* → /shell (MainShell с табами)
///   Внутренние страницы (executor-card, services, schedule, subscription, profile/edit и т.п.)
///   открываются поверх shell обычным push.
final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
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
    GoRoute(
      path: '/orders/:id',
      builder: (_, state) => my_order_detail.MyOrderDetailScreen(
        state: (state.extra as my_order_detail.MyOrderDetailState?) ??
            my_order_detail.MyOrderDetailState.waiting,
      ),
    ),
    GoRoute(
      path: '/orders/:id/review',
      builder: (_, _) => const ReviewScreen(),
    ),

    // Профиль
    GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
    GoRoute(path: '/profile/edit', builder: (_, _) => const EditProfileScreen()),
    GoRoute(path: '/profile/reviews', builder: (_, _) => const ReviewsScreen()),

    // Карточка исполнителя
    GoRoute(path: '/executor-card', builder: (_, _) => const ExecutorCardScreen()),
    GoRoute(path: '/executor-card/edit', builder: (_, _) => const EditExecutorCardScreen()),
    GoRoute(
      path: '/executor-card/verification',
      builder: (_, _) => const VerificationDocumentsScreen(),
    ),

    // Мои услуги
    GoRoute(path: '/services', builder: (_, _) => const MyServicesScreen()),
    GoRoute(path: '/services/create', builder: (_, _) => const CreateServiceScreen()),
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
        );
      },
    ),

    // Подписка
    GoRoute(path: '/subscription', builder: (_, _) => const SubscriptionScreen()),
    GoRoute(path: '/subscription/tariffs', builder: (_, _) => const TariffsScreen()),
    GoRoute(path: '/subscription/card', builder: (_, _) => const AddCardScreen()),
    GoRoute(path: '/subscription/payment', builder: (_, _) => const PaymentScreen()),
    GoRoute(
      path: '/subscription/payment/result',
      builder: (_, _) => const PaymentResultScreen(),
    ),

    // Поддержка
    GoRoute(path: '/support', builder: (_, _) => const SupportHomeScreen()),
    GoRoute(path: '/support/chat', builder: (_, _) => const ChatScreen()),
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
  errorBuilder: (context, state) => Scaffold(
    body: Center(child: Text('Маршрут не найден: ${state.uri}')),
  ),
);

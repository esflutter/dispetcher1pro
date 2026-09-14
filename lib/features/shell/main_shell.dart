import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/ai/ai_navigation.dart';
import 'package:dispatcher_1/core/auth/guest_gate.dart';
import 'package:dispatcher_1/features/profile/account_block.dart';
import 'package:dispatcher_1/core/network_status.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/update/update_checker.dart';
import 'package:dispatcher_1/core/theme/system_bar_style.dart';
import 'package:dispatcher_1/core/widgets/no_internet_view.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/catalog_categories_screen.dart';
import 'package:dispatcher_1/features/executor_card/executor_card_screen.dart';
import 'package:dispatcher_1/features/orders/my_orders_screen.dart';
import 'package:dispatcher_1/features/profile/profile_screen.dart';
import 'package:dispatcher_1/features/schedule/widgets/schedule_alerts.dart';
import 'package:dispatcher_1/features/shell/widgets/main_bottom_nav_bar.dart';
import 'package:dispatcher_1/features/shell/widgets/support_fab.dart';

/// Главный shell приложения. Нижняя навигация на 3 таба
/// (Каталог / Заказы / Профиль) + плавающая оранжевая кнопка
/// поддержки в правом нижнем углу — как в Figma.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Глобальный способ переключить нижний таб изнутри экранов,
  /// запушенных поверх MainShell (например, из `OrderFeedScreen`,
  /// где нижняя панель — это «фейковая» копия shell'овской).
  /// Достаточно выставить нужный индекс и сделать
  /// `Navigator.popUntil(isFirst)`, чтобы вернуться к shell.
  static final ValueNotifier<int> selectedTab = ValueNotifier<int>(0);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // Гость видит стартовый экран создания профиля; живые заказы и аккаунтные
  // разделы открываются после входа. После входа приложение
  // заходит во ВНОВЬ созданный MainShell (isGuest=false), поэтому фиксируем
  // флаг один раз при создании.
  late final bool _guest = isGuest;
  late final List<Widget> _screens = <Widget>[
    const CatalogCategoriesScreen(),
    _guest
        ? const GuestLockedView(
            title: 'Сначала создайте профиль',
            subtitle:
                'Заполните профиль исполнителя, чтобы открыть каталог заказов и откликаться.',
            icon: Icons.assignment_outlined,
            intent: GuestAuthIntent.createProfile,
          )
        : MyOrdersScreen(onGoToCatalog: () => MainShell.selectedTab.value = 0),
    _guest
        ? const GuestLockedView(
            title: 'Войдите в аккаунт',
            subtitle: 'Профиль, услуги и график доступны после входа.',
            icon: Icons.person_outline,
          )
        : const ProfileScreen(),
  ];

  Timer? _blockExpiryTimer;

  @override
  void initState() {
    super.initState();
    MainShell.selectedTab.addListener(_onTabChanged);
    // Авто-снятие просроченной блокировки по рейтингу. `isBlocked` —
    // чистый getter, поэтому срок проверяем здесь раз в минуту (вне build),
    // иначе истечение блока во время отрисовки экрана роняло «setState
    // during build».
    AccountBlock.tickExpiry();
    _blockExpiryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => AccountBlock.tickExpiry(),
    );
    // Первый реальный экран после сплэша — здесь один раз за запуск
    // проверяем, не пора ли обновиться (тихо, если сеть/настройка недоступны).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      UpdateChecker.maybePromptOnce(context);
      // Разовый попап «Заполните график работы»: shell пересоздаётся после
      // успешной привязки карты (активации триала), сигнал pending поднят
      // экраном результата оплаты. В остальные запуски это no-op.
      ScheduleAlerts.maybeShowFillSchedulePrompt(context);
    });
  }

  @override
  void dispose() {
    _blockExpiryTimer?.cancel();
    MainShell.selectedTab.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  void _openSupport() {
    // Ассистент доступен гостю для общих вопросов. Поиск заказов и создание
    // профиля внутри чата гейтятся на вход отдельно (см. chat_screen.dart).
    // Стартовый экран ассистента показывается только один раз после
    // регистрации; по FAB всегда открываем чат напрямую.
    openAssistantChat(context);
  }

  @override
  Widget build(BuildContext context) {
    final int index = MainShell.selectedTab.value;
    // Под shell нав-бар закрашивается AppColors.navBarDark и тянется до
    // системных кнопок навигации. Через AnnotatedRegion сообщаем Android-у
    // что фон тёмный — чтобы Xiaomi/MIUI красила свои 3-button иконки
    // белыми (на тёмном фоне чёрные иконки сливались). Вне shell
    // (splash, OTP, регистрация) остаётся глобальный белый стиль.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dispatcherSystemBarStyle(
        navBarColor: AppColors.navBarDark,
        navIconBrightness: Brightness.light,
        // Шапка каталога — тёмный Container (не AppBar), стиль статус-бара
        // на этой вкладке берётся отсюда. Иконки часов/батареи — светлые.
        statusIconBrightness: Brightness.light,
      ),
      child: _buildScaffold(index),
    );
  }

  Widget _buildScaffold(int index) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: NetworkStatus.instance,
        builder: (BuildContext context, _) {
          if (NetworkStatus.instance.isOffline) {
            return NoInternetView(
              onRetry: () => NetworkStatus.instance.recheck(),
            );
          }
          return IndexedStack(index: index, children: _screens);
        },
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 24.h),
        child: SupportFab(onTap: _openSupport),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: MainBottomNavBar(
        items: _guest ? kGuestMainNavItems : kMainNavItems,
        currentIndex: index,
        onTap: (int i) => MainShell.selectedTab.value = i,
      ),
    );
  }
}

/// Зарегистрированный исполнитель получает доступ к заказам только после того,
/// как создал карточку. ValueListenableBuilder открывает каталог сразу после
/// сохранения — без перезапуска приложения.
class _ExecutorCatalogGate extends StatelessWidget {
  const _ExecutorCatalogGate();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ExecutorCardState.notifier,
    builder: (BuildContext context, bool cardCreated, _) {
      if (cardCreated) return const CatalogCategoriesScreen();
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 64.r,
                height: 64.r,
                decoration: const BoxDecoration(
                  color: AppColors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_add_alt_1_rounded,
                  color: AppColors.primary,
                  size: 32.r,
                ),
              ),
              SizedBox(height: 18.h),
              Text(
                'Сначала создайте профиль',
                textAlign: TextAlign.center,
                style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8.h),
              Text(
                'Так заказчики увидят вашу технику, а вы получите доступ к подходящим заказам.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              SizedBox(height: 22.h),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Создать профиль',
                  onPressed: () => context.push('/executor-card/edit'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

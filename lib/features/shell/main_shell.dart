import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/network_status.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/no_internet_view.dart';
import 'package:dispatcher_1/features/catalog/catalog_categories_screen.dart';
import 'package:dispatcher_1/features/orders/my_orders_screen.dart';
import 'package:dispatcher_1/features/profile/profile_screen.dart';
import 'package:dispatcher_1/features/shell/widgets/main_bottom_nav_bar.dart';
import 'package:dispatcher_1/features/shell/widgets/support_fab.dart';

/// Главный shell приложения. Нижняя навигация на 3 таба
/// (Каталог / Заказы / Профиль) + плавающая оранжевая кнопка
/// поддержки в правом нижнем углу — как в Figma.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const List<Widget> _screens = <Widget>[
    CatalogCategoriesScreen(),
    MyOrdersScreen(),
    ProfileScreen(),
  ];

  void _openSupport() {
    // Стартовый экран ассистента («С чего хотите начать?») показывается
    // только один раз — сразу после регистрации (см. registration_screen.dart).
    // По FAB всегда открываем чат напрямую.
    context.push('/assistant/chat');
  }

  @override
  Widget build(BuildContext context) {
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
          return IndexedStack(index: _index, children: _screens);
        },
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 24.h),
        child: SupportFab(onTap: _openSupport),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: MainBottomNavBar(
        items: kMainNavItems,
        currentIndex: _index,
        onTap: (int i) => setState(() => _index = i),
      ),
    );
  }
}


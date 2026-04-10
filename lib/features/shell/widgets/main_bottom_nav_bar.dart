import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';

/// Элемент нижней навигации (иконка + подпись).
class MainNavItem {
  const MainNavItem(this.label, this.iconAsset);
  final String label;
  final String iconAsset;
}

/// Канонические 3 таба приложения (Каталог / Заказы / Профиль).
const List<MainNavItem> kMainNavItems = <MainNavItem>[
  MainNavItem('Каталог', 'assets/icons/nav/catalog.svg'),
  MainNavItem('Заказы', 'assets/icons/nav/orders.svg'),
  MainNavItem('Профиль', 'assets/icons/nav/profile.svg'),
];

/// Тёмный нижний навбар из `MainShell`. Вынесен в отдельный виджет,
/// чтобы вложенные экраны (например, «Лента заказов») могли показать
/// точно такой же навбар поверх собственного Scaffold.
class MainBottomNavBar extends StatelessWidget {
  const MainBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<MainNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 64.h + bottomInset,
      decoration: const BoxDecoration(
        color: AppColors.navBarDark,
      ),
      padding: EdgeInsets.only(top: 6.h, bottom: bottomInset),
      child: Row(
        children: List<Widget>.generate(items.length, (int i) {
          final MainNavItem it = items[i];
          final bool active = i == currentIndex;
          final Color color =
              active ? AppColors.primary : AppColors.textTertiary;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  SvgPicture.asset(
                    it.iconAsset,
                    width: 24.r,
                    height: 24.r,
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    it.label,
                    style: AppTextStyles.tabActive.copyWith(color: color),
                  ),
                  SizedBox(height: 4.h),
                  Container(
                    width: 44.w,
                    height: 3.h,
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(1.5.r),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

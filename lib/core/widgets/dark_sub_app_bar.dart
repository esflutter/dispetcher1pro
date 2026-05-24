import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/system_bar_style.dart';

/// Канонический тёмный AppBar вложенных экранов (те, что пушатся поверх
/// MainShell). Совпадает с паттерном из `orders/order_detail_screen.dart`
/// и `catalog/order_detail_screen.dart`: высота 48, белая стрелка
/// `back_arrow.webp`, центрованный белый заголовок `titleS`.
class DarkSubAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DarkSubAppBar({
    super.key,
    required this.title,
    this.actions,
  });

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => Size.fromHeight(48.h);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.navBarDark,
      foregroundColor: Colors.white,
      // У тёмного AppBar нужны светлые иконки в статус-баре, иначе
      // время и батарея сливаются с navBarDark. AppBar.systemOverlayStyle
      // перекрывает глобальный стиль на тех экранах, где он рисуется.
      systemOverlayStyle: dispatcherSystemBarStyle(
        navBarColor: AppColors.background,
        statusIconBrightness: Brightness.light,
      ),
      elevation: 0,
      centerTitle: true,
      toolbarHeight: 48.h,
      leading: Padding(
        padding: EdgeInsets.only(top: 2.h),
        child: IconButton(
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
          icon: Padding(
            padding: EdgeInsets.only(left: 8.w),
            child: Image.asset(
              'assets/icons/ui/back_arrow.webp',
              width: 24.r,
              height: 24.r,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20.r,
                color: Colors.white,
              ),
            ),
          ),
          // Сначала пробуем закрыть локальный Navigator (например, если
          // экран был открыт через MaterialPageRoute поверх GoRouter
          // shell — paywall, ReviewScreen, ServicePaywall и т.п.).
          // Иначе — pop в стеке GoRouter. Без этого после возврата с
          // вложенного MaterialPageRoute back-кнопка экрана GoRouter
          // не реагировала: Navigator.maybePop() возвращал false
          // (стек уже пуст), а GoRouter не получал сигнала.
          onPressed: () {
            final NavigatorState nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
            } else if (context.canPop()) {
              context.pop();
            }
          },
        ),
      ),
      title: Padding(
        padding: EdgeInsets.only(top: 2.h),
        child: Text(
          title,
          style: AppTextStyles.titleS.copyWith(color: Colors.white),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
      actions: actions,
    );
  }
}

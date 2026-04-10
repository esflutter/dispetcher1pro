import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/features/shell/widgets/support_fab.dart';

/// Поисковая строка с оранжевой кнопкой фильтра — общий компонент для
/// «Лента заказов» и «Заказы на карте».
class CatalogSearchBar extends StatelessWidget {
  const CatalogSearchBar({
    super.key,
    required this.onFilterTap,
    this.controller,
    this.onChanged,
  });

  final VoidCallback onFilterTap;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              height: 44.h,
              padding: EdgeInsets.only(left: 9.w, right: 12.w),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.search,
                      color: AppColors.textTertiary, size: 24.r),
                  SizedBox(width: 5.w),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      cursorColor: AppColors.primary,
                      style: AppTextStyles.bodyMRegular.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 17.sp,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Поиск',
                        hintStyle: AppTextStyles.bodyMRegular.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 17.sp,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: onFilterTap,
            child: Container(
              width: 44.h,
              height: 44.h,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(Icons.tune, color: Colors.white, size: 20.r),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill-сегментированный переключатель «Списком / На карте».
class CatalogSegmented extends StatelessWidget {
  const CatalogSegmented({
    super.key,
    required this.index,
    required this.items,
    required this.onChanged,
  });

  final int index;
  final List<String> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      height: 36.h,
      padding: EdgeInsets.all(3.r),
      decoration: BoxDecoration(
        color: AppColors.fieldFill,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index
                        ? AppColors.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18.r),
                  ),
                  child: Text(
                    items[i],
                    style: AppTextStyles.bodyMMedium.copyWith(
                      color: i == index
                          ? Colors.white
                          : AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Плавающая кнопка ИИ-ассистента (правый нижний угол). Внешний вид —
/// единый для всех экранов: используем канонический [SupportFab] из shell,
/// чтобы FAB на вкладке «Каталог» и на вложенных страницах выглядел
/// одинаково.
class AiAssistantFab extends StatelessWidget {
  const AiAssistantFab({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SupportFab(onTap: onTap);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';

/// Карточка услуги в списке «Мои услуги».
class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    required this.title,
    required this.machinery,
    required this.pricePerHour,
    required this.pricePerDay,
    this.minOrder = '',
    this.onTap,
  });

  final String title;
  final List<String> machinery;
  final String pricePerHour;
  final String pricePerDay;
  /// Минимальный заказ в часах (строка). Пусто — не показываем.
  final String minOrder;
  final VoidCallback? onTap;

  bool get _hasHour => pricePerHour.isNotEmpty && pricePerHour != '0';
  bool get _hasDay => pricePerDay.isNotEmpty && pricePerDay != '0';
  int? get _minHours => int.tryParse(minOrder);

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTextStyles.body.copyWith(
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    );
    final valueStyle = AppTextStyles.bodyMedium.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.primary,
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Серый тег с видом техники прячем, когда он совпадает с названием
            // услуги (название теперь = вид техники) — иначе дублируется.
            if (!(machinery.length == 1 && machinery.first == title)) ...[
              Text(
                machinery.join('   '),
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textTertiary,
                  height: 1.78,
                ),
              ),
              SizedBox(height: 8.h),
            ],
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                if (_hasHour) ...[
                  Flexible(
                    child: Text('₽ / час',
                        style: labelStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  SizedBox(width: 6.w),
                  Flexible(
                    child: Text('$pricePerHour ₽',
                        style: valueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
                if (_hasHour && _hasDay) SizedBox(width: 24.w),
                if (_hasDay) ...[
                  Flexible(
                    child: Text('₽ / день',
                        style: labelStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  SizedBox(width: 6.w),
                  Flexible(
                    child: Text('$pricePerDay ₽',
                        style: valueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ],
            ),
            if (_minHours != null && _minHours! > 0) ...[
              SizedBox(height: 8.h),
              Text(
                'Минимальный заказ от $_minHours ${_hoursWord(_minHours!)}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Склонение «час» после числа: «от 1 часа», «от 4 часов».
String _hoursWord(int n) {
  final int mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'часов';
  if (n % 10 == 1) return 'часа';
  return 'часов';
}

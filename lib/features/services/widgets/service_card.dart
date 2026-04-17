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
    required this.description,
    required this.pricePerHour,
    required this.pricePerDay,
    this.onTap,
  });

  final String title;
  final List<String> machinery;
  final String description;
  final String pricePerHour;
  final String pricePerDay;
  final VoidCallback? onTap;

  bool get _hasHour => pricePerHour.isNotEmpty && pricePerHour != '0';
  bool get _hasDay => pricePerDay.isNotEmpty && pricePerDay != '0';

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
            SizedBox(height: 4.h),
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
            SizedBox(height: 6.h),
            Text(
              description,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 14.sp,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                if (_hasHour) ...[
                  Text('₽ / час', style: labelStyle),
                  SizedBox(width: 6.w),
                  Text('$pricePerHour ₽', style: valueStyle),
                ],
                if (_hasHour && _hasDay) SizedBox(width: 24.w),
                if (_hasDay) ...[
                  Text('₽ / день', style: labelStyle),
                  SizedBox(width: 6.w),
                  Text('$pricePerDay ₽', style: valueStyle),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

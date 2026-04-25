import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/utils/plural.dart';

/// Шапка заказчика в деталях заказа: аватар + имя + звезда с рейтингом
/// и подчёркнутая кликабельная «N отзывов». Используется в каталоге
/// (`CatalogOrderDetailScreen`) и «Моих заказах» (`MyOrderDetailScreen`).
/// Если передан [onCall], справа появляется круглая оранжевая кнопка
/// вызова — показывается, когда заказ принят и у исполнителя есть
/// доступ к телефону заказчика.
class CustomerHeader extends StatelessWidget {
  const CustomerHeader({
    super.key,
    required this.name,
    required this.rating,
    required this.reviews,
    required this.onTap,
    this.onReviewsTap,
    this.onCall,
    this.avatarUrl,
  });

  final String name;
  final double rating;
  final int reviews;
  final VoidCallback onTap;
  final String? avatarUrl;

  /// Отдельный колбэк на «N отзывов». Если задан — тап по подчёркнутому
  /// тексту открывает экран отзывов, не триггеря [onTap].
  final VoidCallback? onReviewsTap;
  final VoidCallback? onCall;

  String _fmtRating(double v) =>
      v.toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 28.r,
                  backgroundColor: AppColors.primaryTint,
                  backgroundImage: (avatarUrl != null &&
                          avatarUrl!.trim().isNotEmpty)
                      ? NetworkImage(avatarUrl!) as ImageProvider
                      : const AssetImage(
                          'assets/images/catalog/avatar_placeholder.webp'),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Row(
                        children: <Widget>[
                          Image.asset(
                            'assets/images/catalog/star.webp',
                            width: 20.r,
                            height: 20.r,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.star_rounded,
                              size: 20.r,
                              color: AppColors.ratingStar,
                            ),
                          ),
                          SizedBox(width: 4.w),
                          Text(
                            _fmtRating(rating),
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w400,
                              height: 1.3,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(width: 16.w),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onReviewsTap,
                            child: Text(
                              '$reviews ${reviewsWord(reviews)}',
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w400,
                                height: 1.3,
                                color: AppColors.textPrimary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (onCall != null) ...<Widget>[
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: onCall,
            child: Container(
              width: 40.r,
              height: 40.r,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                Icons.phone,
                color: Colors.white,
                size: 22.r,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

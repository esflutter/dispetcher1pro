import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/features/catalog/order_detail_screen.dart';
import 'package:dispatcher_1/features/catalog/orders_map_screen.dart';

/// Просмотр заказа на карте — карта во весь экран и нижняя карточка
/// заказа (по Figma «Просмотр заказа на карте»).
class OrderOnMapScreen extends StatelessWidget {
  const OrderOnMapScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: OrdersMapScreen()),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8.w,
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textPrimary, size: 20.r),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OrderDetailScreen(orderId: orderId),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text('Экскаватор',
                            style: AppTextStyles.caption.copyWith(
                                color: AppColors.textTertiary)),
                        Text('2 часа назад',
                            style: AppTextStyles.caption.copyWith(
                                color: AppColors.textTertiary)),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    Text('Нужен экскаватор для копки траншеи',
                        style: AppTextStyles.titleS
                            .copyWith(fontWeight: FontWeight.w700)),
                    SizedBox(height: 8.h),
                    _Line(label: 'Дата аренды:',
                        value: '15-19 июня · 09:00–18:00'),
                    SizedBox(height: 2.h),
                    _Line(label: 'Адрес:',
                        value: 'Московская область, Москва, Улица1, д 144'),
                    SizedBox(height: 8.h),
                    Text('80 000 – 100 000 ₽',
                        style: AppTextStyles.bodyMMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12.sp,
          color: AppColors.textPrimary,
          height: 1.4,
        ),
        children: <TextSpan>[
          TextSpan(
            text: '$label ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

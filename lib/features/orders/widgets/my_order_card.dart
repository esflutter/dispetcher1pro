import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'package:dispatcher_1/features/orders/widgets/order_status_pill.dart';

/// Карточка заказа в списке «Мои заказы».
/// Сверху — пилюля статуса, ниже — теги техники, заголовок, дата/адрес.
/// Для статусов accepted/completed снизу появляется блок заказчика
/// (аватар + имя + телефон + кнопка-стрелка).
class MyOrderCard extends StatelessWidget {
  const MyOrderCard({
    super.key,
    required this.status,
    required this.title,
    required this.equipment,
    required this.rentDate,
    required this.address,
    required this.publishedAgo,
    this.customerName,
    this.customerPhone,
    this.customerAvatar,
    this.onTap,
    this.onContact,
  });

  final MyOrderStatus status;
  final String title;
  final List<String> equipment;
  final String rentDate;
  final String address;
  final String publishedAgo;
  final String? customerName;
  final String? customerPhone;
  final String? customerAvatar;
  final VoidCallback? onTap;
  final VoidCallback? onContact;

  bool get _showCustomerRow =>
      (status == MyOrderStatus.accepted ||
          status == MyOrderStatus.completed) &&
      customerName != null;

  @override
  Widget build(BuildContext context) {
    // Стиль тегов техники и «Сегодня в 11:30» — как в OrderCard каталога:
    // межстрочный 1.78, кегль 12, серый.
    final TextStyle tagStyle = TextStyle(
      fontFamily: 'Roboto',
      fontSize: 12.sp,
      fontWeight: FontWeight.w400,
      color: AppColors.textTertiary,
      height: 1.78,
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            OrderStatusPill(status: status),
            SizedBox(height: 6.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    equipment.join('   '),
                    style: tagStyle,
                  ),
                ),
                SizedBox(width: 8.w),
                Text(publishedAgo, style: tagStyle),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 17.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 8.h),
            _LabelLine(label: 'Дата аренды:', value: rentDate),
            SizedBox(height: 5.h),
            _LabelLine(
              label: 'Адрес:',
              value: address,
              valueUnderlined: true,
            ),
            if (_showCustomerRow) ...<Widget>[
              SizedBox(height: 12.h),
              _CustomerRow(
                name: customerName!,
                phone: customerPhone ?? '',
                avatar: customerAvatar,
                // Иконка вызова — только пока заказ активен. В статусе
                // «Завершён» связываться с заказчиком по заказу уже не
                // нужно, иконку скрываем.
                onContact:
                    status == MyOrderStatus.completed ? null : onContact,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LabelLine extends StatelessWidget {
  const _LabelLine({
    required this.label,
    required this.value,
    this.valueUnderlined = false,
  });

  final String label;
  final String value;
  final bool valueUnderlined;

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 13.sp,
          color: AppColors.textPrimary,
          height: 1.4,
        ),
        children: <TextSpan>[
          TextSpan(
            text: '$label ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
              decoration: valueUnderlined
                  ? TextDecoration.underline
                  : TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.name,
    required this.phone,
    required this.avatar,
    required this.onContact,
  });

  final String name;
  final String phone;
  final String? avatar;
  final VoidCallback? onContact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        CircleAvatar(
          radius: 24.r,
          backgroundColor: AppColors.primaryTint,
          backgroundImage: AssetImage(
            avatar ?? 'assets/images/catalog/avatar_placeholder.webp',
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                name.trim().isEmpty ? CropResult.namePlaceholder : name,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                phone,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w400,
                  height: 1.3,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (onContact != null) ...<Widget>[
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: onContact,
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

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Секция «жирный заголовок + содержимое» с нижним отступом 12.h.
/// Используется на экранах деталей заказа («Дата и время аренды»,
/// «Адрес», «Требуемая спецтехника» и т.д.) — общий виджет для
/// каталога и раздела «Мои заказы».
class LabeledSection extends StatelessWidget {
  const LabeledSection({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          SizedBox(height: 4.h),
          child,
        ],
      ),
    );
  }
}

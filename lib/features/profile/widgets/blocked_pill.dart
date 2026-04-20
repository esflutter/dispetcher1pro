import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';

/// Полноширинная красная «пилюля» «Ваш профиль заблокирован».
/// Показывается только когда `AccountBlock.isBlocked == true`.
class BlockedPill extends StatelessWidget {
  const BlockedPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 25.h,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: AppColors.errorTint,
        borderRadius: BorderRadius.circular(100.r),
      ),
      child: Text(
        'Ваш профиль заблокирован',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
          height: 1.0,
          color: AppColors.error,
        ),
      ),
    );
  }
}

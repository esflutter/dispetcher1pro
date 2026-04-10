import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Модальное окно отклика на заказ. Два состояния по Figma:
///   verified == false → «Подтвердите свои данные»
///   verified == true  → «Ваш отклик отправлен!»
class RespondModalDialog extends StatelessWidget {
  const RespondModalDialog({super.key, required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: verified ? _verifiedBody(context) : _unverifiedBody(context),
      ),
    );
  }

  Widget _verifiedBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(Icons.close_rounded,
                size: 22.r, color: AppColors.textTertiary),
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          'Ваш отклик отправлен!',
          textAlign: TextAlign.center,
          style: AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 10.h),
        Text(
          'Заказчик рассмотрит вашу заявку на заказ. Если он выберет вас — '
          'заказ появится в разделе Мои заказы.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMRegular
              .copyWith(color: AppColors.textSecondary),
        ),
        SizedBox(height: 20.h),
        PrimaryButton(
          label: 'Ок',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _unverifiedBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: 8.h),
        Center(
          child: Container(
            width: 72.r,
            height: 72.r,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_outline,
                size: 40.r, color: Colors.white),
          ),
        ),
        SizedBox(height: 16.h),
        Text(
          'Подтвердите свои данные',
          textAlign: TextAlign.center,
          style: AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 10.h),
        Text(
          'Чтобы откликаться на заказы, нужно отправить документы на проверку. '
          'Это займёт пару минут.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMRegular
              .copyWith(color: AppColors.textSecondary),
        ),
        SizedBox(height: 20.h),
        PrimaryButton(
          label: 'Отправить документы',
          onPressed: () => Navigator.of(context).pop(),
        ),
        SizedBox(height: 4.h),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Может быть позже',
            style: AppTextStyles.bodyMMedium
                .copyWith(color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

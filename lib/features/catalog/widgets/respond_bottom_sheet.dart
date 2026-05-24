import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

import 'package:dispatcher_1/core/widgets/dialog_close_button.dart';
/// Модальное окно отклика на заказ. Два состояния по Figma:
///   verified == false → «Подтвердите свои данные»
///   verified == true  → «Ваш отклик отправлен!»
class RespondModalDialog extends StatelessWidget {
  const RespondModalDialog({
    super.key,
    required this.verified,
    this.rejectReason,
  });

  final bool verified;

  /// Текстовая причина отказа модерацией
  /// (`profiles_private.verification_reject_reason`). Показывается ниже
  /// заголовка только когда задана и `verified == false`.
  final String? rejectReason;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 16.w),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.r, 18.r, 16.r, 26.r),
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
          child: DialogCloseButton(
            onTap: () => Navigator.of(context).pop(),
            color: AppColors.textTertiary,
            iconSize: 22.r,
          ),
        ),
        SizedBox(height: 24.h),
        Text(
          'Ваш отклик отправлен!',
          textAlign: TextAlign.center,
          style: AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 10.h),
        Text(
          'Заказчик рассмотрит вашу заявку. Если он выберет вас, '
          'заказ появится в разделе «Принятые заказы».',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMRegular
              .copyWith(color: AppColors.textSecondary),
        ),
        SizedBox(height: 20.h),
        PrimaryButton(
          label: 'Ок',
          onPressed: () => Navigator.of(context).pop(),
        ),
        SizedBox(height: 16.h),
      ],
    );
  }

  Widget _unverifiedBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: 24.h),
        Center(
          child: Image.asset(
            'assets/images/catalog/user_edit.webp',
            width: 96.r,
            height: 96.r,
            fit: BoxFit.contain,
          ),
        ),
        SizedBox(height: 24.h),
        Text(
          'Подтвердите свои данные',
          textAlign: TextAlign.center,
          style: AppTextStyles.titleL,
        ),
        SizedBox(height: 10.h),
        Text(
          'Чтобы откликаться на заказы, нужно отправить документы на проверку. '
          'Это займёт пару минут.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body
              .copyWith(color: AppColors.textSecondary),
        ),
        if (rejectReason != null && rejectReason!.trim().isNotEmpty) ...<Widget>[
          SizedBox(height: 10.h),
          Text(
            'Причина отказа: ${rejectReason!.trim()}',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppColors.error),
          ),
        ],
        SizedBox(height: 18.h),
        PrimaryButton(
          label: 'Отправить документы',
          onPressed: () {
            Navigator.of(context).pop();
            GoRouter.of(context).push('/assistant/chat', extra: <String, String>{
              'initial': 'verify_documents',
            });
          },
        ),
        SizedBox(height: 18.h),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: Text(
              'Может быть, позже',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textPrimary),
            ),
          ),
        ),
        SizedBox(height: 14.h),
      ],
    );
  }
}

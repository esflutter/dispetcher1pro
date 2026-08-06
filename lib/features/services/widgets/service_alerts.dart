import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

import 'package:dispatcher_1/core/widgets/dialog_close_button.dart';
/// Диалог подтверждения удаления услуги.
Future<bool?> showDeleteServiceDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 16.w),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 22.h),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: DialogCloseButton(
                onTap: () => Navigator.of(ctx).pop(false),
                color: AppColors.textTertiary,
                iconSize: 22.r,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'Вы уверены, что хотите\nудалить услугу?',
              style: AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 18.h),
            PrimaryButton(
              label: 'Удалить',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            SizedBox(height: 12.h),
            GestureDetector(
              onTap: () => Navigator.of(ctx).pop(false),
              child: Center(
                child: Text('Вернуться',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textPrimary)),
              ),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    ),
  );
}

/// Диалог «Ваша услуга размещена!» после успешной оплаты.
///
/// [needsDocs] — услуга создана, но документы по ней ещё не одобрены, поэтому
/// заказчикам она пока не видна. Обещать «теперь вас видят» в этом случае
/// нельзя: в режиме документов-по-услугам сервер пускает в каталог только
/// одобренные услуги, и человек не понимал бы, почему заказов нет.
Future<void> showServicePublishedDialog(
  BuildContext context, {
  bool needsDocs = false,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 16.w),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.r, 14.r, 16.r, 22.r),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: DialogCloseButton(
                onTap: () => Navigator.of(ctx).pop(),
                color: AppColors.textTertiary,
                iconSize: 22.r,
              ),
            ),
            SizedBox(height: 22.h),
            Text(
              needsDocs ? 'Услуга создана' : 'Ваша услуга размещена!',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8.h),
            Text(
              needsDocs
                  ? 'Чтобы заказчики её увидели,\nотправьте документы по услуге —\nих проверит администратор'
                  : 'Теперь услуга видна другим\nпользователям, и заказчики смогут\nсвязаться с вами',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMRegular
                  .copyWith(color: AppColors.textSecondary),
            ),
            SizedBox(height: 18.h),
            PrimaryButton(
              label: 'Ок',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            SizedBox(height: 12.h),
          ],
        ),
      ),
    ),
  );
}

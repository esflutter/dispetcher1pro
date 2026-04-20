import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/respond_bottom_sheet.dart';

Future<void> showCreateExecutorCardAlert(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => const RespondModalDialog(verified: false),
  );
}

/// Попап «Сначала создайте карточку исполнителя» — показывается, когда
/// пользователь пытается зайти в разделы, требующие созданной карточки
/// («Мой график», «Мои услуги»), но карточка ещё не оформлена. По тапу
/// «Создать» возвращает `true`, родитель сам решает куда навигировать.
Future<bool?> showExecutorCardRequiredAlert(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Container(
        // Отступы и структура (крестик → 20 → заголовок → … → 8.h)
        // идентичны другим попапам с парой «основное действие +
        // Вернуться» — `_ConfirmDialog` из `order_alerts.dart` и
        // `ScheduleAlerts`.
        padding: EdgeInsets.fromLTRB(16.r, 14.r, 16.r, 22.r),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(false),
                child: Icon(Icons.close_rounded,
                    size: 22.r, color: AppColors.textTertiary),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Сначала создайте карточку\nисполнителя',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: AppSpacing.xs),
            Text(
              'Раздел станет доступен, как только\nвы оформите карточку.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textSecondary),
            ),
            SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Создать',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            SizedBox(height: AppSpacing.lg),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(false),
              child: Center(
                child: Text(
                  'Вернуться',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    ),
  );
}

/// Bottom-sheet алерт подтверждения удаления карточки исполнителя.
Future<bool?> showDeleteExecutorCardAlert(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
      ),
      insetPadding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: AppSpacing.sm),
            Text(
              'Вы уверены, что хотите\nудалить карточку?',
              style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              height: 54.h,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                  ),
                ),
                child: Text('Удалить',
                    style:
                        AppTextStyles.button.copyWith(color: Colors.white)),
              ),
            ),
            SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Отмена',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    ),
  );
}

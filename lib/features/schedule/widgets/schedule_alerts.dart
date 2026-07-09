import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/schedule/schedule_prompt_prefs.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

import 'package:dispatcher_1/core/widgets/dialog_close_button.dart';
/// Центрированный alert-dialog «Закрыть приём заказов?».
class ScheduleAlerts {
  ScheduleAlerts._();

  /// Алерт-предупреждение перед тем, как пометить день выходным, если
  /// на нём уже есть активные заказы (принятые или ожидающие
  /// подтверждения). Подтверждение = все эти заказы будут отменены.
  static Future<bool?> showMarkDayOffWithActiveOrders(
    BuildContext context, {
    required int ordersCount,
  }) {
    final String noun;
    final String cancellation;
    final int mod100 = ordersCount % 100;
    final int mod10 = ordersCount % 10;
    if (mod100 >= 11 && mod100 <= 14) {
      noun = 'активных заказов';
      cancellation = 'заказы будут отменены';
    } else if (mod10 == 1) {
      noun = 'активный заказ';
      cancellation = 'заказ будет отменён';
    } else if (mod10 >= 2 && mod10 <= 4) {
      noun = 'активных заказа';
      cancellation = 'заказы будут отменены';
    } else {
      noun = 'активных заказов';
      cancellation = 'заказы будут отменены';
    }
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
          padding: EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: DialogCloseButton(
                  onTap: () => Navigator.of(ctx).pop(false),
                  color: AppColors.textSecondary,
                  iconSize: 22.r,
                ),
              ),
              Text(
                'Отметить день нерабочим?',
                style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                'На этот день есть $ordersCount $noun. '
                'Если отметить день нерабочим, $cancellation.',
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Отметить нерабочим',
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
              SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'Вернуться',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Разовый попап «Заполните график работы» после первой активации
  /// подписки (привязки карты). Вызывается после первого кадра корневого
  /// экрана и карточки исполнителя: если сигнал [SchedulePromptPrefs.pending]
  /// поднят и попап ещё ни разу не показывали — показывает его и по
  /// «Указать график» уводит в «Мой график». Показ фиксируется навсегда
  /// (persisted), поэтому больше одного раза попап не появится.
  static Future<void> maybeShowFillSchedulePrompt(BuildContext context) async {
    if (!SchedulePromptPrefs.pending) return;
    // Сбрасываем сигнал сразу — чтобы второй экран (shell + карточка
    // исполнителя) не попытался показать попап параллельно.
    SchedulePromptPrefs.pending = false;
    if (await SchedulePromptPrefs.seen()) return;
    await SchedulePromptPrefs.markSeen();
    if (!context.mounted) return;
    final bool? go = await _showFillSchedulePrompt(context);
    if (go == true && context.mounted) {
      context.push('/schedule');
    }
  }

  static Future<bool?> _showFillSchedulePrompt(BuildContext context) {
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
          padding: EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: DialogCloseButton(
                  onTap: () => Navigator.of(ctx).pop(false),
                  color: AppColors.textSecondary,
                  iconSize: 22.r,
                ),
              ),
              Text(
                'Заполните график работы',
                style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                'Заказчики ищут исполнителей на конкретные даты. '
                'Отметьте в графике дни, когда вы принимаете заказы, — '
                'тогда вас будут находить в поиске.',
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Указать график',
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
              SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'Позже',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<bool?> showCloseAcceptance(BuildContext context) {
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
          padding: EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: DialogCloseButton(
                  onTap: () => Navigator.of(ctx).pop(false),
                  color: AppColors.textSecondary,
                  iconSize: 22.r,
                ),
              ),
              Text(
                'Закрыть приём заказов?',
                style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                'Новые заказы на этот день\nпоступать не будут',
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Закрыть',
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
              SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'Вернуться',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

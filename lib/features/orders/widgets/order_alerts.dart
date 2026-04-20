import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Алерт «Вы уверены, что хотите отказаться от заказа?»
/// Используется на экране подтверждённого заказа (исполнитель уже принял).
Future<void> showConfirmRefuseDialog(
  BuildContext context, {
  required VoidCallback onRefuse,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (BuildContext ctx) => _ConfirmDialog(
      title: 'Вы уверены, что хотите\nотказаться от заказа?',
      primaryLabel: 'Отказаться',
      onPrimary: () {
        Navigator.of(ctx).pop();
        onRefuse();
      },
    ),
  );
}

/// Алерт «Вы уверены, что хотите отклонить заказ?»
/// Используется на экране, где исполнитель ещё не подтвердил заказ.
Future<void> showConfirmDeclineDialog(
  BuildContext context, {
  required VoidCallback onDecline,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (BuildContext ctx) => _ConfirmDialog(
      title: 'Вы уверены, что хотите\nотклонить заказ?',
      primaryLabel: 'Отклонить заказ',
      onPrimary: () {
        Navigator.of(ctx).pop();
        onDecline();
      },
    ),
  );
}

/// Алерт «Вы уверены, что хотите отозвать отклик?»
/// Используется на экране заказа со статусом «Ожидает ответа заказчика»,
/// когда исполнитель уже отправил отклик, но заказчик ещё не выбрал.
Future<void> showConfirmWithdrawDialog(
  BuildContext context, {
  required VoidCallback onWithdraw,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (BuildContext ctx) => _ConfirmDialog(
      title: 'Вы уверены, что хотите\nотозвать отклик?',
      primaryLabel: 'Отозвать отклик',
      onPrimary: () {
        Navigator.of(ctx).pop();
        onWithdraw();
      },
    ),
  );
}

/// Подтверждение принятия заказа исполнителем (опционально, по флоу).
Future<void> showConfirmAcceptDialog(
  BuildContext context, {
  required VoidCallback onConfirm,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (BuildContext ctx) => _ConfirmDialog(
      title: 'Вы уверены, что хотите\nпринять заказ?',
      primaryLabel: 'Подтвердить',
      onPrimary: () {
        Navigator.of(ctx).pop();
        onConfirm();
      },
    ),
  );
}

/// Алерт «Заказ принят. Свяжитесь с заказчиком по указанным на странице
/// данным.» — показывается исполнителю сразу после подтверждения заказа
/// из статуса «Ждёт подтверждения». Аналог `showExecutorSelectedDialog`
/// из приложения заказчика — сообщает о мэтче и наводит на контакты,
/// которые только что открылись на той же странице.
Future<void> showOrderAcceptedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (BuildContext ctx) => Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 16.w),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.r, 22.r, 16.r, 22.r),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Заказ принят',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Свяжитесь с заказчиком по указанным на странице данным.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16.sp,
                fontWeight: FontWeight.w400,
                height: 1.3,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 18.h),
            PrimaryButton(
              label: 'Ок',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Алерт «Вы оставили отзыв» — показывается после успешной отправки отзыва.
/// Возвращает `true`, если пользователь нажал «Мои отзывы», иначе `null`.
Future<bool?> showReviewSentDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (BuildContext ctx) => Dialog(
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
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Icon(
                  Icons.close_rounded,
                  size: 22.r,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            SizedBox(height: 10.h),
            Center(
              child: Image.asset(
                'assets/images/orders/big_star.webp',
                width: 67.r,
                height: 67.r,
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(height: 30.h),
            Text(
              'Вы оставили отзыв',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Пользователь увидит вашу оценку',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16.sp,
                fontWeight: FontWeight.w400,
                height: 1.3,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 14.h),
            PrimaryButton(
              label: 'Ок',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Внутренний компонент: модалка-подтверждение с заголовком, кнопкой
/// и текстом «Вернуться» снизу.
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final String title;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Icon(
                  Icons.close_rounded,
                  size: 22.r,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 20.h),
            PrimaryButton(label: primaryLabel, onPressed: onPrimary),
            SizedBox(height: 20.h),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Center(
                child: Text(
                  'Вернуться',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }
}

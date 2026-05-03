import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Алерт «Вы уверены, что хотите отказаться от заказа?»
/// Возвращает `true`, если пользователь нажал «Отказаться»; `false`/`null` —
/// если закрыл/отменил. Сама операция в БД делается вызывающим экраном
/// уже ПОСЛЕ закрытия диалога — раньше колбэк запускался прямо отсюда без
/// `await`, и UI закрывал детальный экран ДО ответа БД (при ошибке мэтч
/// оставался в старом статусе, юзер получал PostgrestException на
/// следующем тапе по кнопке).
Future<bool?> showConfirmRefuseDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (BuildContext ctx) => _ConfirmDialog(
      title: 'Вы уверены, что хотите\nотказаться от заказа?',
      primaryLabel: 'Отказаться',
      onPrimary: () => Navigator.of(ctx).pop(true),
    ),
  );
}

/// Алерт «Вы уверены, что хотите отклонить заказ?» — возвращает `true`
/// при подтверждении, см. [showConfirmRefuseDialog] про новый контракт.
Future<bool?> showConfirmDeclineDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (BuildContext ctx) => _ConfirmDialog(
      title: 'Вы уверены, что хотите\nотклонить заказ?',
      primaryLabel: 'Отклонить заказ',
      onPrimary: () => Navigator.of(ctx).pop(true),
    ),
  );
}

/// Алерт «Вы уверены, что хотите отозвать отклик?» — возвращает `true`
/// при подтверждении.
Future<bool?> showConfirmWithdrawDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (BuildContext ctx) => _ConfirmDialog(
      title: 'Вы уверены, что хотите\nотозвать отклик?',
      primaryLabel: 'Отозвать отклик',
      onPrimary: () => Navigator.of(ctx).pop(true),
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

/// Попап «Подписка приостановлена» — показывается при попытке откликнуться
/// или принять заказ, когда подписка приостановлена. Кнопка ведёт на экран
/// управления подпиской. Возвращает `true`, если пользователь нажал кнопку.
Future<bool?> showSubscriptionPausedDialog(BuildContext context) {
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
            SizedBox(height: 12.h),
            Text(
              'Подписка приостановлена',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              'Возобновите подписку, чтобы откликаться на заказы и принимать их',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16.sp,
                fontWeight: FontWeight.w400,
                height: 1.3,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 20.h),
            PrimaryButton(
              label: 'Управление подпиской',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            SizedBox(height: 20.h),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(),
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

/// Попап «Для отклика необходима карточка исполнителя».
/// Показывается при попытке откликнуться, если подписка оплачена,
/// но карточка ещё не создана. Возвращает `true` если нажали кнопку перехода.
Future<bool?> showExecutorCardRequiredDialog(BuildContext context) {
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
            SizedBox(height: 12.h),
            Text(
              'Создайте карточку исполнителя',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              'Для отклика на заказ необходимо создать карточку исполнителя',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16.sp,
                fontWeight: FontWeight.w400,
                height: 1.3,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 20.h),
            PrimaryButton(
              label: 'Создать карточку',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            SizedBox(height: 20.h),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(),
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
    ),
  );
}

/// Попап «У вас нет услуги с техникой [equipment]».
/// Показывается при попытке выбрать технику в шторке отклика,
/// если у исполнителя нет соответствующей услуги.
Future<void> showNoServiceForEquipmentDialog(
  BuildContext context, {
  required String equipment,
  required VoidCallback onGoToServices,
}) {
  return showDialog<void>(
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
                child: Icon(Icons.close_rounded,
                    size: 22.r, color: AppColors.textTertiary),
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              'Нет услуги с этой техникой',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              'Создайте услугу с техникой «$equipment», чтобы откликнуться на этот заказ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16.sp,
                fontWeight: FontWeight.w400,
                height: 1.3,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 20.h),
            PrimaryButton(
              label: 'Мои услуги',
              onPressed: () {
                Navigator.of(ctx).pop();
                onGoToServices();
              },
            ),
            SizedBox(height: 20.h),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(),
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

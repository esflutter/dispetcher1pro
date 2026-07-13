import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

import 'package:dispatcher_1/core/widgets/dialog_close_button.dart';
import 'package:dispatcher_1/features/profile/account_block.dart';
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

/// Алерт-подтверждение ручного завершения заказа. Возвращает `true`,
/// если пользователь нажал главную кнопку; сам RPC вызывает экран уже
/// ПОСЛЕ закрытия диалога (тот же контракт, что у [showConfirmRefuseDialog]).
/// С двухшаговым завершением (миграция 116) диалог используется в двух
/// сценариях с разными текстами: «Отметить выполненным» (уйдёт запрос
/// заказчику) и «Подтвердить завершение» (заказ завершится сразу) —
/// поэтому заголовок/текст/кнопка передаются параметрами.
Future<bool?> showConfirmCompleteDialog(
  BuildContext context, {
  String title = 'Заказ выполнен?',
  String body =
      'Заказчик получит запрос на подтверждение. После его ответа заказ '
      'будет завершён, и можно будет оставить отзыв.',
  String primaryLabel = 'Да, выполнен',
}) {
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
              child: DialogCloseButton(
                onTap: () => Navigator.of(ctx).pop(),
                color: AppColors.textTertiary,
                iconSize: 22.r,
              ),
            ),
            SizedBox(height: 12.h),
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
            SizedBox(height: 10.h),
            Text(
              body,
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
              label: primaryLabel,
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

/// Диалог «Работа не завершена»: заказчик отметил работу выполненной, но
/// исполнитель не согласен. Обязательное поле причины (до 300 символов),
/// причина уйдёт модератору вместе со спором. Возвращает введённый текст,
/// если нажали «Отправить»; `null` — если закрыли не отправив. Сам RPC
/// (`decline_match_completion`) вызывает экран уже ПОСЛЕ закрытия диалога
/// (тот же контракт, что у [showConfirmRefuseDialog]).
Future<String?> showDeclineCompletionDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (BuildContext ctx) => const _DeclineCompletionDialog(),
  );
}

class _DeclineCompletionDialog extends StatefulWidget {
  const _DeclineCompletionDialog();

  @override
  State<_DeclineCompletionDialog> createState() =>
      _DeclineCompletionDialogState();
}

class _DeclineCompletionDialogState extends State<_DeclineCompletionDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

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
              child: DialogCloseButton(
                onTap: () => Navigator.of(context).pop(),
                color: AppColors.textTertiary,
                iconSize: 22.r,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              'Работа не завершена?',
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
              'Опишите, что не так. Причина уйдёт модератору — '
              'он разберётся и примет решение.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16.sp,
                fontWeight: FontWeight.w400,
                height: 1.3,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 16.h),
            Container(
              constraints: BoxConstraints(minHeight: 56.h),
              decoration: BoxDecoration(
                color: AppColors.fieldFill,
                borderRadius: BorderRadius.circular(12.r),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: 16.w,
                vertical: 16.h,
              ),
              child: TextField(
                controller: _reason,
                // null — поле растёт вниз по мере добавления строк.
                maxLines: null,
                minLines: 1,
                maxLength: 300,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(300),
                ],
                // Кнопка «Отправить» активна только при непустой причине —
                // перерисовываем диалог на каждый ввод.
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w400,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  // Скрываем счётчик «0/300» снизу — ограничение нужно
                  // только как валидация ввода, показывать не надо.
                  counterText: '',
                  hintText: 'Что не так?',
                  hintStyle: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),
            SizedBox(height: 20.h),
            PrimaryButton(
              label: 'Отправить',
              // Сервер отобьёт пустую причину кодом reason_required —
              // не даём отправить её ещё на клиенте.
              enabled: _reason.text.trim().isNotEmpty,
              onPressed: () {
                final String text = _reason.text.trim();
                if (text.isEmpty) return;
                Navigator.of(context).pop(text);
              },
            ),
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
              child: DialogCloseButton(
                onTap: () => Navigator.of(ctx).pop(),
                color: AppColors.textTertiary,
                iconSize: 22.r,
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

/// Попап «Профиль заблокирован» — показывается при попытке действия (принять
/// заказ, подтвердить), когда аккаунт заблокирован за низкий рейтинг. Раньше
/// такие кнопки просто гасли без объяснения, и исполнитель не понимал, почему
/// действие недоступно. Текст согласован с плашкой в профиле.
Future<void> showAccountBlockedDialog(BuildContext context) {
  final DateTime? until = AccountBlock.blockedUntil;
  final bool forever = until != null && until.year >= 2090;
  final String body = forever
      ? 'Профиль заблокирован. Если это ошибка — напишите в поддержку '
          '(раздел «Профиль»).'
      : 'Ваш рейтинг ниже 2 звёзд, доступ временно ограничен '
          '${AccountBlock.blockedUntilText ?? 'на 30 дней'}. Во избежание '
          'дальнейших блокировок избегайте отзывов с низкой оценкой.';
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
              child: DialogCloseButton(
                onTap: () => Navigator.of(ctx).pop(),
                color: AppColors.textTertiary,
                iconSize: 22.r,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              'Профиль заблокирован',
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
              body,
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
              label: 'Понятно',
              onPressed: () => Navigator.of(ctx).pop(),
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
              child: DialogCloseButton(
                onTap: () => Navigator.of(ctx).pop(),
                color: AppColors.textTertiary,
                iconSize: 22.r,
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
              child: DialogCloseButton(
                onTap: () => Navigator.of(ctx).pop(),
                color: AppColors.textTertiary,
                iconSize: 22.r,
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

/// Попап «Заполните карточку исполнителя»: карточка создана, но без
/// адреса/радиуса она не опубликована, и сервер отклонит отклик
/// (card_not_published). Объясняем заранее и ведём в форму карточки.
/// Возвращает `true`, если нажали кнопку перехода.
Future<bool?> showExecutorCardIncompleteDialog(BuildContext context) {
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
              child: DialogCloseButton(
                onTap: () => Navigator.of(ctx).pop(),
                color: AppColors.textTertiary,
                iconSize: 22.r,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              'Заполните карточку исполнителя',
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
              'Чтобы откликаться на заказы, укажите в карточке адрес '
              'и радиус работы — по ним заказчики находят вас.',
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
              label: 'Заполнить карточку',
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
              child: DialogCloseButton(
                onTap: () => Navigator.of(ctx).pop(),
                color: AppColors.textTertiary,
                iconSize: 22.r,
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
              child: DialogCloseButton(
                onTap: () => Navigator.of(context).pop(),
                color: AppColors.textTertiary,
                iconSize: 22.r,
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

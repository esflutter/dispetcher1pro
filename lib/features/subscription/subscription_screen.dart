import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/ai/ai_navigation.dart';
import 'package:dispatcher_1/core/payments/payment_service.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/widgets/subscription_paywall.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';

import 'package:dispatcher_1/core/widgets/dialog_close_button.dart';
/// Состояние подписки.
enum SubscriptionStatus { active, paused, inactive }

/// Экран «Информация о подписке».
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  /// Показывать ли кнопку «Способы оплаты». Показываем если:
  ///   1) у юзера есть хотя бы одна привязанная карта, ИЛИ
  ///   2) юзер хоть раз оплачивал что-то платное (даже если карта
  ///      сохранена не была — например, через YooMoney) — раздел
  ///      управления методами оплаты ему всё равно полезен.
  /// Любая ошибка чтения трактуется как «не показывать», чтобы юзер
  /// не упёрся в пустой/сломанный экран.
  bool _showCardsButton = false;

  @override
  void initState() {
    super.initState();
    _loadPaymentMethodsAccess();
  }

  Future<void> _loadPaymentMethodsAccess() async {
    try {
      final List<dynamic> cards =
          await PaymentService.instance.listCards();
      if (!mounted) return;
      if (cards.isNotEmpty) {
        setState(() => _showCardsButton = true);
        return;
      }
      // Карт нет — но если был платёж, всё равно показываем кнопку.
      final bool hadPayment =
          await PaymentService.instance.hasAnySucceededPayment();
      if (!mounted) return;
      setState(() => _showCardsButton = hadPayment);
    } catch (_) {
      if (!mounted) return;
      setState(() => _showCardsButton = false);
    }
  }

  SubscriptionStatus get _status {
    if (VerificationStatus.hasSubscription) return SubscriptionStatus.active;
    if (VerificationStatus.subscriptionPaidUntilText != null) {
      return SubscriptionStatus.paused;
    }
    return SubscriptionStatus.inactive;
  }

  Future<void> _openPaywall() async {
    // Paywall показывает рекламную карточку «Получите доступ к заказам»
    // и при нажатии «Продолжить» сам уводит юзера в `/subscription/payment`.
    // Когда юзер вернётся (через payment_result_screen → popUntil to root),
    // `VerificationStatus.hasSubscription` уже обновлён реальным успехом.
    // Перерисуем экран, чтобы пересчитать _status.
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const SubscriptionPaywall(),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _onToggle(bool value) async {
    if (!value && _status == SubscriptionStatus.active) {
      // Выключение активной — переводит в «Приостановлена»: флаг
      // подписки снимаем, но оплаченный период оставляем; в БД
      // выключаем `subscription_auto_renew`. При ошибке откатываем
      // локальный флаг, чтобы UI и БД не разошлись.
      final bool? ok = await _showDisableDialog();
      if (ok != true) return;
      setState(() => VerificationStatus.hasSubscription = false);
      try {
        await ProfileService.instance.updateSubscriptionAutoRenew(false);
      } catch (_) {
        if (!mounted) return;
        setState(() => VerificationStatus.hasSubscription = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось выключить авто-продление. Попробуйте ещё раз.')),
        );
      }
    } else if (value && _status == SubscriptionStatus.paused) {
      // Возврат из «Приостановлена» в «Активна» — без повторной оплаты,
      // т. к. платёжный период ещё не закончился.
      setState(() => VerificationStatus.hasSubscription = true);
      try {
        await ProfileService.instance.updateSubscriptionAutoRenew(true);
      } catch (_) {
        if (!mounted) return;
        setState(() => VerificationStatus.hasSubscription = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось включить авто-продление. Попробуйте ещё раз.')),
        );
      }
    } else if (value && _status == SubscriptionStatus.inactive) {
      if (!mounted) return;
      await _openPaywall();
    }
  }

  Future<bool?> _showDisableDialog() {
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
              Text('Отключить подписку?',
                  style: AppTextStyles.titleL,
                  textAlign: TextAlign.center),
              SizedBox(height: AppSpacing.xs),
              Text(
                'Доступ к заказам будет закрыт, а ваши услуги не будут отображаться в каталоге',
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Отключить',
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
              SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Отмена',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textPrimary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCards() async {
    await context.push<void>('/subscription/cards');
    // После возврата перезагружаем список — юзер мог удалить последнюю
    // карту, тогда кнопку «Способы оплаты» больше показывать не нужно.
    if (mounted) await _loadPaymentMethodsAccess();
  }

  @override
  Widget build(BuildContext context) {
    final bool showPayButton = _status == SubscriptionStatus.inactive;
    final bool showCardsButton = _showCardsButton;
    final bool showAnyBottomButton = showPayButton || showCardsButton;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Информация о подписке'),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: showAnyBottomButton ? 88.h : 24.h),
        child: AiAssistantFab(onTap: () => openAssistantChat(context)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenH, vertical: 14.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Подписка',
                        style: AppTextStyles.button),
                  ),
                  _CustomToggle(
                    value: _status == SubscriptionStatus.active,
                    onChanged: _onToggle,
                  ),
                ],
              ),
            ),
            Divider(height: 1.h, color: AppColors.divider),
            Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.screenH,
                  AppSpacing.md, AppSpacing.screenH, 0),
              child: _StatusCard(status: _status),
            ),
            const Spacer(),
            if (showAnyBottomButton)
              Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      offset: const Offset(0, -1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showPayButton)
                      PrimaryButton(
                        label: 'Оплатить подписку',
                        onPressed: _openPaywall,
                      ),
                    if (showPayButton && showCardsButton)
                      SizedBox(height: 8.h),
                    if (showCardsButton)
                      PrimaryButton(
                        label: 'Способы оплаты',
                        onPressed: _openCards,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final String? paidUntil = VerificationStatus.subscriptionPaidUntilText;
    String title;
    String subtitle;
    switch (status) {
      case SubscriptionStatus.active:
        title = 'Подписка активна';
        subtitle = paidUntil != null
            ? 'Оплачено до $paidUntil'
            : 'Авто-продление включено';
      case SubscriptionStatus.paused:
        title = 'Подписка приостановлена';
        subtitle = paidUntil != null
            ? 'Оплачено до $paidUntil'
            : 'Авто-продление выключено';
      case SubscriptionStatus.inactive:
        title = 'Подписка неактивна';
        subtitle =
            'Оплатите подписку, чтобы откликаться на заказы и заказчики видели ваш профиль';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: AppTextStyles.h3Medium),
        SizedBox(height: AppSpacing.xs),
        Text(subtitle,
            style: AppTextStyles.body.copyWith(color: AppColors.textPrimary)),
      ],
    );
  }
}

class _CustomToggle extends StatelessWidget {
  const _CustomToggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final double w = 52.r;
    final double h = 32.r;
    final double thumb = 28.r;
    final double pad = 2.r;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(h / 2),
          color: value ? AppColors.toggleOn : AppColors.toggleOff,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: thumb,
            height: thumb,
            margin: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

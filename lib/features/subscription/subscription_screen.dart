import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/widgets/subscription_paywall.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';

/// Состояние подписки.
enum SubscriptionStatus { active, paused, inactive }

/// Экран «Информация о подписке».
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  SubscriptionStatus get _status {
    if (VerificationStatus.hasSubscription) return SubscriptionStatus.active;
    if (VerificationStatus.subscriptionPaidUntilText != null) {
      return SubscriptionStatus.paused;
    }
    return SubscriptionStatus.inactive;
  }

  Future<void> _openPaywall() async {
    final bool? paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => const SubscriptionPaywall(),
      ),
    );
    if (paid == true && mounted) {
      setState(() {
        VerificationStatus.hasSubscription = true;
        // В моке фиксируем дату оплаченного периода. В проде это придёт
        // с бэкенда вместе с ответом об успешной оплате.
        VerificationStatus.subscriptionPaidUntilText ??= '15 июля';
      });
    }
  }

  Future<void> _onToggle(bool value) async {
    if (!value && _status == SubscriptionStatus.active) {
      // Выключение активной — переводит в «Приостановлена»: флаг
      // подписки снимаем, но оплаченный период оставляем.
      final bool? ok = await _showDisableDialog();
      if (ok != true) return;
      setState(() => VerificationStatus.hasSubscription = false);
    } else if (value && _status == SubscriptionStatus.paused) {
      // Возврат из «Приостановлена» в «Активна» — без повторной оплаты,
      // т. к. платёжный период ещё не закончился.
      setState(() => VerificationStatus.hasSubscription = true);
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
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(false),
                  child: Icon(Icons.close_rounded,
                      size: 22.r, color: AppColors.textSecondary),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Информация о подписке'),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
            bottom: _status == SubscriptionStatus.inactive ? 88.h : 24.h),
        child: AiAssistantFab(onTap: () => context.push('/assistant/chat')),
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
            if (_status == SubscriptionStatus.inactive)
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
                child: PrimaryButton(
                  label: 'Оплатить подписку',
                  onPressed: _openPaywall,
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
            : 'Бесплатный период до 15 июля';
      case SubscriptionStatus.paused:
        title = 'Подписка приостановлена';
        subtitle = 'Оплачено до ${paidUntil ?? '15 июля'}';
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
          color: value ? const Color(0xFF34C759) : const Color(0xFFE0E0E0),
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

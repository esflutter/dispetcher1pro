import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';

/// Результат оплаты.
enum PaymentResult { success, error }

class PaymentResultScreen extends StatefulWidget {
  const PaymentResultScreen({super.key, this.result = PaymentResult.success});

  final PaymentResult result;

  @override
  State<PaymentResultScreen> createState() => _PaymentResultScreenState();
}

class _PaymentResultScreenState extends State<PaymentResultScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.result == PaymentResult.success) {
      // Активируем подписку: in-memory флаг включает все экраны (карточка
      // исполнителя, paywall'ы, кнопки «Откликнуться»), фоновый UPDATE
      // в БД фиксирует оплаченный период до now()+30d.
      VerificationStatus.hasSubscription = true;
      final DateTime paidUntil =
          DateTime.now().add(const Duration(days: 30));
      // ignore: discarded_futures
      ProfileService.instance
          .updateSubscription(paidUntil: paidUntil, autoRenew: true)
          .catchError((_) {/* silent */});
    }
  }

  PaymentResult get result => widget.result;

  @override
  Widget build(BuildContext context) {
    final bool ok = result == PaymentResult.success;
    final String title = ok ? 'Оплата прошла' : 'Не удалось оплатить';
    final String subtitle = ok
        ? 'Подписка активирована. Заказы доступны.'
        : 'Проверьте данные карты и попробуйте ещё раз.';
    final IconData icon =
        ok ? Icons.check_circle_rounded : Icons.error_rounded;
    final Color iconColor = ok ? AppColors.success : AppColors.error;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textPrimary),
                  onPressed: () => Navigator.of(context)
                      .popUntil((Route<dynamic> r) => r.isFirst),
                ),
              ),
              const Spacer(),
              Container(
                width: 120.r,
                height: 120.r,
                decoration: BoxDecoration(
                  color: ok
                      ? AppColors.primaryTint
                      : AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 64.r),
              ),
              SizedBox(height: AppSpacing.xl),
              Text(title,
                  style: AppTextStyles.h3, textAlign: TextAlign.center),
              SizedBox(height: AppSpacing.sm),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMRegular
                    .copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              PrimaryButton(
                label: ok ? 'Готово' : 'Попробовать снова',
                onPressed: () {
                  if (ok) {
                    Navigator.of(context)
                        .popUntil((Route<dynamic> r) => r.isFirst);
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Экран «Способ оплаты» — нижняя карточка поверх фотографии.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, this.cardLast4});

  /// Если карта уже выбрана снаружи (например, при возврате из
  /// `/subscription/card`) — её последние 4 цифры приходят сюда. Иначе
  /// state-screen откроет добавление карты сам.
  final String? cardLast4;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String? _cardLast4;

  @override
  void initState() {
    super.initState();
    _cardLast4 = widget.cardLast4;
  }

  Future<void> _onAddCard() async {
    final String? last4 = await context.push<String>('/subscription/card');
    if (last4 != null && last4.isNotEmpty && mounted) {
      setState(() => _cardLast4 = last4);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/catalog/subscription_bg.webp',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(color: AppColors.textTertiary),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _PaymentSheet(
              cardLast4: _cardLast4,
              onAddCard: _onAddCard,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentSheet extends StatelessWidget {
  const _PaymentSheet({required this.cardLast4, required this.onAddCard});
  final String? cardLast4;
  final VoidCallback onAddCard;

  @override
  Widget build(BuildContext context) {
    final bool hasCard = cardLast4 != null;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      padding: EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.md,
          AppSpacing.screenH, AppSpacing.md),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Способ оплаты',
                      style: AppTextStyles.titleL
                          .copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Icon(Icons.close_rounded,
                      size: 22.r, color: AppColors.textSecondary),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.sm),
            Divider(height: 1.h, color: AppColors.divider),
            SizedBox(height: AppSpacing.md),
            if (hasCard)
              Row(
                children: [
                  Icon(Icons.radio_button_checked,
                      color: AppColors.primary, size: 22.r),
                  SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Оплата картой',
                          style: AppTextStyles.bodyMedium),
                      Text('•••• $cardLast4',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textTertiary)),
                    ],
                  ),
                ],
              )
            else
              GestureDetector(
                onTap: onAddCard,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Container(
                      width: 32.r,
                      height: 24.r,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.add_rounded,
                          size: 16.r, color: Colors.white),
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Text('Добавить карту', style: AppTextStyles.bodyMedium),
                  ],
                ),
              ),
            SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Оплатить',
              enabled: hasCard,
              onPressed: () => context.push('/subscription/payment/result'),
            ),
          ],
        ),
      ),
    );
  }
}

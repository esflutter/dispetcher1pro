import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/settings/settings_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Paywall: единственный тариф с trial-периодом.
/// Поверх фоновой фотографии (handshake) показывается белая карточка
/// с заголовком, преимуществами и кнопкой «Продолжить».
class TariffsScreen extends StatelessWidget {
  const TariffsScreen({super.key, this.variant = TariffsVariant.orders});

  final TariffsVariant variant;

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
            child: _TariffsSheet(variant: variant),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8.h,
            right: 16.w,
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 32.r,
                height: 32.r,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.close_rounded,
                    size: 20.r, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Вариант paywall экрана.
enum TariffsVariant {
  /// «Получите доступ к заказам» — стартовая подписка.
  orders,

  /// «Оплатите размещение услуги» — платное размещение услуги.
  service,

  /// «Оплатите размещение карточки исполнителя» — платное размещение карточки.
  executorCard,
}

class _TariffsSheet extends StatefulWidget {
  const _TariffsSheet({required this.variant});
  final TariffsVariant variant;

  @override
  State<_TariffsSheet> createState() => _TariffsSheetState();
}

class _TariffsSheetState extends State<_TariffsSheet> {
  int? _subscriptionPrice;
  int? _slotPrice;

  /// Длительность бесплатного триала. Показывается в paywall'ах
  /// «Получите доступ к заказам» и «Оплатите размещение карточки
  /// исполнителя» как «N дней бесплатно, затем …».
  static const int _trialDays = 30;

  static const _ordersBullets = [
    'Откликайтесь на заказы',
    'Попадайте в список исполнителей',
    'Получайте новые заявки',
  ];

  @override
  void initState() {
    super.initState();
    _loadPrices();
  }

  Future<void> _loadPrices() async {
    try {
      final int sub = await SettingsService.instance.subscriptionMonthlyPriceRub();
      final int slot = await SettingsService.instance.serviceSlotPriceRub();
      if (!mounted) return;
      setState(() {
        _subscriptionPrice = sub;
        _slotPrice = slot;
      });
    } catch (_) {/* fallback на placeholder N ₽ */}
  }

  String _fmtPrice(int? v) {
    if (v == null) return 'N';
    final String s = v.toString();
    final StringBuffer b = StringBuffer();
    for (int k = 0; k < s.length; k++) {
      if (k > 0 && (s.length - k) % 3 == 0) b.write(' ');
      b.write(s[k]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final String title;
    final String description;
    final String priceLabel;
    final List<String>? bullets;
    final TariffsVariant variant = widget.variant;

    switch (variant) {
      case TariffsVariant.orders:
        title = 'Получите доступ к\nзаказам';
        description = '';
        priceLabel =
            '$_trialDays дней бесплатно, затем ${_fmtPrice(_subscriptionPrice)} ₽/месяц';
        bullets = _ordersBullets;
      case TariffsVariant.service:
        title = 'Оплатите размещение\nуслуги';
        description =
            'После оплаты ваша услуга появится в\nкаталоге, и заказчики смогут выбрать вас';
        priceLabel = '${_fmtPrice(_slotPrice)} ₽ за услугу';
        bullets = null;
      case TariffsVariant.executorCard:
        title = 'Оплатите размещение\nкарточки исполнителя';
        description =
            'После оплаты ваша карточка появится в\nкаталоге, и заказчики смогут выбрать вас';
        priceLabel =
            '$_trialDays дней бесплатно, затем ${_fmtPrice(_subscriptionPrice)} ₽/месяц';
        bullets = null;
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.lg,
        AppSpacing.screenH,
        AppSpacing.md,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: AppTextStyles.h2.copyWith(color: AppColors.textBlack),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppSpacing.md),
            if (bullets != null)
              Column(
                children: bullets
                    .map((b) => Padding(
                          padding: EdgeInsets.only(bottom: 4.h),
                          child: Text(
                            b,
                            style: AppTextStyles.body
                                .copyWith(color: AppColors.textPrimary),
                            textAlign: TextAlign.center,
                          ),
                        ))
                    .toList(),
              )
            else if (description.isNotEmpty)
              Text(
                description,
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            SizedBox(height: AppSpacing.lg),
            Text(
              priceLabel,
              style: AppTextStyles.subBody
                  .copyWith(color: AppColors.textMuted),
            ),
            SizedBox(height: AppSpacing.xs),
            PrimaryButton(
              label: 'Продолжить',
              onPressed: () => context.push('/subscription/payment'),
            ),
            SizedBox(height: AppSpacing.md),
            const _Footer(),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 10.sp,
      fontWeight: FontWeight.w500,
      color: AppColors.iosGrey,
    );
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Условия использования', style: style),
            SizedBox(width: 8.w),
            Text('•', style: style),
            SizedBox(width: 8.w),
            Text('Политика конфиденциальности', style: style),
          ],
        ),
        SizedBox(height: 2.h),
        Text('Восстановить покупки', style: style),
      ],
    );
  }
}

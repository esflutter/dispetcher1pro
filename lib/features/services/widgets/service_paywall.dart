import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/settings/settings_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/subscription/widgets/payment_method_card.dart';
import 'package:dispatcher_1/core/utils/legal_links.dart';

/// Paywall оплаты размещения услуги. Структура та же, что у
/// [SubscriptionPaywall] и [ExecutorCardPaywall]: фон + переход
/// маркетинговой карточки в шторку выбора способа оплаты.
///
/// Для оплаты использует `PaymentKind.serviceSlot` и `serviceId` —
/// после успеха триггер `apply_payment_success` ставит
/// `services.is_paid = true`, услуга появляется в каталоге.
class ServicePaywall extends StatefulWidget {
  const ServicePaywall({super.key, required this.serviceId});

  final String serviceId;

  @override
  State<ServicePaywall> createState() => _ServicePaywallState();
}

class _ServicePaywallState extends State<ServicePaywall>
    with SingleTickerProviderStateMixin {
  bool _showPayment = false;
  late final AnimationController _anim;
  late final Animation<double> _slideUp;
  late final Animation<double> _fadeOut;
  int? _priceRub;
  bool _loadingPrice = true;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideUp = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _fadeOut = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _anim, curve: const Interval(0.9, 1.0)));
    _loadPrice();
  }

  Future<void> _loadPrice({bool forceSettingsReload = false}) async {
    if (mounted) setState(() => _loadingPrice = true);
    int? price;
    try {
      if (forceSettingsReload) await SettingsService.instance.reload();
      price = await SettingsService.instance.serviceSlotPriceRub();
    } catch (_) {
      /* цена остаётся неизвестной */
    }
    if (!mounted) return;
    setState(() {
      _priceRub = price;
      _loadingPrice = false;
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _onContinue() {
    if (_priceRub == null) return;
    setState(() => _showPayment = true);
    _anim.forward();
  }

  String _fmtPrice(int v) {
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
    final double cardHeight = MediaQuery.of(context).size.height * 0.47;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: cardHeight - 24.r,
            child: Image.asset(
              'assets/images/catalog/subscription_bg.webp',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12.h,
            right: 10.w,
            child: SizedBox(
              width: 44.r,
              height: 44.r,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.close, color: Colors.white, size: 22.r),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _showPayment
                ? FadeTransition(
                    opacity: _fadeOut,
                    child: _buildPaywall(context),
                  )
                : _buildPaywall(context),
          ),
          if (_showPayment)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ListenableBuilder(
                listenable: _anim,
                builder: (BuildContext _, Widget? child) {
                  return Transform.translate(
                    offset: Offset(0, _slideUp.value * cardHeight),
                    child: child,
                  );
                },
                child: PaymentMethodCard(
                  kind: PaymentKind.serviceSlot,
                  amount: _priceRub,
                  serviceId: widget.serviceId,
                  // После успешной оплаты слота юзер должен вернуться
                  // в «Мои услуги» — там его новая услуга появится
                  // как is_paid=true (триггер apply_payment_success).
                  returnPath: '/services',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPaywall(BuildContext context) {
    return Container(
      key: const ValueKey('paywall'),
      height: MediaQuery.of(context).size.height * 0.47,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      padding: EdgeInsets.fromLTRB(
        16.w,
        24.h,
        16.w,
        12.h + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        children: <Widget>[
          Text(
            'Оплатите размещение\nуслуги',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 28.sp,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          SizedBox(height: 13.h),
          Text(
            'После оплаты ваша услуга появится в каталоге, и заказчики смогут выбрать вас',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16.sp,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            _priceRub == null
                ? 'Стоимость уточняется'
                : '${_fmtPrice(_priceRub!)} ₽ за услугу',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.textGreyMuted,
            ),
          ),
          SizedBox(height: 12.h),
          PrimaryButton(
            label: _priceRub != null
                ? 'Продолжить'
                : _loadingPrice
                ? 'Стоимость загружается…'
                : 'Повторить загрузку',
            enabled: _priceRub != null || !_loadingPrice,
            onPressed: _priceRub != null
                ? _onContinue
                : () => _loadPrice(forceSettingsReload: true),
          ),
          SizedBox(height: 12.h),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              GestureDetector(
                onTap: () => openTermsUrl(context),
                child: Text(
                  'Условия использования',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textTertiary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              Text(
                '  •  ',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 10.sp,
                  color: AppColors.textTertiary,
                ),
              ),
              GestureDetector(
                onTap: () => openPrivacyUrl(context),
                child: Text(
                  'Политика конфиденциальности',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textTertiary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

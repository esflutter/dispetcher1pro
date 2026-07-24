import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/settings/settings_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/subscription/widgets/payment_method_card.dart';
import 'package:dispatcher_1/core/utils/legal_links.dart';

/// Paywall для оплаты размещения карточки исполнителя. Структурно
/// идентичен [SubscriptionPaywall] (фон + AnimatedSwitcher между
/// маркетинговой карточкой и шторкой выбора способа оплаты), но с
/// другим заголовком и описанием.
///
/// Платёж — подписка: по дизайну у нас всего ДВЕ оплаты — подписка и слот
/// услуги. Карточка исполнителя гейтится через
/// `profiles_private.subscription_paid_until`.
///
/// Триал выровнен с каталожным [SubscriptionPaywall]: новичку (триал ещё не
/// использован) даём card_binding 1 ₽ + 30 дней бесплатно, вернувшемуся —
/// прямую оплату подписки. Раньше этот экран ВСЕГДА брал полную цену, и
/// пробный период зависел от того, с какого экрана юзер дошёл до оплаты.
class ExecutorCardPaywall extends StatefulWidget {
  const ExecutorCardPaywall({super.key});

  @override
  State<ExecutorCardPaywall> createState() => _ExecutorCardPaywallState();
}

class _ExecutorCardPaywallState extends State<ExecutorCardPaywall>
    with SingleTickerProviderStateMixin {
  bool _showPayment = false;
  late final AnimationController _anim;
  late final Animation<double> _slideUp;
  late final Animation<double> _fadeOut;
  int? _priceRub;

  /// Триал уже использован — берём прямую оплату подписки, без «30 дней
  /// бесплатно». По умолчанию false (новый юзер).
  bool? _trialUsed;
  bool _loadingSetup = true;

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
    _loadSetup();
  }

  Future<void> _loadSetup({bool forceSettingsReload = false}) async {
    if (mounted) setState(() => _loadingSetup = true);
    int? price;
    bool? trialUsed;
    try {
      if (forceSettingsReload) await SettingsService.instance.reload();
      price = await SettingsService.instance.subscriptionMonthlyPriceRub();
    } catch (_) {
      /* цена остаётся неизвестной */
    }
    try {
      final MyPrivate? priv = await ProfileService.instance.loadMyPrivate();
      trialUsed = priv?.subscriptionTrialUsed;
    } catch (_) {
      /* право на триал остаётся неизвестным */
    }
    if (!mounted) return;
    setState(() {
      _priceRub = price;
      _trialUsed = trialUsed;
      _loadingSetup = false;
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _onContinue() {
    if (_priceRub == null || _trialUsed == null) return;
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
    final bool trialUsed = _trialUsed ?? false;
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
                  // Новичок (триал не использован): card_binding 1 ₽ +
                  // активация 30-дневного триала — как в каталожном
                  // пейволле. Вернувшийся: прямая оплата подписки.
                  kind: trialUsed
                      ? PaymentKind.subscription
                      : PaymentKind.cardBinding,
                  amount: trialUsed ? _priceRub : 1,
                  renewalAmount: _priceRub,
                  activateTrial: !trialUsed,
                  // После оплаты из контекста «Открыть карточку исполнителя»
                  // возвращаем именно туда, а не на /shell — юзер только что
                  // хотел отредактировать карточку, подписка теперь активна.
                  returnPath: '/executor-card',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPaywall(BuildContext context) {
    final bool ready = _priceRub != null && _trialUsed != null;
    final bool trialUsed = _trialUsed ?? false;
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
            'Оплатите размещение\nкарточки исполнителя',
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
            'После оплаты ваша карточка появится в каталоге, и заказчики смогут выбрать вас',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16.sp,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            _trialUsed == null
                ? 'Условия подписки уточняются'
                : _priceRub == null
                ? 'Стоимость подписки уточняется'
                : trialUsed
                ? '${_fmtPrice(_priceRub!)} ₽/месяц с авто-продлением'
                : '30 дней бесплатно, затем ${_fmtPrice(_priceRub!)} ₽/месяц',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.textGreyMuted,
            ),
          ),
          SizedBox(height: 12.h),
          PrimaryButton(
            label: ready
                ? 'Продолжить'
                : _loadingSetup
                ? 'Данные загружаются…'
                : 'Повторить загрузку',
            enabled: ready || !_loadingSetup,
            onPressed: ready
                ? _onContinue
                : () => _loadSetup(forceSettingsReload: true),
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

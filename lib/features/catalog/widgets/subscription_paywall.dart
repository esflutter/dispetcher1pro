import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/settings/settings_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/subscription/widgets/payment_method_card.dart';

/// Paywall подписки. Структура эталона: фон с рукопожатием на весь
/// экран, нижняя карточка с маркетинговым текстом и кнопкой
/// «Продолжить». При нажатии «Продолжить» карточка плавно уезжает
/// (fade-out на последних 10% анимации), на её место выезжает
/// шторка `PaymentMethodCard` (slide-up). Картинка остаётся на месте.
///
/// Закрытие — крестик сверху-справа (на картинке) или внутри шторки —
/// `Navigator.pop()`. После успешной оплаты юзер уходит на
/// `payment_result_screen`, тот заменяет стек на `/shell`, и paywall
/// размонтируется заодно.
class SubscriptionPaywall extends StatefulWidget {
  const SubscriptionPaywall({super.key});

  @override
  State<SubscriptionPaywall> createState() => _SubscriptionPaywallState();
}

class _SubscriptionPaywallState extends State<SubscriptionPaywall>
    with SingleTickerProviderStateMixin {
  bool _showPayment = false;
  late final AnimationController _anim;
  late final Animation<double> _slideUp;
  late final Animation<double> _fadeOut;
  int? _priceRub;

  /// Триал уже использован — paywall открыт повторно (юзер удалил карту
  /// и теперь привязывает новую, или подписка истекла). На webhook'е
  /// второй триал не выдаётся; здесь меняем тексты, чтобы не врать
  /// пользователю про «30 дней бесплатно».
  bool _trialUsed = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _slideUp = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _anim, curve: const Interval(0.9, 1.0)),
    );
    _loadPrice();
    _loadTrialState();
  }

  Future<void> _loadPrice() async {
    try {
      final int p =
          await SettingsService.instance.subscriptionMonthlyPriceRub();
      if (!mounted) return;
      setState(() => _priceRub = p);
    } catch (_) {/* fallback в build */}
  }

  Future<void> _loadTrialState() async {
    try {
      final MyPrivate? priv = await ProfileService.instance.loadMyPrivate();
      if (!mounted || priv == null) return;
      setState(() => _trialUsed = priv.subscriptionTrialUsed);
    } catch (_) {/* по умолчанию trial_used=false (новый юзер) */}
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _onContinue() {
    setState(() => _showPayment = true);
    _anim.forward();
  }

  @override
  Widget build(BuildContext context) {
    final double cardHeight = MediaQuery.of(context).size.height * 0.47;
    return Scaffold(
      // Явный фон, чтобы edge-to-edge на Android 15+ не показывал чёрную
      // полосу под нав-баром. Сам контент рисуется поверх через Stack.
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
            // 44×44 — минимум touch-target. Раньше hit-area = иконка
            // 22dp, пальцем попадать было сложно.
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
          // Маркетинговая карточка — рисуется всегда; в режиме _showPayment
          // — с FadeTransition, чтобы за счёт fadeOut стать невидимой к
          // концу анимации (под наезжающей шторкой её всё равно не видно,
          // но fadeOut снимает edge-case с просвечиванием через
          // полупрозрачные углы шторки).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _showPayment
                ? FadeTransition(
                    opacity: _fadeOut, child: _buildPaywall(context))
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
                  // Активация триала идёт через card_binding (1 ₽ + рефанд):
                  // юзер привязывает карту, webhook ставит paid_until=now+30d
                  // и trial_used=true, через 30 дней cron снимет 1 000 ₽
                  // с этой карты автоматически. См. activateTrial в
                  // payment_method_card.dart и webhook activateTrial().
                  kind: PaymentKind.cardBinding,
                  amount: 1,
                  activateTrial: true,
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
          16.w, 24.h, 16.w, 12.h + MediaQuery.of(context).padding.bottom),
      child: Column(
        children: <Widget>[
          Text(
            _trialUsed
                ? 'Привяжите карту, чтобы\nпродолжить подписку'
                : 'Получите доступ к\nзаказам',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 28.sp,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          SizedBox(height: 13.h),
          const _BulletItem(text: 'Откликайтесь на заказы'),
          const _BulletItem(text: 'Попадайте в список исполнителей'),
          const _BulletItem(text: 'Получайте новые заявки'),
          SizedBox(height: 20.h),
          Text(
            _priceRub == null
                ? 'Стоимость подписки уточняется'
                : _trialUsed
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
          PrimaryButton(label: 'Продолжить', onPressed: _onContinue),
          SizedBox(height: 12.h),
          Text(
            'Условия использования  •  Политика конфиденциальности',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 10.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
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
}

class _BulletItem extends StatelessWidget {
  const _BulletItem({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          text,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 16.sp,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

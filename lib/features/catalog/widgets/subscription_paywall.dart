import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/settings/settings_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Маркетинговый paywall: фоновое фото + карточка с буллетами и
/// кнопкой «Продолжить». Кнопка закрывает paywall и уводит в реальный
/// экран оплаты подписки (`/subscription/payment`). Оплата идёт через
/// YooKassa Edge Function, сюда юзер уже не возвращается.
class SubscriptionPaywall extends StatefulWidget {
  const SubscriptionPaywall({super.key});

  @override
  State<SubscriptionPaywall> createState() => _SubscriptionPaywallState();
}

class _SubscriptionPaywallState extends State<SubscriptionPaywall> {
  int? _priceRub;

  @override
  void initState() {
    super.initState();
    _loadPrice();
  }

  Future<void> _loadPrice() async {
    try {
      final int p = await SettingsService.instance.subscriptionMonthlyPriceRub();
      if (!mounted) return;
      setState(() => _priceRub = p);
    } catch (_) {/* fallback в build */}
  }

  void _onContinue(BuildContext context) {
    final GoRouter router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/subscription/payment');
  }

  @override
  Widget build(BuildContext context) {
    final double cardHeight = MediaQuery.of(context).size.height * 0.47;
    return Scaffold(
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
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(Icons.close, color: Colors.white, size: 22.r),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _PaywallCard(
              priceRub: _priceRub,
              onContinue: () => _onContinue(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaywallCard extends StatelessWidget {
  const _PaywallCard({required this.priceRub, required this.onContinue});
  final int? priceRub;
  final VoidCallback onContinue;

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
    return Container(
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
            'Получите доступ к\nзаказам',
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
            priceRub == null
                ? 'Стоимость подписки уточняется'
                : '${_fmtPrice(priceRub!)} ₽ в месяц',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.textGreyMuted,
            ),
          ),
          SizedBox(height: 12.h),
          PrimaryButton(label: 'Продолжить', onPressed: onContinue),
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
          SizedBox(height: 4.h),
          Text(
            'Восстановить покупки',
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

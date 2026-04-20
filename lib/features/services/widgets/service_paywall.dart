import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Paywall оплаты размещения услуги.
/// Точно повторяет паттерн ExecutorCardPaywall / SubscriptionPaywall:
/// фоновое фото → карточка paywall → карточка оплаты (AnimatedSwitcher).
class ServicePaywall extends StatefulWidget {
  const ServicePaywall({super.key});

  @override
  State<ServicePaywall> createState() => _ServicePaywallState();
}

class _ServicePaywallState extends State<ServicePaywall>
    with SingleTickerProviderStateMixin {
  bool _showPayment = false;
  final List<String> _cards = <String>[];
  int? _selectedIndex;
  late AnimationController _anim;
  late Animation<double> _slideUp;
  late Animation<double> _fadeOut;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _slideUp = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _anim, curve: const Interval(0.9, 1.0)),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _addCard() {
    if (_cards.length >= 30) return;
    setState(() {
      final int last4 = 1234 + _cards.length * 1111;
      _cards.add('**** ${last4.toString().padLeft(4, '0').substring(0, 4)}');
      _selectedIndex = _cards.length - 1;
    });
  }

  void _onContinue() {
    setState(() => _showPayment = true);
    _anim.forward();
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
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, _slideUp.value * cardHeight),
                    child: child,
                  );
                },
                child: _buildPayment(context),
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
      padding: EdgeInsets.fromLTRB(16.w, 24.h, 16.w,
          12.h + MediaQuery.of(context).padding.bottom),
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
            'После оплаты ваша услуга появится в\nкаталоге, и заказчики смогут выбрать вас',
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
            'N ₽ за услугу',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
          SizedBox(height: 12.h),
          PrimaryButton(
            label: 'Продолжить',
            onPressed: _onContinue,
          ),
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

  Widget _buildPayment(BuildContext context) {
    return Container(
      key: const ValueKey('payment'),
      height: MediaQuery.of(context).size.height * 0.47,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 20.h),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Center(
                    child: Text(
                      'Способ оплаты',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.close,
                      size: 22.r, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: AppColors.border),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _addCard,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    child: Row(
                      children: <Widget>[
                        Image.asset(
                          'assets/images/catalog/card_add.webp',
                          width: 28.r,
                          height: 28.r,
                        ),
                        SizedBox(width: 12.w),
                        Text(
                          'Добавить карту',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (int i = 0; i < _cards.length; i++)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selectedIndex = i),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 22.r,
                            height: 22.r,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _selectedIndex == i
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: 2,
                              ),
                            ),
                            child: _selectedIndex == i
                                ? Center(
                                    child: Container(
                                      width: 12.r,
                                      height: 12.r,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          SizedBox(width: 12.w),
                          Text(
                            _cards[i],
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                16.w, 16.h, 16.w, 16.h + MediaQuery.of(context).padding.bottom),
            child: PrimaryButton(
              label: 'Оплатить',
              onPressed: _selectedIndex != null
                  ? () => Navigator.of(context).pop(true)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

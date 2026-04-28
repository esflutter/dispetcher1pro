import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/profile/profile_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../profile/widgets/verification_badge.dart';

/// Сплеш-экран приложения «Диспетчер №1».
/// Через 1.5 секунды отправляем пользователя:
/// - на `/shell`, если есть валидная Supabase-сессия (вошедший
///   пользователь не должен снова вводить телефон при рестарте);
/// - иначе на `/onboarding`.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Пока на экране висит лого+спиннер (минимум 1.5 сек), параллельно:
  /// — определяем, есть ли валидная Supabase-сессия;
  /// — если есть, подгружаем приватную часть профиля и инициализируем
  ///   VerificationStatus (подписка/верификация). Это нужно, чтобы при
  ///   первом же тапе «Откликнуться» в каталоге paywall не открылся
  ///   ошибочно из-за свежезагруженного `hasSubscription = false`.
  Future<void> _bootstrap() async {
    final Future<void> minDelay =
        Future<void>.delayed(const Duration(milliseconds: 1500));

    Session? session;
    try {
      session = Supabase.instance.client.auth.currentSession;
    } catch (_) {
      session = null;
    }

    if (session != null) {
      try {
        final MyPrivate? priv = await ProfileService.instance.loadMyPrivate();
        final DateTime? paidUntil = priv?.subscriptionPaidUntil;
        if (paidUntil != null) {
          VerificationStatus.hasSubscription =
              paidUntil.isAfter(DateTime.now().toUtc());
          VerificationStatus.subscriptionPaidUntilText = _fmtDateRu(paidUntil);
        }
      } catch (_) {/* фоллбэк: подписку поднимет profile_screen */}
    }

    await minDelay;
    if (_disposed || !mounted) return;
    context.go(session != null ? '/shell' : '/onboarding');
  }

  static const List<String> _monthsRu = <String>[
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  String _fmtDateRu(DateTime d) {
    final DateTime local = d.toLocal();
    return '${local.day} ${_monthsRu[local.month - 1]}';
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/onboarding/splash_logo.webp',
                    width: 130.r,
                    height: 130.r,
                    fit: BoxFit.contain,
                    errorBuilder: (BuildContext _, Object _, StackTrace? _) => Icon(
                      Icons.engineering,
                      size: 80.r,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(height: 24.h),
                  Text(
                    'Диспетчер №1 PRO',
                    style: AppTextStyles.h3.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 64.h),
                child: SizedBox(
                  width: 44.r,
                  height: 44.r,
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 4.r,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

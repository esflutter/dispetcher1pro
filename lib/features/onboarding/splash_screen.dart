import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

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
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      // Supabase может быть не инициализирован, если запускаем без
      // --dart-define ключей (URL/anonKey). Тогда сессии всё равно
      // нет — отправляем на онбординг, чтобы не зависнуть на сплэше.
      Session? session;
      try {
        session = Supabase.instance.client.auth.currentSession;
      } catch (_) {
        session = null;
      }
      context.go(session != null ? '/shell' : '/onboarding');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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

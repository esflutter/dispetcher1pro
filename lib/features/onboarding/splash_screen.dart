import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bootstrap/post_login_bootstrap.dart';
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
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Пока на экране висит лого+спиннер (минимум 1.5 сек), параллельно
  /// определяем, есть ли валидная Supabase-сессия; если есть — гоняем
  /// общий post-login bootstrap (см. [runPostLoginBootstrap]), чтобы
  /// при первом тапе «Откликнуться»/«Мои услуги»/«Мой график» не
  /// показывался ошибочный попап про отсутствующую подписку/карточку.
  Future<void> _bootstrap() async {
    final Future<void> minDelay =
        Future<void>.delayed(const Duration(milliseconds: 1500));

    Session? session;
    try {
      session = Supabase.instance.client.auth.currentSession;
    } catch (_) {
      session = null;
    }

    bool needsRegistration = false;
    if (session != null) {
      // Таймаут: на «полуживой» сети (Wi-Fi подключён, но не работает)
      // bootstrap мог висеть до TCP-таймаута ОС — вечный сплеш.
      try {
        await runPostLoginBootstrap().timeout(const Duration(seconds: 12));
      } catch (_) {/* доводим до экрана — там свои заглушки */}
      // Убил приложение между SMS-кодом и регистрацией: сессия есть, а имя
      // и согласие с офертой — нет. Раньше такой юзер попадал сразу в
      // каталог и регистрация не предлагалась уже никогда (у заказчика
      // эта проверка была, у исполнителя — отсутствовала).
      try {
        final Map<String, dynamic>? row = await Supabase.instance.client
            .from('profiles')
            .select('agreement_accepted_at')
            .eq('id', session.user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 8));
        needsRegistration = row == null || row['agreement_accepted_at'] == null;
      } catch (_) {/* сеть упала — пускаем в /shell, не держим на сплеше */}
    }

    await minDelay;
    if (_disposed || !mounted) return;
    context.go(session == null
        ? '/onboarding'
        : (needsRegistration ? '/auth/registration' : '/shell'));
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
                    width: 100.r,
                    height: 100.r,
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

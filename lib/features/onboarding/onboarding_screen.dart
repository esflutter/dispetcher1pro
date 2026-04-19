import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/primary_button.dart';

class _OnbStep {
  const _OnbStep({
    required this.image,
    required this.title,
    required this.description,
  });

  final String image;
  final String title;
  final String description;
}

const List<_OnbStep> _steps = <_OnbStep>[
  _OnbStep(
    image: 'assets/images/onboarding/onb_1.webp',
    title: 'Откликайтесь на заказы',
    description: 'Предлагайте свои услуги и получайте\nпредложения от заказчиков',
  ),
  _OnbStep(
    image: 'assets/images/onboarding/onb_2.webp',
    title: 'Находите заказы рядом',
    description: 'Выбирайте подходящие заявки\nпод свою технику',
  ),
  _OnbStep(
    image: 'assets/images/onboarding/onb_3.webp',
    title: 'Работайте напрямую',
    description: 'Получайте контакты заказчика\nи договаривайтесь без посредников',
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_index < _steps.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      context.go('/auth/phone');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sHeight = MediaQuery.of(context).size.height;
    final bottomSectionHeight = sHeight * 0.445;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. Sliding Images Behind
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: bottomSectionHeight - 22.r, // Заканчивается ровно под скруглением шторки
            child: PageView.builder(
              controller: _controller,
              itemCount: _steps.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => Image.asset(
                _steps[i].image,
                fit: BoxFit.cover,
                // Центрируем по вертикали: сверху обрезается столько же,
                // сколько снизу (по линии, где заканчивается скругление
                // шторки). Даёт визуальный баланс вместо прижатия к верху.
                alignment: Alignment.center,
                errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                    Container(
                  color: AppColors.surfaceVariant,
                  alignment: Alignment.center,
                  child: Icon(Icons.image_outlined,
                      size: 80, color: AppColors.textTertiary),
                ),
              ),
            ),
          ),
          
          // 2. Static White Card at bottom
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: bottomSectionHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22.r)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    SizedBox(height: 42.h),
                    
                    // Animated Text Container (Swipe Sync Parallax)
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        double page =
                            _controller.hasClients ? (_controller.page ?? _index.toDouble()) : _index.toDouble();

                        return Stack(
                          alignment: Alignment.topCenter,
                          children: List.generate(_steps.length, (i) {
                            double offset = page - i;
                            double opacity = (1 - offset.abs()).clamp(0.0, 1.0);

                            if (opacity == 0) return const SizedBox.shrink();

                            double translateX = -offset * MediaQuery.of(context).size.width * 0.6;

                            return Transform.translate(
                              offset: Offset(translateX, 0),
                              child: Opacity(
                                opacity: opacity,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                                      child: Text(
                                        _steps[i].title,
                                        style: AppTextStyles.h2.copyWith(
                                          fontSize: 24.sp,
                                          color: AppColors.textBlack,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(height: 11.h),
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                                      child: Text(
                                        _steps[i].description,
                                        style: AppTextStyles.body.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        );
                      },
                    ),

                    const Spacer(),

                    // Indicator
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBE4C6).withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(100.r),
                      ),
                      child: SmoothPageIndicator(
                        controller: _controller,
                        count: _steps.length,
                        effect: SlideEffect(
                          dotHeight: 8.r,
                          dotWidth: 8.r,
                          spacing: 8.w,
                          activeDotColor: const Color(0xFFFFAC26),
                          dotColor: const Color(0xFFFFAC26).withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    SizedBox(height: 19.h),

                    // Button
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: PrimaryButton(
                        label: 'Далее',
                        onPressed: _onNext,
                      ),
                    ),
                    SizedBox(height: 51.h), // Bottom padding
                  ],
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }
}

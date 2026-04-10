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
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Sliding content (Images + Text Cards)
          PageView.builder(
            controller: _controller,
            itemCount: _steps.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => _OnbPage(step: _steps[i], screenHeight: sHeight),
          ),
          
          // TODO: временная кнопка для быстрого перехода в каталог.
          Positioned(
            top: MediaQuery.of(context).padding.top + 8.h,
            right: 12.w,
            child: GestureDetector(
              onTap: () => context.go('/shell'),
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(100.r),
                ),
                child: Text(
                  'В каталог →',
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          // Static content on top (Indicator + Button)
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: sHeight * 0.445, // 46% exactly
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
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

class _OnbPage extends StatelessWidget {
  const _OnbPage({required this.step, required this.screenHeight});

  final _OnbStep step;
  final double screenHeight;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Full bleed image behind the status bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: screenHeight * 0.445 - 22.r, // Заканчивается ровно под скруглением шторки
          child: Image.asset(
            step.image,
            fit: BoxFit.cover,
            errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                Container(
              color: AppColors.surfaceVariant,
              alignment: Alignment.center,
              child: Icon(Icons.image_outlined,
                  size: 80, color: AppColors.textTertiary),
            ),
          ),
        ),
        // Overlapping bottom white card
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: screenHeight * 0.445,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22.r)),
            ),
            padding: EdgeInsets.only(top: 42.h, left: 16.w, right: 16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  step.title,
                  style: AppTextStyles.h2.copyWith(
                    fontSize: 24.sp,
                    color: AppColors.textBlack,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 11.h),
                Text(
                  step.description,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

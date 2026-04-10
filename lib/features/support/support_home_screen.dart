import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';

/// Стартовый экран ИИ-ассистента: «С чего хотите начать?».
/// Поле «Задать вопрос», два жёлтых action-chip'а и «Пропустить».
class SupportHomeScreen extends StatelessWidget {
  const SupportHomeScreen({super.key});

  void _openChat(BuildContext context, {String? initialMessage}) {
    final extra = initialMessage == null ? null : {'initial': initialMessage};
    GoRouter.of(context).push('/assistant/chat', extra: extra);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 16.h),
              Text(
                'С чего хотите начать?',
                style: AppTextStyles.h1Phone.copyWith(color: AppColors.textBlack),
              ),
              SizedBox(height: 16.h),
              Text(
                'Задайте вопрос или выберите тему\nиз предложенных',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textBlack,
                  fontSize: 16.sp,
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: _AskQuestionField(onTap: () => _openChat(context)),
                    ),
                    SizedBox(height: 24.h),
                    _ActionChip(
                      label: 'Разместить услугу',
                      onTap: () => _openChat(context, initialMessage: 'Разместить услугу'),
                    ),
                    SizedBox(height: 8.h),
                    _ActionChip(
                      label: 'Создать карточку исполнителя',
                      onTap: () => _openChat(context, initialMessage: 'Создать карточку исполнителя'),
                    ),
                  ],
                ),
              ),
              Center(
                child: GestureDetector(
                  onTap: () {
                    // Экран ассистента пушится поверх MainShell обычным
                    // Navigator.push (см. main_shell.dart), поэтому
                    // «Пропустить» — это просто закрытие текущего роута.
                    // context.go('/shell') здесь не сработал бы: go_router
                    // переключается под этим MaterialPageRoute, и визуально
                    // ничего не меняется.
                    final NavigatorState nav = Navigator.of(context);
                    if (nav.canPop()) {
                      nav.pop();
                    } else {
                      context.go('/shell');
                    }
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 24.w),
                    child: Text(
                      'Пропустить',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textBlack,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
            ],
          ),
        ),
      ),
    );
  }
}

class _AskQuestionField extends StatelessWidget {
  const _AskQuestionField({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64.h,
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 8.w, 8.h),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: AppColors.primary, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Задать вопрос',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textBlack,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              width: 48.w,
              height: 48.w,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8.r),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.arrow_forward, color: Colors.white, size: 22.r),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8.r),
          child: Container(
            height: 36.h,
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(
                color: Colors.white,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

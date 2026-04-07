import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Paywall: единственный тариф с trial-периодом.
/// Точная вёрстка из Figma — заголовок, буллеты, кнопка, ссылки внизу.
class TariffsScreen extends StatelessWidget {
  const TariffsScreen({super.key});

  static const _bullets = [
    'Откликайтесь на заказы',
    'Попадайте в список исполнителей',
    'Получайте новые заявки',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF929292),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(color: const Color(0xFF929292)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.lg,
                AppSpacing.screenH,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Получите доступ к заказам',
                    style: AppTextStyles.h2.copyWith(color: AppColors.textBlack),
                  ),
                  SizedBox(height: AppSpacing.md),
                  for (final b in _bullets) ...[
                    Text(b,
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.textPrimary)),
                    SizedBox(height: 4.h),
                  ],
                  SizedBox(height: AppSpacing.lg),
                  Center(
                    child: Text(
                      'N дней бесплатно, затем N ₽/месяц',
                      style: AppTextStyles.subBody
                          .copyWith(color: const Color(0xFF636362)),
                    ),
                  ),
                  SizedBox(height: AppSpacing.xs),
                  PrimaryButton(
                    label: 'Продолжить',
                    onPressed: () => context.push('/subscription/card'),
                  ),
                  SizedBox(height: AppSpacing.md),
                  _Footer(),
                ],
              ),
            ),
          ),
          Positioned(
            top: 50.h,
            right: 16.w,
            child: IconButton(
              icon: Icon(Icons.close_rounded,
                  size: 24.r, color: AppColors.surface),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 10.sp,
      fontWeight: FontWeight.w500,
      color: AppColors.iosGrey,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Условия использования', style: style),
        Text('Политика конфиденциальности', style: style),
        Text('Восстановить покупки', style: style),
      ],
    );
  }
}

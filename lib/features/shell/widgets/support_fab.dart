import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';

/// Канонический FAB вызова ИИ-ассистента (поддержки). Используется
/// в `MainShell` и на всех вложенных экранах — внешний вид должен
/// быть одинаковым везде.
class SupportFab extends StatelessWidget {
  const SupportFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Размер 56×56 (через .r — масштабируется ScreenUtil под любую плотность).
    // Иконка уже содержит свой оранжевый круг, поэтому FAB прозрачный
    // и без тени — иначе получается «два фаба друг поверх друга».
    return SizedBox(
      width: 56.r,
      height: 56.r,
      child: FloatingActionButton(
        onPressed: onTap,
        backgroundColor: Colors.transparent,
        elevation: 0,
        highlightElevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        disabledElevation: 0,
        shape: const CircleBorder(),
        child: Image.asset(
          'assets/icons/nav/support_fab.webp',
          width: 56.r,
          height: 56.r,
          fit: BoxFit.contain,
          errorBuilder: (BuildContext _, Object _, StackTrace? _) => Icon(
              Icons.support_agent,
              color: AppColors.surface,
              size: 28.r),
        ),
      ),
    );
  }
}

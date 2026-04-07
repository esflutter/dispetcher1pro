import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'app_colors.dart';

/// Типографика «Диспетчер №1». Семейство — Roboto, веса 400/500/600/700.
/// Размеры из Figma (фрейм 375 dp), масштабирование через flutter_screenutil (.sp).
class AppTextStyles {
  AppTextStyles._();

  static const String _family = 'Roboto';

  static TextStyle _t({
    required double size,
    required FontWeight weight,
    double? height,
    double letterSpacing = 0,
    Color color = AppColors.textPrimary,
  }) =>
      TextStyle(
        fontFamily: _family,
        fontSize: size.sp,
        fontWeight: weight,
        height: height == null ? null : height / size,
        letterSpacing: letterSpacing,
        color: color,
      );

  // Display / H1 — 30
  static TextStyle get h1 => _t(size: 30, weight: FontWeight.w700, height: 41);
  static TextStyle get h1SemiBold =>
      _t(size: 30, weight: FontWeight.w600, height: 41);
  static TextStyle get h1Phone =>
      _t(size: 30, weight: FontWeight.w600, height: 38);

  // H2 — 28 (онбординг)
  static TextStyle get h2 => _t(
        size: 28,
        weight: FontWeight.w700,
        height: 32.81,
        letterSpacing: -0.112,
      );

  // H3 — 24
  static TextStyle get h3 => _t(size: 24, weight: FontWeight.w600, height: 28.125);
  static TextStyle get h3Medium =>
      _t(size: 24, weight: FontWeight.w500, height: 33.6);
  static TextStyle get h3Tight =>
      _t(size: 24, weight: FontWeight.w600, height: 28.8, letterSpacing: -0.72);

  // Title L — 20
  static TextStyle get titleL =>
      _t(size: 20, weight: FontWeight.w600, height: 28, letterSpacing: 0.2);

  // Body L — 18
  static TextStyle get bodyL =>
      _t(size: 18, weight: FontWeight.w400, height: 25.2, letterSpacing: 0.2);

  // 17
  static TextStyle get bodyMMedium =>
      _t(size: 17, weight: FontWeight.w500, height: 23.8, letterSpacing: 0.2);
  static TextStyle get bodyMRegular =>
      _t(size: 17, weight: FontWeight.w400, height: 22, letterSpacing: -0.43);
  static TextStyle get titleS =>
      _t(size: 17, weight: FontWeight.w600, height: 22, letterSpacing: -0.43);

  // 16
  static TextStyle get button =>
      _t(size: 16, weight: FontWeight.w600, height: 22.4, letterSpacing: 0.2);
  static TextStyle get body =>
      _t(size: 16, weight: FontWeight.w400, height: 22.4, letterSpacing: 0.2);
  static TextStyle get bodyMedium =>
      _t(size: 16, weight: FontWeight.w500, height: 24, letterSpacing: 0.15);
  static TextStyle get linkBold =>
      _t(size: 16, weight: FontWeight.w600, height: 20, letterSpacing: -0.4,
          color: AppColors.primary);

  // 14
  static TextStyle get tabActive =>
      _t(size: 14, weight: FontWeight.w500, height: 20, letterSpacing: 0.1);
  static TextStyle get tabInactive =>
      _t(size: 14, weight: FontWeight.w400, height: 20);
  static TextStyle get subBody =>
      _t(size: 14, weight: FontWeight.w500, height: 22, letterSpacing: -0.06);
  static TextStyle get chip =>
      _t(size: 14, weight: FontWeight.w500, height: 16.4, letterSpacing: -0.4);

  // 12
  static TextStyle get caption =>
      _t(size: 12, weight: FontWeight.w400, height: 16, color: AppColors.textSecondary);
  static TextStyle get captionBold =>
      _t(size: 12, weight: FontWeight.w600, height: 16.8);

  // 15 — resend link (Open Sans в Figma, унифицируем на Roboto)
  static TextStyle get resendLink =>
      _t(size: 15, weight: FontWeight.w400, height: 21, color: AppColors.textMuted);

  // 10
  static TextStyle get tiny =>
      _t(size: 10, weight: FontWeight.w500, height: 11.7);
}

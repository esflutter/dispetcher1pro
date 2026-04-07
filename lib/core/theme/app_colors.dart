import 'package:flutter/material.dart';

/// Палитра приложения «Диспетчер №1».
/// Восстановлена из Figma-фреймов исполнителя (опубликованных color-styles в файле нет).
class AppColors {
  AppColors._();

  // Бренд
  static const Color primary = Color(0xFFFFAC26); // оранжевый
  static const Color primaryDark = Color(0xFFC77E1F);
  static const Color primaryTint = Color(0xFFFFF9F0); // светлый бренд-фон
  static const Color fieldFill = Color(0xFFFFF9EF); // фон полей ввода
  static const Color primaryTintStrong = Color(0xFFFBE4C6);

  // Поверхности
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF2F2F2);
  static const Color surfaceMuted = Color(0xFFFAFAFA);
  static const Color categoryCard = Color(0xFFF1F1F1);
  static const Color navBarDark = Color(0xFF333333);

  // Текст
  static const Color textPrimary = Color(0xFF1D1D1D);
  static const Color textSecondary = Color(0xFF49454F);
  static const Color textTertiary = Color(0xFF929292);
  static const Color textMuted = Color(0xFF7A7A7A);
  static const Color textBlack = Color(0xFF141515);
  static const Color textHeading = Color(0xFF333333);

  // Делители / бордеры
  static const Color divider = Color(0xFFEEEEEE);
  static const Color border = Color(0xFFE2E1E1);

  // Состояния
  static const Color success = Color(0xFF05BD0B);
  static const Color error = Color(0xFFE53935);
  static const Color errorTint = Color(0xFFFDECEA);
  static const Color telegramBlue = Color(0xFF2CA9E1);
  static const Color whatsappGreen = Color(0xFF38CB10);
  static const Color warning = Color(0xFFFFAC26);

  // Рейтинг
  static const Color ratingStar = Color(0xFFFFC300);

  // Системные iOS (для статус-бара/SF-glyphs если понадобятся)
  static const Color iosBlue = Color(0xFF007AFF);
  static const Color iosLabel = Color(0xFF3C3C43);
  static const Color iosGrey = Color(0xFFAEAEB2);
}

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';
import 'system_bar_style.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.primary,
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        onError: Colors.white,
      ),
      textTheme: TextTheme(
        displayLarge: AppTextStyles.h1,
        displayMedium: AppTextStyles.h2,
        displaySmall: AppTextStyles.h3,
        titleLarge: AppTextStyles.titleL,
        titleMedium: AppTextStyles.titleS,
        bodyLarge: AppTextStyles.bodyL,
        bodyMedium: AppTextStyles.body,
        bodySmall: AppTextStyles.caption,
        labelLarge: AppTextStyles.button,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        // Подавляющее большинство шапок в приложении тёмные (navBarDark) —
        // для них нужны СВЕТЛЫЕ иконки статус-бара (часы, батарея). M3 по
        // умолчанию привязывает их к светлой теме (тёмные иконки) и они
        // сливаются с тёмной шапкой. Делаем светлые иконки дефолтом для всех
        // AppBar. ВАЖНО: это влияет только на статус-бар (верхняя проба
        // экрана); нижний системный нав-бар берётся из нижней пробы
        // (MainShell / глобальный стиль), поэтому тёмная нижняя панель в
        // shell не страдает. Светлые шапки (чат, отзыв, настройки)
        // переопределяют статус-бар на тёмные иконки у себя.
        systemOverlayStyle: dispatcherSystemBarStyle(
          statusIconBrightness: Brightness.light,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.surface,
        headerBackgroundColor: AppColors.surface,
        headerForegroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        dayShape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        dayStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        dayForegroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return AppColors.textPrimary;
          },
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return null;
          },
        ),
        todayForegroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return AppColors.primary;
          },
        ),
        todayBorder: const BorderSide(color: AppColors.primary),
        todayBackgroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return Colors.transparent;
          },
        ),
        dayOverlayColor:
            WidgetStatePropertyAll<Color>(AppColors.primary.withValues(alpha: 0.12)),
        confirmButtonStyle: ButtonStyle(
          foregroundColor:
              const WidgetStatePropertyAll<Color>(AppColors.primary),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            const TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        cancelButtonStyle: ButtonStyle(
          foregroundColor:
              const WidgetStatePropertyAll<Color>(AppColors.textSecondary),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            const TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        hourMinuteColor: AppColors.fieldFill,
        hourMinuteTextColor: AppColors.textPrimary,
        dialHandColor: AppColors.primary,
        dialBackgroundColor: AppColors.fieldFill,
        dialTextColor: AppColors.textPrimary,
        entryModeIconColor: AppColors.textTertiary,
        confirmButtonStyle: ButtonStyle(
          foregroundColor:
              const WidgetStatePropertyAll<Color>(AppColors.primary),
        ),
        cancelButtonStyle: ButtonStyle(
          foregroundColor:
              const WidgetStatePropertyAll<Color>(AppColors.textSecondary),
        ),
      ),
    );
  }
}

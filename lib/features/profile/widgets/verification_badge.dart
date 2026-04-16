import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';

/// Статус верификации профиля исполнителя. Блокировка профиля
/// (рейтинг < 2★) вынесена в отдельное состояние `AccountBlock`
/// и не присутствует в этом перечислении.
enum VerificationStatus {
  verified,
  inProgress,
  rejected,
  notVerified;

  static final ValueNotifier<VerificationStatus> _notifier =
      ValueNotifier<VerificationStatus>(VerificationStatus.notVerified);

  static VerificationStatus get current => _notifier.value;
  static set current(VerificationStatus v) => _notifier.value = v;

  /// Подписка на изменения статуса верификации.
  static ValueNotifier<VerificationStatus> get notifier => _notifier;

  /// Глобальный флаг активной подписки (до появления бэкенда).
  static bool hasSubscription = false;

  bool get isVerified => this == VerificationStatus.verified;
}

class _BadgeConfig {
  const _BadgeConfig({
    required this.label,
    required this.fg,
    required this.bg,
  });
  final String label;
  final Color fg;
  final Color bg;
}

_BadgeConfig _configFor(VerificationStatus s) {
  switch (s) {
    case VerificationStatus.verified:
      return const _BadgeConfig(
        label: 'Верификация пройдена',
        fg: Color(0xFF1F8A2D),
        bg: Color(0xFFD7F6CB),
      );
    case VerificationStatus.inProgress:
      return _BadgeConfig(
        label: 'Верификация в процессе',
        fg: const Color(0xFF1DAEDE),
        bg: const Color(0xFF1DAEDE).withValues(alpha: 0.1),
      );
    case VerificationStatus.rejected:
      return const _BadgeConfig(
        label: 'Верификация не пройдена',
        fg: AppColors.error,
        bg: Color(0xFFFCE1E1),
      );
    case VerificationStatus.notVerified:
      return const _BadgeConfig(
        label: 'Верификация не пройдена',
        fg: AppColors.error,
        bg: Color(0xFFFCE1E1),
      );
  }
}

/// Небольшой pill-бейдж со статусом — для компактных мест
/// (например, заголовок карточки исполнителя).
class VerificationBadge extends StatelessWidget {
  const VerificationBadge({super.key, required this.status});

  final VerificationStatus status;

  @override
  Widget build(BuildContext context) {
    final cfg = _configFor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6.h),
      decoration: BoxDecoration(
        color: cfg.bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        cfg.label,
        style: AppTextStyles.captionBold.copyWith(color: cfg.fg),
      ),
    );
  }
}

/// Полноширинный pill со статусом верификации — используется
/// на главном экране профиля и в карточке исполнителя.
class FullWidthVerificationPill extends StatelessWidget {
  const FullWidthVerificationPill({super.key, required this.status});

  final VerificationStatus status;

  @override
  Widget build(BuildContext context) {
    final cfg = _configFor(status);
    return Container(
      width: double.infinity,
      height: 25.h,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: cfg.bg,
        borderRadius: BorderRadius.circular(100.r),
      ),
      child: Text(
        cfg.label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
          height: 1.0,
          color: cfg.fg,
        ),
      ),
    );
  }
}

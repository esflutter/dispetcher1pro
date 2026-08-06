import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/settings/settings_service.dart';
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

  /// Глобальный флаг активной подписки. Реактивный — подписаться можно
  /// через [hasSubscriptionNotifier], при изменении значения все
  /// слушатели получат уведомление, даже если изменение пришло с
  /// другого экрана. Геттер/сеттер `hasSubscription` сохраняет
  /// обратную совместимость со старым кодом.
  static final ValueNotifier<bool> hasSubscriptionNotifier =
      ValueNotifier<bool>(false);

  /// ЕДИНСТВЕННАЯ точка, где решается «есть ли у исполнителя доступ».
  /// В бесплатном режиме доступ есть всегда — этого достаточно, чтобы
  /// отвалились сразу все платные гейты (отклик на заказ, подтверждение
  /// приглашения, карточка исполнителя), не трогая каждый по отдельности.
  /// Правка «по месту присвоения» тут не годится: значение проставляется
  /// внутри условия «дата оплаты не пустая», а у большинства она пустая.
  static bool get hasSubscription =>
      SettingsService.instance.freeModeCached || hasSubscriptionNotifier.value;
  static set hasSubscription(bool v) => hasSubscriptionNotifier.value = v;

  /// Дата, до которой оплачен текущий платёжный период подписки
  /// (текстом, как его выдаст бэкенд, например «15 июля»).
  /// `null` — не оплачено, платёжного «хвоста» нет.
  static final ValueNotifier<String?> subscriptionPaidUntilTextNotifier =
      ValueNotifier<String?>(null);
  static String? get subscriptionPaidUntilText =>
      subscriptionPaidUntilTextNotifier.value;
  static set subscriptionPaidUntilText(String? v) =>
      subscriptionPaidUntilTextNotifier.value = v;

  /// Сама дата `paid_until` (не текст). Нужна гейтам, чтобы отличить
  /// «подписка приостановлена, но оплаченный период ещё идёт» от
  /// «подписка полностью истекла». В первом случае показываем диалог
  /// возобновления, во втором — маркетинговый paywall. `null` — оплаты
  /// не было вовсе. Текстовое поле выше держим как есть: оно по-прежнему
  /// показывает дату в профиле даже у истёкшей подписки.
  static DateTime? subscriptionPaidUntil;

  bool get isVerified => this == VerificationStatus.verified;

  /// `true` если подписка активна ИЛИ приостановлена (переключатель
  /// выключен, но оплаченный период ещё не закончился). В обоих случаях
  /// пользователь имеет полный доступ — переключатель управляет только
  /// автосписанием.
  static bool get isSubscriptionValid =>
      hasSubscription ||
      (subscriptionPaidUntil != null &&
          subscriptionPaidUntil!.isAfter(DateTime.now()));

  /// Полный сброс состояния верификации — для logout. Возвращает к
  /// `notVerified` и выключает подписку, чтобы следующий пользователь
  /// на этом устройстве не унаследовал чужой статус.
  static void clearAuthData() {
    _notifier.value = VerificationStatus.notVerified;
    hasSubscriptionNotifier.value = false;
    subscriptionPaidUntilTextNotifier.value = null;
    subscriptionPaidUntil = null;
  }
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
        fg: AppColors.verificationSuccessFg,
        bg: AppColors.verificationSuccessBg,
      );
    case VerificationStatus.inProgress:
      return _BadgeConfig(
        label: 'Верификация в процессе',
        fg: AppColors.verificationInfoFg,
        bg: AppColors.verificationInfoFg.withValues(alpha: 0.1),
      );
    case VerificationStatus.rejected:
      return const _BadgeConfig(
        label: 'Верификация не пройдена',
        fg: AppColors.error,
        bg: AppColors.verificationErrorBg,
      );
    case VerificationStatus.notVerified:
      return const _BadgeConfig(
        label: 'Верификация не пройдена',
        fg: AppColors.error,
        bg: AppColors.verificationErrorBg,
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

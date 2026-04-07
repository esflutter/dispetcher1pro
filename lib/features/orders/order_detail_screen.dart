import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/orders/review_screen.dart';
import 'package:dispatcher_1/features/orders/widgets/order_alerts.dart';
import 'package:dispatcher_1/features/orders/widgets/order_list_card.dart';

/// Состояние экрана деталей "моего" заказа.
enum MyOrderDetailState { waiting, accepted, completed, rejected }

/// Детали моего заказа (НЕ путать с публичной карточкой из features/catalog).
class MyOrderDetailScreen extends StatelessWidget {
  const MyOrderDetailScreen({
    super.key,
    required this.state,
    this.title = 'Рытьё котлована',
    this.dateTime = '12 апр, 09:00 — 18:00',
    this.equipment = 'Экскаватор-погрузчик',
    this.workType = 'Земляные работы',
    this.address = 'г. Москва, ул. Ленина, 12',
    this.customerName = 'Иван Петров',
  });

  final MyOrderDetailState state;
  final String title;
  final String dateTime;
  final String equipment;
  final String workType;
  final String address;
  final String customerName;

  OrderCardStatus get _statusForBadge {
    switch (state) {
      case MyOrderDetailState.waiting:
        return OrderCardStatus.waiting;
      case MyOrderDetailState.accepted:
        return OrderCardStatus.accepted;
      case MyOrderDetailState.completed:
        return OrderCardStatus.completed;
      case MyOrderDetailState.rejected:
        return OrderCardStatus.rejected;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: Text(
          'Заказ',
          style: AppTextStyles.titleS.copyWith(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenH,
                  vertical: AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusPill(status: _statusForBadge),
                    SizedBox(height: AppSpacing.md),
                    Text(title, style: AppTextStyles.h3),
                    SizedBox(height: AppSpacing.md),
                    _Section(
                      title: 'Дата и время аренды',
                      child: _Line(icon: Icons.access_time_rounded, text: dateTime),
                    ),
                    _Section(
                      title: 'Адрес',
                      child: _Line(icon: Icons.location_on_outlined, text: address),
                    ),
                    _Section(
                      title: 'Требуемая спецтехника',
                      child: _Line(icon: Icons.build_rounded, text: equipment),
                    ),
                    _Section(
                      title: 'Категория работ',
                      child: _Line(icon: Icons.engineering_outlined, text: workType),
                    ),
                    _Section(
                      title: 'Заказчик',
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20.r,
                            backgroundColor: AppColors.primaryTint,
                            child: const Icon(Icons.person, color: AppColors.primary),
                          ),
                          SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              customerName,
                              style: AppTextStyles.bodyMMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.xs,
                AppSpacing.screenH,
                AppSpacing.md,
              ),
              child: _buildAction(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    switch (state) {
      case MyOrderDetailState.waiting:
        return Column(
          children: [
            PrimaryButton(
              label: 'Подтвердить',
              onPressed: () => showAcceptAlert(context),
            ),
            SizedBox(height: AppSpacing.xs),
            SecondaryButton(
              label: 'Отклонить',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Заказ отклонён'),
                    duration: Duration(seconds: 2),
                  ),
                );
                Navigator.of(context).maybePop();
              },
            ),
          ],
        );
      case MyOrderDetailState.accepted:
        return PrimaryButton(
          label: 'Свяжитесь с заказчиком',
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Звоним: $customerName'),
              duration: const Duration(seconds: 2),
            ),
          ),
        );
      case MyOrderDetailState.completed:
        return PrimaryButton(
          label: 'Оставить отзыв',
          onPressed: () => showReviewPromptSheet(
            context,
            onLeaveReview: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReviewScreen(),
                ),
              );
            },
          ),
        );
      case MyOrderDetailState.rejected:
        return SecondaryButton(label: 'Вернуться к списку', onPressed: () {
          Navigator.of(context).maybePop();
        });
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final OrderCardStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6.h),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        status.label,
        style: AppTextStyles.captionBold.copyWith(color: status.color),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
          ),
          SizedBox(height: AppSpacing.xxs),
          child,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18.r, color: AppColors.textSecondary),
        SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(text, style: AppTextStyles.body)),
      ],
    );
  }
}

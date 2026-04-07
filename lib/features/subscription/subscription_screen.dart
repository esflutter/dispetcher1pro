import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Состояние подписки.
enum SubscriptionStatus { active, paused, inactive }

/// Экран «Информация о подписке».
/// Карточка статуса + переключатель + действие.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    this.status = SubscriptionStatus.active,
  });

  final SubscriptionStatus status;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late SubscriptionStatus _status;

  @override
  void initState() {
    super.initState();
    _status = widget.status;
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
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20.r, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Информация о подписке',
          style: AppTextStyles.titleS.copyWith(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(height: AppSpacing.md),
            _ToggleRow(
              value: _status == SubscriptionStatus.active,
              onChanged: (v) => setState(() => _status =
                  v ? SubscriptionStatus.active : SubscriptionStatus.paused),
            ),
            const Divider(height: 1, color: AppColors.divider),
            SizedBox(height: AppSpacing.md),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: _StatusCard(status: _status),
            ),
            const Spacer(),
            Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.screenH, 0,
                  AppSpacing.screenH, AppSpacing.lg),
              child: PrimaryButton(
                label: _status == SubscriptionStatus.inactive
                    ? 'Оплатить подписку'
                    : 'Отключить',
                onPressed: () => context.push('/subscription/tariffs'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.screenH, vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text('Подписка', style: AppTextStyles.bodyMMedium)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF34C759),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    String title;
    String subtitle;
    switch (status) {
      case SubscriptionStatus.active:
        title = 'Подписка активна';
        subtitle = 'Бесплатный период до 15 июля';
      case SubscriptionStatus.paused:
        title = 'Подписка приостановлена';
        subtitle = 'Оплачено до 15 июля';
      case SubscriptionStatus.inactive:
        title = 'Подписка неактивна';
        subtitle =
            'Оплатите подписку, чтобы откликаться на заказы и заказчики видели ваш профиль';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.h3Medium),
        SizedBox(height: AppSpacing.xs),
        Text(subtitle,
            style: AppTextStyles.body.copyWith(color: AppColors.textPrimary)),
      ],
    );
  }
}

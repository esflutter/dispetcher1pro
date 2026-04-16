import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/core/widgets/cropped_avatar.dart';
import 'package:dispatcher_1/features/profile/account_block.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';

import 'widgets/executor_card_alerts.dart';
import 'widgets/executor_card_paywall.dart';

enum ExecutorCardStatus { empty, inReview, rejected, verified, blocked }

class ExecutorCardScreen extends StatefulWidget {
  const ExecutorCardScreen({super.key});

  static bool cardCreated = false;

  @override
  State<ExecutorCardScreen> createState() => _ExecutorCardScreenState();
}

class _ExecutorCardScreenState extends State<ExecutorCardScreen> {
  static bool _alertShown = false;

  bool get _filled =>
      AccountBlock.isBlocked ||
      (VerificationStatus.current.isVerified &&
          VerificationStatus.hasSubscription &&
          ExecutorCardScreen.cardCreated);

  ExecutorCardStatus get _status {
    if (AccountBlock.isBlocked) return ExecutorCardStatus.blocked;
    switch (VerificationStatus.current) {
      case VerificationStatus.verified:
        return ExecutorCardScreen.cardCreated
            ? ExecutorCardStatus.verified
            : ExecutorCardStatus.empty;
      case VerificationStatus.inProgress:
        return ExecutorCardStatus.inReview;
      case VerificationStatus.rejected:
      case VerificationStatus.notVerified:
        return ExecutorCardStatus.empty;
    }
  }

  @override
  void initState() {
    super.initState();
    AccountBlock.notifier.addListener(_refresh);
    if (_status == ExecutorCardStatus.inReview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_alertShown) {
          _alertShown = true;
          showExecutorCardStatusDialog(context, _status);
        }
      });
    }
  }

  @override
  void dispose() {
    AccountBlock.notifier.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _onCreateTap() async {
    if (AccountBlock.isBlocked) {
      await showExecutorCardStatusDialog(context, ExecutorCardStatus.blocked);
      return;
    }
    if (_status == ExecutorCardStatus.inReview) {
      await showExecutorCardStatusDialog(context, _status);
      return;
    }

    if (VerificationStatus.current.isVerified) {
      if (!VerificationStatus.hasSubscription) {
        final bool? paid = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            fullscreenDialog: true,
            builder: (_) => const ExecutorCardPaywall(),
          ),
        );
        if (paid != true || !mounted) return;
        VerificationStatus.hasSubscription = true;
      }
      if (mounted) {
        await context.push('/executor-card/edit');
        if (mounted) setState(() {});
      }
      return;
    }

    await showCreateExecutorCardAlert(context);
    if (!mounted) return;

    if (_status == ExecutorCardStatus.inReview && mounted) {
      await showExecutorCardStatusDialog(context, _status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool filled = _filled;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Моя карточка исполнителя'),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 88.h),
        child: AiAssistantFab(onTap: () => context.push('/assistant/chat')),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: filled ? const _FilledCard() : _EmptyContent(status: _status),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    offset: const Offset(0, -1),
                    blurRadius: 8,
                  ),
                ],
              ),
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
              child: filled
                  ? PrimaryButton(
                      label: 'Редактировать',
                      onPressed: () async {
                        await context.push('/executor-card/edit');
                        if (mounted) setState(() {});
                      },
                    )
                  : PrimaryButton(
                      label: 'Создать',
                      onPressed: _onCreateTap,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyContent extends StatelessWidget {
  const _EmptyContent({required this.status});
  final ExecutorCardStatus status;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 22.h),
          if (VerificationStatus.current.isVerified)
            const FullWidthVerificationPill(
                status: VerificationStatus.verified),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Создайте карточку\nисполнителя',
                    style: AppTextStyles.titleL,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 6.h),
                  Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16.w),
                    child: Text(
                      'Заказчики смогут посмотреть информацию о вас, услугах и связаться с вами.',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Данные карточки исполнителя (до появления бэкенда).
class ExecutorCardData {
  static String phone = '+7 999 123-45-67';
  static String? location;
  static String? radius;
  static List<String> machinery = [];
  static List<String> categories = [];
  static String? experience;
  static String? status;
  static String? about;
}

class _FilledCard extends StatelessWidget {
  const _FilledCard();

  String _val(String? v) => (v != null && v.isNotEmpty) ? v : '—';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(),
          SizedBox(height: 20.h),
          _SectionTitle('Номер телефона'),
          SizedBox(height: 4.h),
          Text(ExecutorCardData.phone, style: AppTextStyles.body),
          SizedBox(height: 16.h),
          _SectionTitle('Местоположение'),
          SizedBox(height: 4.h),
          Text(_val(ExecutorCardData.location), style: AppTextStyles.body),
          if (ExecutorCardData.radius != null && ExecutorCardData.radius!.isNotEmpty) ...[
            SizedBox(height: 2.h),
            Text(ExecutorCardData.radius!,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textTertiary)),
          ],
          SizedBox(height: 16.h),
          _SectionTitle('Спецтехника'),
          SizedBox(height: 8.h),
          ExecutorCardData.machinery.isNotEmpty
              ? _ChipWrap(items: ExecutorCardData.machinery)
              : Text('—', style: AppTextStyles.body),
          SizedBox(height: 16.h),
          _SectionTitle('Категории услуг'),
          SizedBox(height: 8.h),
          ExecutorCardData.categories.isNotEmpty
              ? _ChipWrap(items: ExecutorCardData.categories)
              : Text('—', style: AppTextStyles.body),
          SizedBox(height: 16.h),
          _SectionTitle('Опыт работы'),
          SizedBox(height: 4.h),
          Text(_val(ExecutorCardData.experience), style: AppTextStyles.body),
          SizedBox(height: 16.h),
          _SectionTitle('Статус'),
          SizedBox(height: 4.h),
          Text(_val(ExecutorCardData.status), style: AppTextStyles.body),
          SizedBox(height: 16.h),
          _SectionTitle('О себе'),
          SizedBox(height: 4.h),
          Text(_val(ExecutorCardData.about), style: AppTextStyles.body),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        CroppedAvatar(size: 72.r),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Александр Иванов',
                  style: AppTextStyles.titleS),
              SizedBox(height: 4.h),
              Row(
                children: [
                  Image.asset('assets/images/catalog/star.webp',
                      width: 20.r, height: 20.r),
                  SizedBox(width: 4.w),
                  Text('4,5', style: AppTextStyles.body),
                  SizedBox(width: 16.w),
                  GestureDetector(
                    onTap: () => context.push('/profile/reviews'),
                    child: Text(
                      '10 отзывов',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textPrimary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTextStyles.bodyMedium
          .copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: items
          .map((label) => Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: AppColors.fieldFill,
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  label,
                  style: AppTextStyles.chip.copyWith(
                    fontSize: 13.sp,
                    color: AppColors.textPrimary,
                  ),
                ),
              ))
          .toList(),
    );
  }
}

Future<void> showExecutorCardStatusDialog(
    BuildContext context, ExecutorCardStatus status) {
  final String title;
  final String text;
  if (status == ExecutorCardStatus.inReview) {
    title = 'Ваши документы ещё\nна проверке';
    text = 'Вы получите уведомление, когда проверка завершится';
  } else if (status == ExecutorCardStatus.blocked) {
    title = 'Ваш профиль заблокирован\nна 30 дней';
    text = 'Во избежание дальнейших блокировок избегайте отзывов с низкой оценкой';
  } else {
    title = 'Документы не прошли\nпроверку';
    text = 'Проверьте данные и отправьте документы ещё раз';
  }
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 16.w),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.r, 14.r, 16.r, 22.r),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Icon(Icons.close_rounded,
                    size: 22.r, color: AppColors.textTertiary),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8.h),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMRegular
                  .copyWith(color: AppColors.textSecondary),
            ),
            SizedBox(height: 18.h),
            PrimaryButton(
              label: 'Ок',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            SizedBox(height: 12.h),
          ],
        ),
      ),
    ),
  );
}

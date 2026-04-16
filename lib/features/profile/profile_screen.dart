import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/cropped_avatar.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'account_block.dart';
import 'widgets/blocked_pill.dart';
import 'widgets/verification_badge.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.status = VerificationStatus.notVerified,
    this.fullName = 'Александр Иванов',
    this.photoUrl,
  });

  final VerificationStatus status;
  final String fullName;
  final String? photoUrl;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  VerificationStatus get _status => VerificationStatus.current;
  set _status(VerificationStatus v) => VerificationStatus.current = v;

  bool get _isBlocked => AccountBlock.isBlocked;

  @override
  void initState() {
    super.initState();
    VerificationStatus.notifier.addListener(_refresh);
    AccountBlock.notifier.addListener(_refresh);
    ReviewsData.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    VerificationStatus.notifier.removeListener(_refresh);
    AccountBlock.notifier.removeListener(_refresh);
    ReviewsData.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // TODO: убрать перед релизом — временное переключение статуса верификации.
  void _cycleStatus() {
    const List<VerificationStatus> order = <VerificationStatus>[
      VerificationStatus.notVerified,
      VerificationStatus.inProgress,
      VerificationStatus.verified,
      VerificationStatus.rejected,
    ];
    final int next = (order.indexOf(_status) + 1) % order.length;
    setState(() {
      VerificationStatus.current = order[next];
    });
  }

  Future<void> _openEdit() async {
    await context.push('/profile/edit');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final VerificationStatus status = _status;
    final String fullName = CropResult.userName;
    final double rating = ReviewsData.aggregate;
    final int reviewsCount = ReviewsData.count;
    final bool isBlocked = _isBlocked;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16.w,
        toolbarHeight: 64.h,
        title: Text(
          'Профиль',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 28.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        actions: <Widget>[
          Padding(
            padding: EdgeInsets.only(right: 8.w),
            child: IconButton(
              icon: Image.asset('assets/icons/profile/pen.webp',
                  width: 24.r, height: 24.r),
              onPressed: _openEdit,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: AppSpacing.md),
            _Header(
              fullName: fullName,
              rating: rating,
              reviewsCount: reviewsCount,
              photoUrl: widget.photoUrl,
              onReviewsTap: () => context.push('/profile/reviews'),
            ),
            SizedBox(height: 16.h),
            if (isBlocked) ...<Widget>[
              const BlockedPill(),
              SizedBox(height: 8.h),
              Text(
                'Ваш рейтинг ниже 2 звёзд, поэтому доступ\nвременно ограничен на 30 дней',
                style: AppTextStyles.subBody.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w400,
                  height: 1.3,
                ),
                textAlign: TextAlign.left,
              ),
              SizedBox(height: 16.h),
            ] else ...<Widget>[
              GestureDetector(
                onTap: _cycleStatus,
                child: FullWidthVerificationPill(status: status),
              ),
              if (status == VerificationStatus.notVerified) ...<Widget>[
                SizedBox(height: 8.h),
                _PrimaryActionButton(
                  label: 'Пройти верификацию',
                  onPressed: () async {
                    await context.push('/assistant/chat', extra: <String, Object?>{'initial': 'verify_documents'});
                    if (mounted) setState(() => _status = VerificationStatus.current);
                  },
                ),
                SizedBox(height: 20.h),
              ] else if (status == VerificationStatus.rejected) ...<Widget>[
                SizedBox(height: 8.h),
                _PrimaryActionButton(
                  label: 'Пройти ещё раз',
                  onPressed: () async {
                    await context.push('/assistant/chat', extra: <String, Object?>{'initial': 'verify_documents'});
                    if (mounted) setState(() => _status = VerificationStatus.current);
                  },
                ),
                SizedBox(height: 20.h),
              ] else
                SizedBox(height: 16.h),
            ],
            _ProfileMenuItem(
              label: 'Моя карточка исполнителя',
              onTap: () => context.push('/executor-card'),
            ),
            SizedBox(height: 16.h),
            _ProfileMenuItem(
              label: 'Мои услуги',
              onTap: () => context.push('/services'),
            ),
            SizedBox(height: 16.h),
            _ProfileMenuItem(
              label: 'Мой график',
              onTap: () => context.push('/schedule'),
            ),
            SizedBox(height: 16.h),
            _ProfileMenuItem(
              label: 'Информация о подписке',
              onTap: () => context.push('/subscription'),
            ),
            SizedBox(height: 20.h),
            const _SupportFooter(),
            SizedBox(height: 32.h),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.fullName,
    required this.rating,
    required this.reviewsCount,
    required this.photoUrl,
    required this.onReviewsTap,
  });

  final String fullName;
  final double rating;
  final int reviewsCount;
  final String? photoUrl;
  final VoidCallback onReviewsTap;

  @override
  Widget build(BuildContext context) {
    final String ratingText = reviewsCount == 0
        ? '0,0'
        : rating.toStringAsFixed(1).replaceAll('.', ',');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        CroppedAvatar(size: 72.r),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(fullName,
                  style: AppTextStyles.titleS),
              SizedBox(height: 4.h),
              GestureDetector(
                onTap: onReviewsTap,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: <Widget>[
                    Image.asset('assets/images/catalog/star.webp',
                        width: 20.r, height: 20.r),
                    SizedBox(width: 4.w),
                    Text(ratingText, style: AppTextStyles.body),
                    SizedBox(width: 16.w),
                    Text(
                      '$reviewsCount отзывов',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textPrimary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.categoryCard,
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          height: 56.h,
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(label, style: AppTextStyles.body),
              ),
              Image.asset('assets/icons/profile/arrow_right.webp',
                  width: 16.r, height: 16.r),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportFooter extends StatelessWidget {
  const _SupportFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Возникли вопросы? Напишите нам!',
            style: AppTextStyles.body.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            )),
        SizedBox(height: 8.h),
        Row(
          children: [
            Image.asset('assets/icons/profile/telegram.webp',
                width: 40.r, height: 40.r),
            SizedBox(width: 12.w),
            Image.asset('assets/icons/profile/whatsapp.webp',
                width: 40.r, height: 40.r),
          ],
        ),
      ],
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 40.h,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.r),
          ),
        ),
        child: Text(label,
            style: AppTextStyles.button.copyWith(color: Colors.white)),
      ),
    );
  }
}

Future<bool?> showLogoutAlert(BuildContext context) {
  return _showProfileAlert(
    context,
    title: 'Вы уверены, что хотите выйти?',
    actionLabel: 'Выйти',
    isDestructive: true,
  );
}

Future<bool?> showDeleteAccountAlert(BuildContext context) {
  return _showProfileAlert(
    context,
    title: 'Вы уверены, что хотите удалить аккаунт?',
    actionLabel: 'Удалить',
    isDestructive: true,
  );
}

Future<bool?> _showProfileAlert(
  BuildContext context, {
  required String title,
  required String actionLabel,
  bool isDestructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFFDFDFDF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: SizedBox(
        width: 270.w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.titleS.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Divider(height: 1, thickness: 0.5, color: Colors.grey.shade400),
            SizedBox(
              height: 44.h,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.of(ctx).pop(false),
                      child: Center(
                        child: Text('Отмена',
                            style: AppTextStyles.titleS.copyWith(
                              color: const Color(0xFF007AFF),
                            )),
                      ),
                    ),
                  ),
                  Container(width: 0.5, color: Colors.grey.shade400),
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.of(ctx).pop(true),
                      child: Center(
                        child: Text(actionLabel,
                            style: AppTextStyles.bodyMRegular.copyWith(
                              color: isDestructive ? AppColors.error : const Color(0xFF007AFF),
                            )),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

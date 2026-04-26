import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/utils/plural.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/avatar_circle.dart';
import 'package:dispatcher_1/core/widgets/cropped_avatar.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'package:dispatcher_1/features/executor_card/executor_card_screen.dart';
import 'package:dispatcher_1/features/executor_card/widgets/executor_card_alerts.dart';
import 'account_block.dart';
import 'widgets/blocked_pill.dart';
import 'widgets/verification_badge.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.status = VerificationStatus.notVerified,
    this.fullName = '',
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

  // Значения с БД — перекрывают начальные нули, когда загрузка прошла
  // успешно. До загрузки показываются нули, чтобы не моргать пустыми
  // звёздами на старте.
  double? _dbRating;
  int? _dbReviewCount;
  String? _dbAvatarUrl;

  @override
  void initState() {
    super.initState();
    VerificationStatus.notifier.addListener(_refresh);
    AccountBlock.notifier.addListener(_refresh);
    _loadFromDb();
  }

  Future<void> _loadFromDb() async {
    try {
      final MyProfile? p = await ProfileService.instance.loadMine();
      if (p == null || !mounted) return;
      CropResult.userName = p.name;
      // Синхронизируем мок-сторы с реальным состоянием в БД.
      AccountBlock.setUntil(p.blockedUntil);
      VerificationStatus.current = switch (p.verificationStatus) {
        'approved' => VerificationStatus.verified,
        'pending' => VerificationStatus.inProgress,
        'rejected' => VerificationStatus.rejected,
        _ => VerificationStatus.notVerified,
      };
      ReviewsData.setFromDb(
        rating: p.ratingAsExecutor,
        reviewCount: p.reviewCountAsExecutor,
      );
      setState(() {
        _dbRating = p.ratingAsExecutor;
        _dbReviewCount = p.reviewCountAsExecutor;
        _dbAvatarUrl = p.avatarUrl;
      });
      // Подписка лежит в profiles_private, отдельный запрос.
      final MyPrivate? priv = await ProfileService.instance.loadMyPrivate();
      if (priv == null || !mounted) return;
      // VerificationStatus.hasSubscription — мок, обновим из БД.
      final DateTime? paid = priv.subscriptionPaidUntil;
      VerificationStatus.hasSubscription =
          paid != null && paid.isAfter(DateTime.now());
      VerificationStatus.subscriptionPaidUntilText =
          paid == null ? null : _fmtPaidUntil(paid);
      if (mounted) setState(() {});
    } catch (_) {
      // Нет сети / ошибка БД — тихо, оставляем мок-значения.
    }
  }

  String _fmtPaidUntil(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  void dispose() {
    VerificationStatus.notifier.removeListener(_refresh);
    AccountBlock.notifier.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _openEdit() async {
    await context.push('/profile/edit');
    if (!mounted) return;
    // Аватар/имя могли поменяться — перетягиваем из БД, чтобы UI
    // не остался с устаревшим _dbAvatarUrl.
    await _loadFromDb();
    if (mounted) setState(() {});
  }

  /// Переход в раздел, требующий оформленной карточки исполнителя
  /// («Мой график», «Мои услуги»). Если карточка ещё не создана —
  /// показываем попап, и по подтверждению открываем экран создания.
  Future<void> _openCardGated(String path) async {
    if (ExecutorCardState.cardCreated) {
      await context.push(path);
      if (mounted) setState(() {});
      return;
    }
    final bool? create = await showExecutorCardRequiredAlert(context);
    if (create != true || !mounted) return;
    await context.push('/executor-card');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final VerificationStatus status = _status;
    final String fullName = CropResult.displayName;
    final double rating = _dbRating ?? 0.0;
    final int reviewsCount = _dbReviewCount ?? 0;
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
              avatarUrl: _dbAvatarUrl ?? widget.photoUrl,
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
              FullWidthVerificationPill(status: status),
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
              onTap: () => _openCardGated('/services'),
            ),
            SizedBox(height: 16.h),
            _ProfileMenuItem(
              label: 'Мой график',
              onTap: () => _openCardGated('/schedule'),
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
    required this.avatarUrl,
    required this.onReviewsTap,
  });

  final String fullName;
  final double rating;
  final int reviewsCount;
  final String? avatarUrl;
  final VoidCallback onReviewsTap;

  @override
  Widget build(BuildContext context) {
    final String ratingText = reviewsCount == 0
        ? '0,0'
        : rating.toStringAsFixed(1).replaceAll('.', ',');
    // Если только что выбрали новое фото в этой сессии и crop ещё в
    // памяти — показываем live-preview (cropped local file). Иначе —
    // сетевую аватарку из БД (или серый placeholder).
    final Widget avatar = CropResult.saved != null
        ? CroppedAvatar(size: 72.r)
        : AvatarCircle(size: 72.r, avatarUrl: avatarUrl);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        avatar,
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
                      '$reviewsCount ${reviewsWord(reviewsCount)}',
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
            Image.asset('assets/icons/profile/max.webp',
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
                              color: AppColors.iosBlue,
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
                              color: isDestructive ? AppColors.error : AppColors.iosBlue,
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

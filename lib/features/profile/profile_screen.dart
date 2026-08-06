import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/ai/ai_navigation.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/settings/settings_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/utils/legal_links.dart';
import 'package:dispatcher_1/core/utils/plural.dart';
import 'package:dispatcher_1/core/utils/support_contact.dart';
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

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  String? _rejectReason;

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
    // Любая правка профиля в дочерних экранах (имя/email/avatar/about/
    // status/опыт) бьёт по changeBeacon → заново тянем DB, чтобы аватар
    // и т.д. обновились без hot reload. Сюда же прилетает пуш о верификации
    // (push_handler бьёт по changeBeacon) — статус обновляется живьём, даже
    // если пользователь стоит на этом экране в момент одобрения.
    ProfileService.changeBeacon.addListener(_onProfileChanged);
    // Возврат в приложение из фона — перечитываем статус: админ мог одобрить
    // документы, пока приложение было свёрнуто. Раньше требовался полный
    // перезапуск, чтобы «Верификация в процессе» сменилась на «пройдена».
    WidgetsBinding.instance.addObserver(this);
    _loadFromDb();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadFromDb();
  }

  void _onProfileChanged() {
    if (!mounted) return;
    _loadFromDb();
  }

  Future<void> _loadFromDb() async {
    try {
      final MyProfile? p = await ProfileService.instance.loadMine();
      if (p == null || !mounted) return;
      // Не перезаписываем CropResult.userName из БД, если локально уже
      // есть значение. Иначе при возврате из EditProfileScreen мы могли
      // затереть только что введённое имя его старым значением: dispose
      // edit-экрана пишет в БД асинхронно, а наш SELECT прилетает быстрее.
      if (CropResult.userName.isEmpty) {
        CropResult.userName = p.name;
      }
      // Синхронизируем мок-сторы с реальным состоянием в БД.
      AccountBlock.setUntil(p.blockedUntil);
      // Режим «документы при каждой услуге»: верификации личности аккаунта
      // нет (доступ на сервере — по одобренной услуге). Клиент считает
      // аккаунт «пройденным», чтобы карточка/отклик не требовали её.
      // await-геттер сам дожидается/повторяет загрузку настроек — при
      // непрогретом кэше не откатываемся ложно в легаси-UI.
      final bool perService = await SettingsService.instance.perServiceDocs();
      if (!mounted) return;
      VerificationStatus.current = perService
          ? VerificationStatus.verified
          : switch (p.verificationStatus) {
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
      // Подписка + email лежат в profiles_private, отдельный запрос.
      final MyPrivate? priv = await ProfileService.instance.loadMyPrivate();
      if (priv == null || !mounted) return;
      // Причина отказа верификации: раньше показывалась только одноразовым
      // пушем — на экране юзер видел голое «не пройдена» и слал те же
      // документы повторно. Теперь причина видна прямо под плашкой.
      _rejectReason = priv.verificationRejectReason;
      // VerificationStatus.hasSubscription — мок, обновим из БД.
      // grace-aware (subscriptionActive): зеркалит серверную
      // is_subscription_active с 3-дневной форой при автопродлении —
      // единый источник с гейтами отклика/каталога.
      final DateTime? paid = priv.subscriptionPaidUntil;
      VerificationStatus.hasSubscription = priv.subscriptionActive;
      VerificationStatus.subscriptionPaidUntilText =
          paid == null ? null : _fmtPaidUntil(paid);
      VerificationStatus.subscriptionPaidUntil = paid;
      // Email — тот же сценарий, что у имени: cold start → нет в кэше
      // → берём из БД. После Hot Restart введённый ранее email пропадал
      // из «Моей карточки» / профиля, потому что `loadMyPrivate.email`
      // нигде не записывался в CropResult.userEmail.
      if (CropResult.userEmail.isEmpty &&
          priv.email != null && priv.email!.isNotEmpty) {
        CropResult.userEmail = priv.email!;
      }
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
    ProfileService.changeBeacon.removeListener(_onProfileChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // Переключение статуса верификации/блокировки по тапу убрано: и
  // верификация, и блокировки теперь управляются только на сервере
  // (админ-панель), а приложение лишь отражает статус из БД. Тап по плашке
  // статуса ничего не меняет.

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

  /// Пояснение под плашкой блокировки. Автоблок за низкий рейтинг — временный,
  /// с датой снятия. Блок администратором кодируется датой в далёком будущем
  /// (год ≥ 2090); для него «рейтинг ниже 2 звёзд» и «до 2090 года» неверны —
  /// показываем нейтральный текст с отсылкой к поддержке.
  String _blockExplanation() {
    final DateTime? until = AccountBlock.blockedUntil;
    final bool forever = until != null && until.year >= 2090;
    if (forever) {
      return 'Ваш профиль заблокирован. Если это ошибка — '
          'напишите в поддержку ниже.';
    }
    return 'Ваш рейтинг ниже 2 звёзд, поэтому доступ\nвременно ограничен '
        '${AccountBlock.blockedUntilText ?? "на 30 дней"}';
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
                _blockExplanation(),
                style: AppTextStyles.subBody.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w400,
                  height: 1.3,
                ),
                textAlign: TextAlign.left,
              ),
              SizedBox(height: 16.h),
            ] else if (SettingsService.instance.perServiceDocsCached) ...<Widget>[
              // Режим «документы при каждой услуге»: проверки личности
              // аккаунта нет — блок верификации в профиле не показываем
              // (документы прикладываются к каждой услуге в «Моих услугах»).
              SizedBox(height: 4.h),
            ] else ...<Widget>[
              FullWidthVerificationPill(status: status),
              if (status == VerificationStatus.notVerified) ...<Widget>[
                SizedBox(height: 8.h),
                _PrimaryActionButton(
                  label: 'Пройти верификацию',
                  onPressed: () async {
                    await openAssistantChat(context, extra: <String, Object?>{'initial': 'verify_documents'});
                    if (mounted) setState(() => _status = VerificationStatus.current);
                  },
                ),
                SizedBox(height: 20.h),
              ] else if (status == VerificationStatus.rejected) ...<Widget>[
                if (_rejectReason != null && _rejectReason!.trim().isNotEmpty) ...<Widget>[
                  SizedBox(height: 6.h),
                  Text(
                    'Причина: ${_rejectReason!.trim()}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 13.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                SizedBox(height: 8.h),
                _PrimaryActionButton(
                  label: 'Пройти ещё раз',
                  onPressed: () async {
                    await openAssistantChat(context, extra: <String, Object?>{'initial': 'verify_documents'});
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
            // Раздел оплаты прячем в бесплатном режиме: платить не за что,
            // а сохранённых карт быть не может — сервер не даёт их привязать.
            // Экран и маршрут остаются на месте, чтобы возврат платного
            // режима был переключением флага, а не новой сборкой.
            if (!SettingsService.instance.freeModeCached) ...<Widget>[
              SizedBox(height: 16.h),
              _ProfileMenuItem(
                label: 'Подписка и оплата',
                onTap: () => context.push('/subscription/manage'),
              ),
            ],
            SizedBox(height: 20.h),
            const _SupportFooter(),
            SizedBox(height: 24.h),
            const _LegalLinksFooter(),
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
                    // При нуле отзывов рейтинг бессмысленен — звезду и
                    // число прячем, оставляем только подчёркнутый счётчик.
                    if (reviewsCount > 0) ...<Widget>[
                      Image.asset('assets/images/catalog/star.webp',
                          width: 20.r, height: 20.r),
                      SizedBox(width: 4.w),
                      Text(ratingText, style: AppTextStyles.body),
                      SizedBox(width: 16.w),
                    ],
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
                child: Text(label,
                    style: AppTextStyles.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
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
            GestureDetector(
              onTap: () => openSupportMessenger(context),
              child: Image.asset('assets/icons/profile/max.webp',
                  width: 40.r, height: 40.r),
            ),
          ],
        ),
      ],
    );
  }
}

/// Тихие ссылки на правовые документы — сторы требуют, чтобы политика
/// была доступна из приложения, а не только на экране регистрации.
class _LegalLinksFooter extends StatelessWidget {
  const _LegalLinksFooter();

  @override
  Widget build(BuildContext context) {
    final TextStyle style = AppTextStyles.subBody.copyWith(
      color: AppColors.textSecondary,
      decoration: TextDecoration.underline,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        GestureDetector(
          onTap: () => openTermsUrl(context),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6.h),
            child: Text('Пользовательское соглашение', style: style),
          ),
        ),
        GestureDetector(
          onTap: () => openPrivacyUrl(context),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6.h),
            child: Text('Политика конфиденциальности', style: style),
          ),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
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
      backgroundColor: AppColors.dialogAlertBg,
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

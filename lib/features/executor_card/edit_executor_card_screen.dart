import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/executor_card/executor_card_service.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/storage/storage_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/email_validation.dart';
import 'package:dispatcher_1/core/utils/photo_source.dart';
import 'package:dispatcher_1/core/utils/plural.dart';
import 'package:dispatcher_1/core/widgets/avatar_circle.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/cropped_avatar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';

import 'executor_card_screen.dart';

/// Длинная форма создания / редактирования карточки исполнителя.
/// Поля из Figma: ФИО, телефон, местоположение (радиус), спецтехника,
/// категории услуг, опыт работы, статус, о себе.
class EditExecutorCardScreen extends StatefulWidget {
  const EditExecutorCardScreen({super.key, this.editing = true});

  final bool editing;

  @override
  State<EditExecutorCardScreen> createState() => _EditExecutorCardScreenState();
}

class _EditExecutorCardScreenState extends State<EditExecutorCardScreen> {
  static const int _nameMaxLen = 60;
  static const int _emailMaxLen = 50;

  late final TextEditingController _location;
  late final TextEditingController _experience;
  late final TextEditingController _about;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();

  /// Показывать ли красную подсказку под полем телефона (нельзя менять
  /// номер в карточке — только через регистрацию/техподдержку).
  bool _showPhoneHint = false;

  /// Текст ошибки под полем email. Выставляется при потере фокуса,
  /// если введённое значение не проходит валидацию регуляркой.
  String? _emailError;

  String? _selectedStatus;
  int _radiusIndex = -1;

  static const _radiusOptions = [
    'В радиусе 10 км',
    'В радиусе 20 км',
    'В радиусе 50 км',
  ];

  bool _statusExpanded = false;

  static const _statusOptions = [
    'Физ. лицо',
    'Самозанятый',
    'ИП',
    'Юр. лицо',
  ];


  @override
  void initState() {
    super.initState();
    _location = TextEditingController(text: ExecutorCardData.location ?? '');
    _experience = TextEditingController(text: ExecutorCardData.experience ?? '');
    _about = TextEditingController(text: ExecutorCardData.about ?? '');
    // Имя/email — один источник с профилем через ExecutorCardData.name
    // (геттер на CropResult.userName) и CropResult.userEmail.
    _nameCtrl = TextEditingController(text: ExecutorCardData.name);
    _emailCtrl = TextEditingController(text: CropResult.userEmail);
    _selectedStatus = ExecutorCardData.status;
    final savedRadius = ExecutorCardData.radius;
    _radiusIndex = savedRadius != null ? _radiusOptions.indexOf(savedRadius) : -1;
    if (_radiusIndex < 0) _radiusIndex = -1;

    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) {
        final String value = _nameCtrl.text.trim();
        if (value.isEmpty) {
          // Пустое имя не сохраняем — откатываем к последнему валидному.
          _nameCtrl.text = ExecutorCardData.name;
        } else {
          ExecutorCardData.name = value;
        }
      }
    });
    _emailFocus.addListener(() {
      if (_emailFocus.hasFocus) {
        // Пользователь вернулся редактировать — убираем ошибку, пока
        // не оценим снова на следующем blur.
        if (_emailError != null) {
          setState(() => _emailError = null);
        }
      } else {
        final String value = _emailCtrl.text.trim();
        final bool valid = isValidEmail(value);
        if (valid) {
          CropResult.userEmail = value;
          // Пишем в `profiles_private.email` через RPC. На уровне UI
          // оптимистично — без await: если сетевой запрос упадёт,
          // в кэше у пользователя email уже сохранён, и при выходе
          // с экрана значение всё равно попадёт в storage у
          // следующей загрузки. Edit-screen профиля делает то же.
          // ignore: discarded_futures
          ProfileService.instance
              .updatePrivateEmail(value)
              .catchError((_) {/* silent */});
          if (_emailError != null) setState(() => _emailError = null);
        } else {
          setState(() => _emailError = 'Некорректная электронная почта');
        }
      }
    });
  }

  @override
  void dispose() {
    // На случай, если пользователь ушёл со экрана, не сняв фокус.
    final String name = _nameCtrl.text.trim();
    if (name.isNotEmpty) ExecutorCardData.name = name;
    final String email = _emailCtrl.text.trim();
    if (isValidEmail(email)) {
      CropResult.userEmail = email;
    }
    _location.dispose();
    _experience.dispose();
    _about.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
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
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.md,
                    AppSpacing.screenH, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              ListenableBuilder(
                listenable: _nameCtrl,
                builder: (_, _) => _HeaderRow(displayName: _nameCtrl.text),
              ),
              SizedBox(height: 16.h),
              _PlainEditableField(
                controller: _nameCtrl,
                focusNode: _nameFocus,
                hint: 'Имя и фамилия',
                keyboardType: TextInputType.name,
                maxLength: _nameMaxLen,
              ),
              SizedBox(height: 8.h),
              _PlainEditableField(
                controller: _emailCtrl,
                focusNode: _emailFocus,
                hint: 'Электронная почта',
                keyboardType: TextInputType.emailAddress,
                maxLength: _emailMaxLen,
              ),
              if (_emailError != null) ...[
                SizedBox(height: 6.h),
                Text(
                  _emailError!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ],
              SizedBox(height: 8.h),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showPhoneHint = !_showPhoneHint),
                child: Container(
                  height: 56.h,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  decoration: BoxDecoration(
                    color: AppColors.fieldFill,
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  alignment: Alignment.centerLeft,
                  child:
                      Text(ExecutorCardData.phone, style: AppTextStyles.body),
                ),
              ),
              if (_showPhoneHint) ...[
                SizedBox(height: 6.h),
                Text(
                  'Можно использовать только номер телефона, '
                  'указанный при регистрации.',
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ],
              SizedBox(height: AppSpacing.lg),
              _SectionTitle('Местоположение'),
              SizedBox(height: 12.h),
              GestureDetector(
                onTap: () async {
                  final String? result = await showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const AddressBottomSheet(),
                  );
                  if (result != null) {
                    setState(() => _location.text = result);
                  }
                },
                child: Container(
                  height: 44.h,
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  decoration: BoxDecoration(
                    color: AppColors.fieldFill,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _location.text.isEmpty ? 'Введите адрес' : _location.text,
                          style: AppTextStyles.body.copyWith(
                            color: _location.text.isEmpty
                                ? AppColors.textTertiary
                                : AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              for (int i = 0; i < _radiusOptions.length; i++)
                _RadioRow(
                  label: _radiusOptions[i],
                  selected: _radiusIndex == i,
                  onTap: () => setState(() => _radiusIndex = i),
                ),
              // Спецтехника и категории услуг в форме редактирования
              // НЕ показываются — они полностью computed из услуг.
              // Смотрим/управляем ими через «Мои услуги», а в карточке
              // они появляются автоматически.
              SizedBox(height: AppSpacing.lg),
              _SectionTitle('Опыт работы'),
              SizedBox(height: AppSpacing.xs),
              _ExperienceField(controller: _experience),
              SizedBox(height: AppSpacing.lg),
              _SectionTitle('Статус'),
              SizedBox(height: AppSpacing.xs),
              GestureDetector(
                onTap: () => setState(() => _statusExpanded = !_statusExpanded),
                child: Container(
                  height: 54.h,
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.fieldFill,
                    borderRadius: _statusExpanded
                        ? BorderRadius.vertical(top: Radius.circular(12.r))
                        : BorderRadius.circular(AppSpacing.radiusM),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedStatus ?? 'Укажите статус',
                          style: AppTextStyles.body.copyWith(
                            color: _selectedStatus == null
                                ? AppColors.textTertiary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Image.asset(
                        _statusExpanded
                            ? 'assets/icons/ui/arrow_up.webp'
                            : 'assets/icons/ui/arrow_down.webp',
                        width: 22.r,
                        height: 22.r,
                      ),
                    ],
                  ),
                ),
              ),
              if (_statusExpanded)
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.fieldFill,
                    borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(12.r)),
                  ),
                  child: Column(
                    children: [
                      Divider(height: 1, thickness: 0.5, color: AppColors.border),
                      for (final s in _statusOptions)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() {
                            _selectedStatus = s;
                            _statusExpanded = false;
                          }),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.md, vertical: 12.h),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(s, style: AppTextStyles.body),
                                ),
                                if (_selectedStatus == s)
                                  Image.asset('assets/icons/ui/check_black.webp',
                                      width: 22.r, height: 22.r),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              SizedBox(height: AppSpacing.lg),
              _SectionTitle('О себе'),
              SizedBox(height: AppSpacing.xs),
              _TintField(
                controller: _about,
                hint: 'Расскажите о себе',
                minLines: 1,
                maxLength: 500,
                maxLines: 5,
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                'Информация о вас помогает другим лучше понять, '
                'с кем они будут работать.',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted),
              ),
                  SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
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
              child: PrimaryButton(
                label: 'Сохранить',
                onPressed: () async {
                  // Локальное обновление моковых сторов — чтобы экраны,
                  // которые ещё на них смотрят, сразу увидели новые данные.
                  ExecutorCardData.location = _location.text;
                  ExecutorCardData.radius = _radiusIndex >= 0
                      ? _radiusOptions[_radiusIndex]
                      : null;
                  ExecutorCardData.experience = _experience.text;
                  ExecutorCardData.status = _selectedStatus;
                  ExecutorCardData.about = _about.text;
                  ExecutorCardScreen.cardCreated = true;

                  // Реальный UPSERT в БД. Радиус — 10/20/50 км в int
                  // (колонка `executor_cards.radius_km`).
                  final int? radiusKm = _radiusIndex == 0
                      ? 10
                      : _radiusIndex == 1
                          ? 20
                          : _radiusIndex == 2
                              ? 50
                              : null;
                  final String? legalStatus = switch (_selectedStatus) {
                    'Физ. лицо' => 'individual',
                    'Самозанятый' => 'self_employed',
                    'ИП' => 'ip',
                    'Юр. лицо' => 'legal_entity',
                    _ => null,
                  };
                  final int? experienceYears =
                      int.tryParse(_experience.text.trim());
                  try {
                    await ExecutorCardService.instance.upsert(
                      locationAddress: _location.text.trim().isEmpty
                          ? null
                          : _location.text.trim(),
                      radiusKm: radiusKm,
                      isPublished: radiusKm != null,
                      about: _about.text.trim().isEmpty
                          ? null
                          : _about.text.trim(),
                      legalStatus: legalStatus,
                      experienceYears: experienceYears,
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Не удалось сохранить: $e')),
                    );
                    return;
                  }
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderRow extends StatefulWidget {
  const _HeaderRow({required this.displayName});

  /// Имя, которое показывать справа от аватара. Пробрасывается из
  /// родительского state, чтобы обновляться «в живую» при наборе.
  final String displayName;

  @override
  State<_HeaderRow> createState() => _HeaderRowState();
}

class _HeaderRowState extends State<_HeaderRow> {
  String? _avatarUrl;
  double _rating = 0;
  int _reviewCount = 0;

  @override
  void initState() {
    super.initState();
    _loadFromDb();
  }

  Future<void> _loadFromDb() async {
    try {
      final MyProfile? p = await ProfileService.instance.loadMine();
      if (p == null || !mounted) return;
      setState(() {
        _avatarUrl = p.avatarUrl;
        _rating = p.ratingAsExecutor;
        _reviewCount = p.reviewCountAsExecutor;
      });
    } catch (_) {/* silent */}
  }

  Future<void> _openCrop() async {
    final String? imagePath = await pickImageFromGallery(context: context);
    if (imagePath == null || !mounted) return;
    final result = await Navigator.of(context).push<CropResult>(
      MaterialPageRoute(
        builder: (_) => PhotoCropScreen(imagePath: imagePath),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => CropResult.saved = result);
    final String? path = result.imagePath;
    if (path != null && !path.startsWith('assets/')) {
      _uploadAvatar(path);
    }
  }

  /// Заливает выбранный аватар в storage `avatars` и пишет URL в
  /// `profiles.avatar_url`. Без этого аватар, выбранный в карточке
  /// исполнителя, существовал только в памяти `CropResult.saved` —
  /// после Hot Restart исчезал.
  Future<void> _uploadAvatar(String path) async {
    try {
      final String url =
          await StorageService.instance.uploadAvatar(File(path));
      await ProfileService.instance.update(avatarUrl: url);
      if (mounted) setState(() => _avatarUrl = url);
    } catch (_) {/* silent */}
  }

  String _fmtRating(double v) =>
      _reviewCount == 0 ? '0,0' : v.toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final Widget avatar = CropResult.saved != null
        ? CroppedAvatar(size: 80.r)
        : AvatarCircle(size: 80.r, avatarUrl: _avatarUrl);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _openCrop,
          child: SizedBox(
            width: 80.r,
            height: 80.r,
            child: Stack(
              children: [
                avatar,
                Positioned(
                  right: -1.w,
                  bottom: 0,
                  child: Image.asset(
                    'assets/icons/ui/edit.webp',
                    width: 21.r,
                    height: 21.r,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.displayName.trim().isEmpty
                    ? CropResult.namePlaceholder
                    : widget.displayName,
                style: AppTextStyles.titleS,
              ),
              SizedBox(height: 4.h),
              Row(
                children: [
                  Image.asset('assets/images/catalog/star.webp',
                      width: 20.r, height: 20.r),
                  SizedBox(width: 4.w),
                  Text(_fmtRating(_rating), style: AppTextStyles.body),
                  SizedBox(width: 16.w),
                  GestureDetector(
                    onTap: () => context.push('/profile/reviews'),
                    child: Text(
                        '$_reviewCount ${reviewsWord(_reviewCount)}',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textPrimary,
                          decoration: TextDecoration.underline,
                        )),
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
      style: AppTextStyles.bodyL.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h),
        child: Row(
          children: <Widget>[
            Container(
              width: 20.r,
              height: 20.r,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10.r,
                        height: 10.r,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            SizedBox(width: 12.w),
            Text(label, style: AppTextStyles.body),
          ],
        ),
      ),
    );
  }
}

/// Пустое поле ввода «как контейнер» — серый заливкой контейнер без
/// рамок TextField, внутри курсор. Используется для имени/email —
/// вписываются в общий стиль блок-контейнеров на экране.
class _PlainEditableField extends StatelessWidget {
  const _PlainEditableField({
    required this.controller,
    required this.hint,
    this.focusNode,
    this.keyboardType,
    this.maxLength,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56.h,
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      decoration: BoxDecoration(
        color: AppColors.fieldFill,
        borderRadius: BorderRadius.circular(14.r),
      ),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        maxLength: maxLength,
        style: AppTextStyles.body,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          counterText: '',
          hintText: hint,
          hintStyle:
              AppTextStyles.body.copyWith(color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

class _TintField extends StatelessWidget {
  const _TintField({
    required this.controller,
    this.hint,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
  });
  final TextEditingController controller;
  final String? hint;
  final int minLines;
  final int maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      buildCounter: maxLength != null ? (_, {required currentLength, required isFocused, required maxLength}) => null : null,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
        filled: true,
        fillColor: AppColors.fieldFill,
        contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}


/// Склонение слова «год» для числа лет опыта.
String experienceYearsWord(int n) {
  final int mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'лет';
  switch (n % 10) {
    case 1:
      return 'год';
    case 2:
    case 3:
    case 4:
      return 'года';
    default:
      return 'лет';
  }
}

/// Поле «Опыт работы» — только цифры 0–99, справа автоматически
/// дорисовывается «год / года / лет» в зависимости от значения.
class _ExperienceField extends StatefulWidget {
  const _ExperienceField({required this.controller});
  final TextEditingController controller;

  @override
  State<_ExperienceField> createState() => _ExperienceFieldState();
}

class _ExperienceFieldState extends State<_ExperienceField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final String text = widget.controller.text;
    final int? value = int.tryParse(text);
    final bool hasText = value != null;
    final String suffix = hasText ? '$text ${experienceYearsWord(value)}' : '';

    return Stack(
      children: <Widget>[
        TextField(
          controller: widget.controller,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          style: hasText
              ? AppTextStyles.body.copyWith(color: Colors.transparent)
              : AppTextStyles.body,
          decoration: InputDecoration(
            hintText: hasText ? null : 'Например, 5 лет',
            hintStyle:
                AppTextStyles.body.copyWith(color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.fieldFill,
            contentPadding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusM),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusM),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusM),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        if (hasText)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                alignment: Alignment.centerLeft,
                child: Text(suffix, style: AppTextStyles.body),
              ),
            ),
          ),
      ],
    );
  }
}

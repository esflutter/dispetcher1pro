import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/ai/ai_navigation.dart';
import 'package:dispatcher_1/core/dadata/dadata_service.dart';
import 'package:dispatcher_1/core/executor_card/executor_card_service.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/storage/storage_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/email_validation.dart';
import 'package:dispatcher_1/core/utils/avatar_crop.dart';
import 'package:dispatcher_1/core/utils/photo_source.dart';
import 'package:dispatcher_1/core/utils/plural.dart';
import 'package:dispatcher_1/core/widgets/avatar_action_sheet.dart';
import 'package:dispatcher_1/core/widgets/avatar_circle.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/cropped_avatar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/core/utils/friendly_error.dart';

import 'executor_card_screen.dart';
import 'widgets/executor_card_alerts.dart';

/// Длинная форма создания / редактирования карточки исполнителя.
/// Поля из Figma: ФИО, телефон, местоположение (радиус), спецтехника,
/// категории услуг, опыт работы, статус, о себе.
class EditExecutorCardScreen extends StatefulWidget {
  const EditExecutorCardScreen({super.key, this.editing = true, this.aiDraft});

  final bool editing;

  /// Черновик карточки, собранный ИИ-ассистентом (kind='card_draft').
  /// Если задан — предзаполняем форму его полями. Затрагиваем только те
  /// поля, что реально пришли: пустой черновик не должен затирать уже
  /// сохранённые значения карточки.
  final Map<String, dynamic>? aiDraft;

  @override
  State<EditExecutorCardScreen> createState() => _EditExecutorCardScreenState();
}

class _EditExecutorCardScreenState extends State<EditExecutorCardScreen> {
  // Защита кнопки «Сохранить» от двойного тапа: без неё уходило два UPSERT
  // и два Navigator.pop() (закрывался лишний экран под формой).
  bool _saving = false;
  static const int _nameMaxLen = 60;
  static const int _emailMaxLen = 50;

  late final TextEditingController _location;
  late final TextEditingController _experience;
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

  /// Координаты выбранного адреса. Изначально null; при init асинхронно
  /// подтягиваются из БД (чтобы не затереть сохранённое значение, если
  /// пользователь не трогал адрес). При выборе нового адреса через
  /// `AddressBottomSheet` перезаписываются `result.lat`/`result.lon`.
  /// Без этих полей `executor_cards.location_lat/location_lng` остались
  /// бы null навсегда — и фильтр радиуса в каталоге не работал бы для
  /// карточек исполнителей.
  double? _locationLat;
  double? _locationLng;
  bool _userPickedNewAddress = false;

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
    // Имя/email — один источник с профилем через ExecutorCardData.name
    // (геттер на CropResult.userName) и CropResult.userEmail.
    _nameCtrl = TextEditingController(text: ExecutorCardData.name);
    _emailCtrl = TextEditingController(text: CropResult.userEmail);
    _selectedStatus = ExecutorCardData.status;
    final savedRadius = ExecutorCardData.radius;
    _radiusIndex = savedRadius != null ? _radiusOptions.indexOf(savedRadius) : -1;
    if (_radiusIndex < 0) _radiusIndex = -1;

    // Подтягиваем сохранённые координаты адреса. Если пользователь
    // выберет новый адрес до того, как ответит БД, наш fetch проиграет
    // выбору и не перетрёт его (флаг `_userPickedNewAddress`).
    // ignore: discarded_futures
    _loadSavedCoords();

    // Предзаполнение из черновика ассистента. Выполняется синхронно до
    // первого build и до того, как _loadSavedCoords дождётся БД, поэтому
    // флаг _userPickedNewAddress успевает защитить координаты от перетирания.
    final draft = widget.aiDraft;
    if (draft != null && draft.isNotEmpty) _applyAiDraft(draft);

    _nameFocus.addListener(_onNameFocusChanged);
    _emailFocus.addListener(_onEmailFocusChanged);
  }

  /// Переносит поля черновика ассистента в контроллеры формы. Меняем только
  /// присутствующие поля — пустые значения не затирают сохранённую карточку.
  void _applyAiDraft(Map<String, dynamic> draft) {
    // Адрес: предпочитаем полный address, иначе город.
    final String? address = (draft['address'] as String?)?.trim();
    final String? city = (draft['city'] as String?)?.trim();
    final String? loc = (address != null && address.isNotEmpty)
        ? address
        : (city != null && city.isNotEmpty ? city : null);
    if (loc != null) _location.text = loc;

    // Координаты из геокодера ассистента. Ставим флаг, чтобы асинхронная
    // загрузка из БД их не перетёрла.
    final double? lat = _draftDouble(draft['latitude']);
    final double? lng = _draftDouble(draft['longitude']);
    if (lat != null && lng != null) {
      _locationLat = lat;
      _locationLng = lng;
      _userPickedNewAddress = true;
    }

    // Радиус: 10/20/50 км → индекс 0/1/2.
    final int? radiusKm = _draftInt(draft['radius_km']);
    if (radiusKm != null) {
      final int idx = switch (radiusKm) { 10 => 0, 20 => 1, 50 => 2, _ => -1 };
      if (idx >= 0) _radiusIndex = idx;
    }

    // Правовой статус: код сервера → подпись в форме.
    final String? statusCode = (draft['legal_status'] as String?)?.trim();
    final String? statusLabel = switch (statusCode) {
      'individual' => 'Физ. лицо',
      'self_employed' => 'Самозанятый',
      'ip' => 'ИП',
      'legal_entity' => 'Юр. лицо',
      _ => null,
    };
    if (statusLabel != null) _selectedStatus = statusLabel;

    // Опыт в годах.
    final int? exp = _draftInt(draft['experience_years']);
    if (exp != null && exp >= 0) _experience.text = exp.toString();
    // «О себе» убрано из формы — ассистентское значение не подставляем.
  }

  static double? _draftDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _draftInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  Future<void> _onNameFocusChanged() async {
    if (_nameFocus.hasFocus) return;
    final String value = _nameCtrl.text.trim();
    if (value.isEmpty) {
      _nameCtrl.text = ExecutorCardData.name;
      return;
    }
    if (value == ExecutorCardData.name) return;
    ExecutorCardData.name = value;
    try {
      await ProfileService.instance.update(name: value);
    } catch (_) {/* silent */}
  }

  void _onEmailFocusChanged() {
    if (_emailFocus.hasFocus) {
      if (_emailError != null) setState(() => _emailError = null);
      return;
    }
    final String value = _emailCtrl.text.trim().toLowerCase();
    final bool valid = isValidEmail(value);
    if (valid) {
      CropResult.userEmail = value;
      // ignore: discarded_futures
      ProfileService.instance
          .updatePrivateEmail(value)
          .catchError((_) {/* silent */});
      if (_emailError != null) setState(() => _emailError = null);
    } else {
      setState(() => _emailError = 'Некорректная электронная почта');
    }
  }

  Future<void> _loadSavedCoords() async {
    try {
      final MyExecutorCard? card =
          await ExecutorCardService.instance.loadMine();
      if (!mounted || card == null) return;
      if (_userPickedNewAddress) return;
      setState(() {
        _locationLat = card.locationLat;
        _locationLng = card.locationLng;
      });
    } catch (_) {/* silent — не критично для UI */}
  }

  @override
  void dispose() {
    // На случай, если пользователь ушёл с экрана не снимая фокус.
    // Раньше save в БД был повешен только на focus-blur listener;
    // если пользователь меняет имя/email и сразу жмёт «Сохранить» или
    // «Назад», листенер не срабатывал и в БД оставалось старое.
    // Дублируем запись здесь (fire-and-forget — экран размонтирован).
    // Rollback при ошибке DB: иначе в локальном кэше окажется новое
    // значение, а в БД — старое; следующий loadMine() тихо вернёт UI
    // к старому имени/email и юзер потеряет правки без обратной связи.
    final String name = _nameCtrl.text.trim();
    if (name.isNotEmpty && name != ExecutorCardData.name) {
      final String prev = ExecutorCardData.name;
      ExecutorCardData.name = name;
      // ignore: discarded_futures
      ProfileService.instance.update(name: name).catchError((Object _) {
        ExecutorCardData.name = prev;
      });
    }
    final String email = _emailCtrl.text.trim().toLowerCase();
    if (isValidEmail(email) && email != CropResult.userEmail) {
      final String prev = CropResult.userEmail;
      CropResult.userEmail = email;
      // ignore: discarded_futures
      ProfileService.instance.updatePrivateEmail(email).catchError((Object _) {
        CropResult.userEmail = prev;
      });
    }
    _nameFocus.removeListener(_onNameFocusChanged);
    _emailFocus.removeListener(_onEmailFocusChanged);
    _location.dispose();
    _experience.dispose();
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
        child: AiAssistantFab(onTap: () => openAssistantChat(context)),
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
                  final DadataAddress? result =
                      await showModalBottomSheet<DadataAddress>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const AddressBottomSheet(),
                  );
                  if (result != null) {
                    setState(() {
                      _location.text = result.value;
                      _locationLat = result.lat;
                      _locationLng = result.lon;
                      _userPickedNewAddress = true;
                      // Если радиус ещё не выставлен — дефолт 10 км.
                      // Иначе исполнитель ввёл адрес, не выбрал чип, и
                      // карточка тихо не публикуется (CHECK требует
                      // radius_km для is_published=true). Юзер может
                      // сменить вручную на 20/50 км.
                      if (_radiusIndex < 0) _radiusIndex = 0;
                    });
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
                  // Поле «О себе» убрано из формы. Карточка вообще не пишет
                  // about в БД (см. ExecutorCardService.upsert) — ранее
                  // сохранённый текст не трогается и не теряется.
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
                onPressed: _saving ? null : () async {
                  // Без местоположения карточка не попадает в каталог —
                  // матчинг работает по координатам + радиусу. Поэтому
                  // явно предупреждаем юзера, чтобы он понимал
                  // последствия. По «Вернуться» — выходим, ничего не
                  // сохраняем (юзер увидит свой уже введённый текст в
                  // полях, форма не сбрасывается).
                  if (_location.text.trim().isEmpty) {
                    final bool? proceed =
                        await showSaveCardWithoutLocationAlert(context);
                    if (proceed != true) return;
                    if (!context.mounted) return;
                  }
                  setState(() => _saving = true);

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
                      locationLat: _locationLat,
                      locationLng: _locationLng,
                      radiusKm: radiusKm,
                      isPublished: radiusKm != null,
                      legalStatus: legalStatus,
                      experienceYears: experienceYears,
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    setState(() => _saving = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(e, fallback: 'Не удалось сохранить. Попробуйте ещё раз.'))),
                    );
                    return;
                  }
                  // Локальные сторы обновляем ТОЛЬКО после успешного UPSERT —
                  // иначе при сбое сети флаг «карточка создана» залипал, и
                  // гейт отклика локально считался пройденным без реальной БД.
                  ExecutorCardData.location = _location.text;
                  ExecutorCardData.radius = _radiusIndex >= 0
                      ? _radiusOptions[_radiusIndex]
                      : null;
                  ExecutorCardData.experience = _experience.text;
                  ExecutorCardData.status = _selectedStatus;
                  ExecutorCardScreen.cardCreated = true;

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
      _uploadAvatar(result);
    }
  }

  /// Заливает выбранный аватар в storage `avatars` и пишет URL в
  /// `profiles.avatar_url`. Кроп впекается в сам файл, чтобы аватар был
  /// одинаков у автора и у всех остальных, а не жил только в памяти
  /// `CropResult.saved` (после перезапуска он там пропадал).
  Future<void> _uploadAvatar(CropResult crop) async {
    final String? path = crop.imagePath;
    if (path == null) return;
    try {
      final File cropped = await renderCroppedAvatar(
        sourcePath: path,
        center: crop.center,
        radius: crop.radius,
        area: crop.screenSize,
      );
      final String url = await StorageService.instance.uploadAvatar(cropped);
      try {
        await cropped.delete();
      } catch (_) {}
      await ProfileService.instance.update(avatarUrl: url);
      if (mounted) setState(() => _avatarUrl = url);
    } catch (_) {
      // Раньше сбой загрузки аватара проглатывался молча: фото визуально
      // «вставало», но не сохранялось, и после перезапуска откатывалось.
      // Теперь честно сообщаем, что надо повторить.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить фото. Проверьте интернет и попробуйте ещё раз.')),
        );
      }
    }
  }

  /// Тап по аватару: если фото уже есть — шторка «Обновить/Удалить»,
  /// иначе сразу выбор нового фото.
  Future<void> _onAvatarTap() async {
    final bool hasAvatar =
        (_avatarUrl != null && _avatarUrl!.isNotEmpty) ||
            CropResult.saved != null;
    if (!hasAvatar) {
      await _openCrop();
      return;
    }
    final AvatarAction? action = await showAvatarActionSheet(context);
    if (action == AvatarAction.update) {
      await _openCrop();
    } else if (action == AvatarAction.delete) {
      await _deleteAvatar();
    }
  }

  Future<void> _deleteAvatar() async {
    try {
      await ProfileService.instance.clearAvatar();
      CropResult.saved = null;
      if (mounted) setState(() => _avatarUrl = null);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось удалить фото')),
        );
      }
    }
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
          onTap: _onAvatarTap,
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
                  if (_reviewCount > 0) ...[
                    Image.asset('assets/images/catalog/star.webp',
                        width: 20.r, height: 20.r),
                    SizedBox(width: 4.w),
                    Text(_fmtRating(_rating), style: AppTextStyles.body),
                    SizedBox(width: 16.w),
                  ],
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

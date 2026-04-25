import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/my_services/models.dart';
import 'package:dispatcher_1/core/my_services/my_services_service.dart';
import 'package:dispatcher_1/core/storage/storage_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/photo_source.dart';
import 'package:dispatcher_1/core/utils/thousand_separator_formatter.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/support/chat_screen.dart';
import 'package:dispatcher_1/features/services/my_services_screen.dart';

import 'widgets/service_alerts.dart';

/// Склонение «час» после предлога «от» (род. падеж).
/// 1 → «часа», 2/3/4/… → «часов», 11–14 → «часов».
/// Пустая строка — «часов» (дефолт для hint).
String hoursWord(String text) {
  final int? n = int.tryParse(text);
  if (n == null) return 'часов';
  final int mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'часов';
  if (n % 10 == 1) return 'часа';
  return 'часов';
}

/// Экран «Создание / редактирование услуги».
/// При передаче [serviceId] работает в режиме редактирования.
class CreateServiceScreen extends StatefulWidget {
  const CreateServiceScreen({super.key, this.serviceId});

  final String? serviceId;

  @override
  State<CreateServiceScreen> createState() => _CreateServiceScreenState();
}

class _CreateServiceScreenState extends State<CreateServiceScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceHourCtrl = TextEditingController();
  final _priceDayCtrl = TextEditingController();
  final _minHoursCtrl = TextEditingController();

  int _radiusIndex = -1;
  String? _address;
  final List<String> _photos = [];

  final Set<String> _selCat = {};
  final Set<String> _selMach = {};
  bool _machLimitError = false;
  final GlobalKey _machBlockKey = GlobalKey();

  void _scrollMachIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? ctx = _machBlockKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  static const _radiusOptions = [
    'В радиусе 10 км',
    'В радиусе 20 км',
    'В радиусе 50 км',
  ];
  static const _categories = [
    'Земляные работы',
    'Погрузочно-разгрузочные работы',
    'Перевозка материалов',
    'Строительные работы',
    'Дорожные работы',
    'Буровые работы',
    'Высотные работы',
    'Демонтажные работы',
    'Благоустройство территории',
  ];
  static const _machinery = [
    'Экскаватор-погрузчик',
    'Экскаватор',
    'Погрузчик',
    'Миниэкскаватор',
    'Буроям',
    'Самогруз',
    'Автокран',
    'Бетононасос',
    'Эвакуатор',
    'Автовышка',
    'Манипулятор',
    'Минипогрузчик',
    'Самосвал',
    'Минитрактор',
  ];

  bool get _isEdit => widget.serviceId != null;

  ServiceMock? _editingService;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      try {
        _editingService = ServiceData.services
            .firstWhere((s) => s.id == widget.serviceId);
      } catch (_) {}
      if (_editingService != null) {
        final s = _editingService!;
        _titleCtrl.text = s.title;
        _descCtrl.text = s.description;
        // Ноль трактуем как «не заполнено» — в поле оставляем hint,
        // а не «0», чтобы пользователь не удалял ноль вручную.
        _priceHourCtrl.text = s.pricePerHour == '0' ? '' : s.pricePerHour;
        _priceDayCtrl.text = s.pricePerDay == '0' ? '' : s.pricePerDay;
        _minHoursCtrl.text = s.minOrder;
        _selCat.addAll(s.categories);
        // Инвариант формы — максимум один вид спецтехники на услугу.
        // Старые услуги / presets могли быть сохранены с несколькими —
        // берём только первую, чтобы форма оставалась валидной.
        if (s.machinery.isNotEmpty) _selMach.add(s.machinery.first);
        _photos.addAll(s.photos);
        _address = s.address;
        _radiusIndex = s.radiusIndex;
      }
    }
  }


  Future<void> _addPhoto() async {
    final int remaining = 8 - _photos.length;
    if (remaining <= 0) return;
    final List<String> picked =
        await pickMultipleImagesFromGallery(limit: remaining, context: context);
    if (picked.isEmpty || !mounted) return;
    final List<String> kept =
        picked.length > remaining ? picked.sublist(0, remaining) : picked;
    setState(() => _photos.addAll(kept));
    if (picked.length > remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Можно добавить не более 8 фото. Добавлены первые ${kept.length}.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceHourCtrl.dispose();
    _priceDayCtrl.dispose();
    _minHoursCtrl.dispose();
    super.dispose();
  }

  Future<ServiceDraft> _currentDraft() async {
    final int? radiusKm = switch (_radiusIndex) {
      0 => 10,
      1 => 20,
      2 => 50,
      _ => null,
    };
    // Загружаем только локальные файлы (asset-пути — это превью из
    // предыдущего черновика, они уже где-то отображаются и не
    // требуют загрузки).
    final List<String> uploadedUrls = <String>[];
    for (final String path in _photos) {
      if (path.startsWith('assets/') || path.startsWith('http')) {
        uploadedUrls.add(path);
        continue;
      }
      try {
        final String url =
            await StorageService.instance.uploadServicePhoto(File(path));
        uploadedUrls.add(url);
      } catch (_) {/* пропускаем неудачную загрузку */}
    }
    return ServiceDraft(
      title: _titleCtrl.text.isEmpty ? 'Новая услуга' : _titleCtrl.text,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text,
      machineryTitles: _selMach.toList(),
      categoryTitles: _selCat.toList(),
      pricePerHour: _parsePrice(_priceHourCtrl.text),
      pricePerDay: _parsePrice(_priceDayCtrl.text),
      minHours: int.tryParse(_minHoursCtrl.text),
      photos: uploadedUrls,
      locationAddress: _address,
      radiusKm: radiusKm,
    );
  }

  double? _parsePrice(String s) {
    final String cleaned = s.replaceAll(RegExp(r'\s'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<bool> _save() async {
    final ServiceDraft draft = await _currentDraft();
    try {
      if (_isEdit) {
        await MyServicesService.instance.update(widget.serviceId!, draft);
      } else {
        await MyServicesService.instance.create(draft);
      }
      await ServiceData.refresh();
      return true;
    } on PostgrestException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: ${e.message}')),
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить услугу.')),
      );
      return false;
    }
  }

  Future<void> _onCreateTap() async {
    // Paywall оплачен до этой формы (в `my_services_screen`).
    final bool ok = await _save();
    if (!ok || !mounted) return;
    // Оплаченный слот израсходован. Следующее создание услуги потребует
    // новой оплаты.
    ServiceData.hasUnusedPaidSlot = false;
    await showServicePublishedDialog(context);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openAddressSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddressBottomSheet(),
    );
    if (result != null && mounted) {
      setState(() => _address = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _isEdit
          ? const DarkSubAppBar(title: 'Редактирование услуги')
          : _CreateAppBar(onClose: () => Navigator.of(context).maybePop()),
      body: _buildManualMode(),
    );
  }

  Widget _buildManualMode() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle('Категория услуг'),
                SizedBox(height: 8.h),
                _ChipWrap(
                  items: _categories,
                  selected: _selCat,
                  onToggle: (v) => setState(() {
                    _selCat.contains(v) ? _selCat.remove(v) : _selCat.add(v);
                  }),
                ),
                SizedBox(height: 16.h),
                Column(
                  key: _machBlockKey,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SectionTitle('Спецтехника'),
                    SizedBox(height: 8.h),
                    _ChipWrap(
                      items: _machinery,
                      selected: _selMach,
                      onToggle: (v) {
                        setState(() {
                          if (_selMach.contains(v)) {
                            _selMach.remove(v);
                            _machLimitError = false;
                          } else if (_selMach.isEmpty) {
                            _selMach.add(v);
                            _machLimitError = false;
                          } else {
                            _machLimitError = true;
                          }
                        });
                        if (_machLimitError) _scrollMachIntoView();
                      },
                    ),
                    if (_machLimitError) ...<Widget>[
                      SizedBox(height: 8.h),
                      Text(
                        'Для одной услуги можно выбрать только один вид '
                        'спецтехники. Создайте новую услугу, чтобы '
                        'добавить ещё.',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 16.h),
                _SectionTitle('Название услуги'),
                SizedBox(height: 8.h),
                _TintField(
                  controller: _titleCtrl,
                  hint: 'Например: Автовышка для фасада',
                  maxLength: 25,
                ),
                SizedBox(height: 16.h),
                _SectionTitle('Описание услуги'),
                SizedBox(height: 8.h),
                _TintField(
                  controller: _descCtrl,
                  hint: 'Опишите, какие работы вы\nвыполняете и условия работы',
                  minLines: 2,
                  maxLines: null,
                  maxLength: 500,
                ),
                SizedBox(height: 16.h),
                _SectionTitle('Фото'),
                SizedBox(height: 4.h),
                Text(
                  'По желанию добавьте фото, до 8 шт.',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                    color: AppColors.textTertiary,
                  ),
                ),
                SizedBox(height: 8.h),
                if (_photos.isNotEmpty) ...[
                  _PhotosGrid(
                    photos: _photos,
                    onRemove: (i) => setState(() => _photos.removeAt(i)),
                  ),
                  SizedBox(height: 8.h),
                ],
                _AddPhotosButton(onTap: _addPhoto),
                SizedBox(height: 16.h),
                _SectionTitle('Стоимость'),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    Expanded(
                      child: _TintField(
                        controller: _priceHourCtrl,
                        hint: '₽ / час',
                        suffix: ' ₽ / час',
                        keyboardType: TextInputType.number,
                        maxLength: 7,
                        thousandSeparator: true,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: _TintField(
                        controller: _priceDayCtrl,
                        hint: '₽ / день',
                        suffix: ' ₽ / день',
                        keyboardType: TextInputType.number,
                        maxLength: 7,
                        thousandSeparator: true,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16.h),
                _SectionTitle('Минимальный заказ'),
                SizedBox(height: 8.h),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 16.w * 2 - 12.w) / 2,
                  child: ListenableBuilder(
                    listenable: _minHoursCtrl,
                    builder: (_, _) => _TintField(
                      controller: _minHoursCtrl,
                      hint: 'от 4 часов',
                      prefix: 'от ',
                      suffix: ' ${hoursWord(_minHoursCtrl.text)}',
                      keyboardType: TextInputType.number,
                      maxLength: 3,
                      digitsOnly: true,
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                _SectionTitle('Местоположение'),
                SizedBox(height: 8.h),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openAddressSheet,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                        horizontal: 16.w, vertical: 14.h),
                    decoration: BoxDecoration(
                      color: AppColors.fieldFill,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      _address ?? 'Введите адрес',
                      style: AppTextStyles.body.copyWith(
                        color: _address != null
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                for (int i = 0; i < _radiusOptions.length; i++)
                  _RadiusOption(
                    label: _radiusOptions[i],
                    selected: _radiusIndex == i,
                    onTap: () => setState(() => _radiusIndex = i),
                  ),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(
            16.w,
            12.h,
            16.w,
            16.h + MediaQuery.of(context).padding.bottom,
          ),
          child: _isEdit ? _editButtons() : _createButtons(),
        ),
      ],
    );
  }

  bool get _canCreate =>
      _selCat.isNotEmpty &&
      _selMach.isNotEmpty &&
      _titleCtrl.text.trim().isNotEmpty &&
      _descCtrl.text.trim().isNotEmpty &&
      (_priceHourCtrl.text.trim().isNotEmpty ||
          _priceDayCtrl.text.trim().isNotEmpty) &&
      _minHoursCtrl.text.trim().isNotEmpty &&
      _address != null &&
      _radiusIndex >= 0;

  Widget _createButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            _titleCtrl,
            _descCtrl,
            _priceHourCtrl,
            _priceDayCtrl,
            _minHoursCtrl,
          ]),
          builder: (_, _) => PrimaryButton(
            label: 'Создать',
            enabled: _canCreate,
            onPressed: _canCreate ? _onCreateTap : null,
          ),
        ),
        SizedBox(height: 8.h),
        SecondaryButton(
          label: 'Заполнить автоматически',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ChatScreen(
                initialMessage: 'create_service',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _editButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PrimaryButton(
          label: 'Сохранить',
          onPressed: () async {
            final bool ok = await _save();
            if (!ok || !mounted) return;
            Navigator.of(context).pop();
          },
        ),
        SizedBox(height: 8.h),
        SecondaryButton(
          label: 'Удалить услугу',
          onPressed: () async {
            final ok = await showDeleteServiceDialog(context);
            if (!mounted) return;
            if (ok != true) return;
            try {
              await MyServicesService.instance.archive(widget.serviceId!);
              await ServiceData.refresh();
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Не удалось удалить: $e')),
              );
              return;
            }
            if (!mounted) return;
            final nav = Navigator.of(context);
            nav.pop(); // закрыть редактирование
            if (nav.canPop()) nav.pop(); // закрыть просмотр
          },
        ),
      ],
    );
  }

}

/// Экран автоматического создания услуги через ИИ-ассистента.
class _AiCreateServiceScreen extends StatefulWidget {
  const _AiCreateServiceScreen();

  @override
  State<_AiCreateServiceScreen> createState() => _AiCreateServiceScreenState();
}

class _AiCreateServiceScreenState extends State<_AiCreateServiceScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 48.h,
        automaticallyImplyLeading: false,
        title: Padding(
          padding: EdgeInsets.only(top: 2.h),
          child: Text(
            'Создание услуги',
            style: AppTextStyles.titleS.copyWith(color: Colors.white),
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 8.w, top: 2.h),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.close_rounded, size: 24.r, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Text(
                'Опишите услугу — текстом или голосом, я заполню всё за вас',
                style: AppTextStyles.body,
              ),
            ),
          ),
          const Spacer(),
          _AiInputBar(
            controller: _ctrl,
            onSend: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

// ── Вспомогательные виджеты ──

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 20.sp,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _TintField extends StatelessWidget {
  const _TintField({
    required this.controller,
    required this.hint,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.maxLength,
    this.suffix,
    this.prefix,
    this.thousandSeparator = false,
    this.digitsOnly = false,
  });
  final TextEditingController controller;
  final String hint;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final int? maxLength;
  final String? suffix;
  final String? prefix;
  final bool thousandSeparator;
  final bool digitsOnly;

  List<TextInputFormatter>? _buildFormatters() {
    if (thousandSeparator) {
      return <TextInputFormatter>[
        ThousandSeparatorFormatter(maxDigits: maxLength ?? 9),
      ];
    }
    final List<TextInputFormatter> fs = <TextInputFormatter>[];
    if (digitsOnly) fs.add(FilteringTextInputFormatter.digitsOnly);
    if (maxLength != null) fs.add(LengthLimitingTextInputFormatter(maxLength));
    return fs.isEmpty ? null : fs;
  }

  @override
  Widget build(BuildContext context) {
    final bool hasAffixDef = suffix != null || prefix != null;

    if (hasAffixDef) {
      // Слушаем controller, чтобы оверлей с prefix/suffix появлялся сразу
      // при вводе, а не ждал следующего setState родителя.
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final bool hasText = controller.text.isNotEmpty;
          double prefixWidth = 0;
          if (hasText && prefix != null) {
            final tp = TextPainter(
              text: TextSpan(text: prefix, style: AppTextStyles.body),
              textDirection: TextDirection.ltr,
            )..layout();
            prefixWidth = tp.width;
          }
          return Stack(
            children: [
              TextField(
                controller: controller,
                keyboardType: keyboardType,
                inputFormatters: _buildFormatters(),
                style: hasText
                    ? AppTextStyles.body.copyWith(color: Colors.transparent)
                    : AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: hasText ? null : hint,
                  hintStyle: AppTextStyles.body
                      .copyWith(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.fieldFill,
                  contentPadding: EdgeInsets.fromLTRB(
                    16.w + prefixWidth, 12.h, 16.w, 12.h,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              if (hasText)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 16.w, vertical: 12.h),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${prefix ?? ''}${controller.text}${suffix ?? ''}',
                        style: AppTextStyles.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }

    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: maxLength != null
          ? [LengthLimitingTextInputFormatter(maxLength)]
          : null,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
        filled: true,
        fillColor: AppColors.fieldFill,
        contentPadding:
            EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.items,
    required this.selected,
    required this.onToggle,
  });
  final List<String> items;
  final Set<String> selected;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: items.map((label) {
        final on = selected.contains(label);
        return GestureDetector(
          onTap: () => onToggle(label),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: on ? AppColors.primary : AppColors.surface,
              border: Border.all(color: AppColors.primary, width: 1),
              borderRadius: BorderRadius.circular(100.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w400,
                      height: 1.3,
                      color: on ? Colors.white : AppColors.textPrimary,
                    )),
                if (on) ...[
                  SizedBox(width: 6.w),
                  Icon(Icons.close_rounded, size: 14.r, color: Colors.white),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _RadiusOption extends StatelessWidget {
  const _RadiusOption({
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
          children: [
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

class _PhotosGrid extends StatelessWidget {
  const _PhotosGrid({required this.photos, required this.onRemove});
  final List<String> photos;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: List.generate(photos.length, (i) {
        return SizedBox(
          width: 72.r,
          height: 72.r,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10.r),
                child: isAssetPath(photos[i])
                    ? Image.asset(
                        photos[i],
                        width: 72.r,
                        height: 72.r,
                        fit: BoxFit.cover,
                      )
                    : Image.file(
                        File(photos[i]),
                        width: 72.r,
                        height: 72.r,
                        fit: BoxFit.cover,
                      ),
              ),
              Positioned(
                top: 4.w,
                right: 4.w,
                child: GestureDetector(
                  onTap: () => onRemove(i),
                  child: Image.asset(
                    'assets/icons/ui/close_photo.webp',
                    width: 24.r,
                    height: 24.r,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _AddPhotosButton extends StatelessWidget {
  const _AddPhotosButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 42.h,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/icons/ui/add_circle.webp',
              width: 24.r,
              height: 24.r,
              fit: BoxFit.contain,
            ),
            SizedBox(width: 8.w),
            Text(
              'Добавить изображения',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiInputBar extends StatelessWidget {
  const _AiInputBar({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 12.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Container(
              width: 44.r,
              height: 44.r,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12.r),
              ),
              alignment: Alignment.center,
              child:
                  Icon(Icons.image_outlined, color: Colors.white, size: 22.r),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Container(
                height: 44.r,
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(100.r),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        inputFormatters: [LengthLimitingTextInputFormatter(1000)],
                        decoration: InputDecoration(
                          hintText: 'Написать...',
                          hintStyle: AppTextStyles.body
                              .copyWith(color: AppColors.textTertiary),
                          isCollapsed: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    Icon(Icons.mic_none_rounded,
                        size: 22.r, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            SizedBox(width: 8.w),
            GestureDetector(
              onTap: onSend,
              child: Container(
                width: 44.r,
                height: 44.r,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 22.r),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// AppBar режима создания услуги: тёмный фон, крестик вместо стрелки назад.
class _CreateAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _CreateAppBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Size get preferredSize => Size.fromHeight(48.h);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.navBarDark,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      toolbarHeight: 48.h,
      automaticallyImplyLeading: false,
      title: Padding(
        padding: EdgeInsets.only(top: 2.h),
        child: Text(
          'Создание услуги',
          style: AppTextStyles.titleS.copyWith(color: Colors.white),
        ),
      ),
      actions: <Widget>[
        Padding(
          padding: EdgeInsets.only(right: 8.w, top: 2.h),
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(Icons.close_rounded, size: 24.r, color: Colors.white),
            onPressed: onClose,
          ),
        ),
      ],
    );
  }
}

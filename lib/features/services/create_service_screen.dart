import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/catalog/catalog_service.dart';
import 'package:dispatcher_1/core/catalog/models.dart' as cat;
import 'package:dispatcher_1/core/dadata/dadata_service.dart';
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
import 'widgets/service_paywall.dart';

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
  const CreateServiceScreen({super.key, this.serviceId, this.aiDraft});

  final String? serviceId;

  /// Черновик от ИИ-ассистента (slot-fill). Если передан — поля
  /// заполняются автоматически.
  final Map<String, dynamic>? aiDraft;

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
  /// Координаты выбранного из DaData адреса. Сохраняем рядом с `_address`,
  /// чтобы при INSERT/UPDATE услуги пробросить их в БД (без них радиус-
  /// фильтр у заказчика не найдёт услугу).
  double? _addressLat;
  double? _addressLng;
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

  // Справочники тянем из CatalogService — он же кэширует их в памяти.
  // Без актуальных id↔title из БД маппинг при INSERT (services.machinery_ids
  // / category_ids) промахнётся и часть выбора потеряется.
  List<String> _categories = const <String>[];
  List<String> _machinery = const <String>[];

  bool get _isEdit => widget.serviceId != null;

  /// true пока подгружаем полную запись услуги из БД (только в edit).
  /// Кнопка «Сохранить» в это время бесполезна, форма пуста.
  bool _loadingDetail = false;

  /// true пока идёт upload фото и INSERT/UPDATE услуги. Без этого
  /// флага двойной тап по «Создать» успевал отправить два INSERT'а
  /// и создать две одинаковых услуги (фото медленные, в окне между
  /// upload и insert второй тап не блокировался).
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loadingDetail = true;
      _loadEditingService();
    }
    final List<cat.MachineryRef>? mc =
        CatalogService.instance.cachedMachinery;
    final List<cat.CategoryRef>? cc =
        CatalogService.instance.cachedCategories;
    if (mc != null) {
      _machinery =
          mc.map((cat.MachineryRef e) => e.title).toList(growable: false);
    }
    if (cc != null) {
      _categories =
          cc.map((cat.CategoryRef e) => e.title).toList(growable: false);
    }
    if (mc == null || cc == null) {
      _loadDirectories();
    }
    if (widget.aiDraft != null && !_isEdit) {
      _applyAiDraft(widget.aiDraft!, mc, cc);
    }
  }

  /// Применяет ИИ-черновик к полям формы (best-effort).
  void _applyAiDraft(
    Map<String, dynamic> draft,
    List<cat.MachineryRef>? mcCached,
    List<cat.CategoryRef>? ccCached,
  ) {
    final title = (draft['title'] as String? ?? '').trim();
    final desc  = (draft['description'] as String? ?? '').trim();
    if (title.isNotEmpty) _titleCtrl.text = title;
    if (desc.isNotEmpty)  _descCtrl.text  = desc;

    final ph = draft['price_per_hour'];
    final pd = draft['price_per_day'];
    final mh = draft['min_hours'];
    if (ph is num) _priceHourCtrl.text = ph.toString();
    if (pd is num) _priceDayCtrl.text  = pd.toString();
    if (mh is num) _minHoursCtrl.text  = mh.toString();

    final machIds = (draft['machinery_ids'] is List)
        ? (draft['machinery_ids'] as List).whereType<int>().toSet()
        : <int>{};
    final catIds = (draft['category_ids'] is List)
        ? (draft['category_ids'] as List).whereType<int>().toSet()
        : <int>{};

    void mapIds() {
      final mc = mcCached ?? CatalogService.instance.cachedMachinery;
      final cc = ccCached ?? CatalogService.instance.cachedCategories;
      if (mc != null) {
        // Услуга — максимум одна техника. Берём первый матч.
        for (final m in mc) {
          if (machIds.contains(m.id)) {
            _selMach.add(m.title);
            if (_selMach.isNotEmpty) break;
          }
        }
      }
      if (cc != null) {
        for (final c in cc) {
          if (catIds.contains(c.id)) _selCat.add(c.title);
        }
      }
    }

    mapIds();
    if (mcCached == null || ccCached == null) {
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        setState(mapIds);
      });
    }

    final radius = draft['radius_km'];
    if (radius is int) {
      const map = <int, int>{10: 0, 20: 1, 50: 2};
      _radiusIndex = map[radius] ?? -1;
    }

    final addr = (draft['address'] as String? ?? '').trim();
    final city = (draft['city']    as String? ?? '').trim();
    if (addr.isNotEmpty) {
      _address = addr;
    } else if (city.isNotEmpty) {
      _address = city;
    }
    // Координаты города от ассистента — иначе услуга без гео не находится
    // в поиске по радиусу. Точный адрес пользователь может уточнить сам.
    final lat = draft['latitude'];
    final lng = draft['longitude'];
    if (lat is num && lng is num) {
      _addressLat = lat.toDouble();
      _addressLng = lng.toDouble();
    }
  }

  Future<void> _loadDirectories() async {
    try {
      final List<cat.MachineryRef> m =
          await CatalogService.instance.listActiveMachinery();
      final List<cat.CategoryRef> c =
          await CatalogService.instance.listActiveCategories();
      if (!mounted) return;
      setState(() {
        _machinery =
            m.map((cat.MachineryRef e) => e.title).toList(growable: false);
        _categories =
            c.map((cat.CategoryRef e) => e.title).toList(growable: false);
      });
    } catch (_) {
      // Чипы техники/категорий без справочников остаются пустыми, и
      // юзер не понимает, почему. Раньше catch был тихий — теперь
      // показываем snackbar с ретраем, чтобы стало ясно: это сеть, а
      // не «у нас нет техники в каталоге».
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Не удалось загрузить справочники. '
            'Проверьте интернет и попробуйте позже.',
          ),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: _loadDirectories,
          ),
        ),
      );
    }
  }

  /// Грузим полную услугу из БД — `MyServicesService.getMine` отдаёт
  /// поля photos/address/radiusKm, которых нет в `ServiceData` (там
  /// только summary). Без этого re-save затирал бы фото и местоположение.
  Future<void> _loadEditingService() async {
    final String? id = widget.serviceId;
    if (id == null) return;
    try {
      final MyServiceDetail? d =
          await MyServicesService.instance.getMine(id);
      if (!mounted || d == null) {
        if (mounted) setState(() => _loadingDetail = false);
        return;
      }
      setState(() {
        _titleCtrl.text = d.title;
        _descCtrl.text = d.description ?? '';
        _priceHourCtrl.text = _fmtPriceForField(d.pricePerHour);
        _priceDayCtrl.text = _fmtPriceForField(d.pricePerDay);
        _minHoursCtrl.text = d.minHours?.toString() ?? '';
        _selCat
          ..clear()
          ..addAll(d.categoryTitles);
        _selMach.clear();
        // Инвариант формы — максимум один вид спецтехники на услугу.
        if (d.machineryTitles.isNotEmpty) {
          _selMach.add(d.machineryTitles.first);
        }
        _photos
          ..clear()
          ..addAll(d.photos);
        _address = d.locationAddress;
        _addressLat = d.locationLat;
        _addressLng = d.locationLng;
        _radiusIndex = switch (d.radiusKm) {
          10 => 0,
          20 => 1,
          50 => 2,
          _ => -1,
        };
        _loadingDetail = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  /// «12500» → «12 500», `null`/`0` → пустая строка (показываем hint).
  String _fmtPriceForField(double? v) {
    if (v == null || v <= 0) return '';
    final int i = v.round();
    final String s = i.toString();
    final StringBuffer b = StringBuffer();
    for (int k = 0; k < s.length; k++) {
      if (k > 0 && (s.length - k) % 3 == 0) b.write(' ');
      b.write(s[k]);
    }
    return b.toString();
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
    int uploadFailed = 0;
    for (final String path in _photos) {
      if (path.startsWith('assets/') || path.startsWith('http')) {
        uploadedUrls.add(path);
        continue;
      }
      try {
        final String url =
            await StorageService.instance.uploadServicePhoto(File(path));
        uploadedUrls.add(url);
      } catch (_) {
        uploadFailed++;
      }
    }
    if (uploadFailed > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploadFailed == 1
                ? 'Не удалось загрузить 1 фото. Услуга сохранится без него.'
                : 'Не удалось загрузить $uploadFailed фото. Услуга сохранится без них.',
          ),
        ),
      );
    }
    final double? priceHour = _parsePrice(_priceHourCtrl.text);
    final double? priceDay = _parsePrice(_priceDayCtrl.text);
    final int? minHours = int.tryParse(_minHoursCtrl.text.trim());
    return ServiceDraft(
      title: _titleCtrl.text.isEmpty ? 'Новая услуга' : _titleCtrl.text,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text,
      machineryTitles: _selMach.toList(),
      categoryTitles: _selCat.toList(),
      // ≤ 0 не пропускаем — UI блокирует кнопку «Создать», но и здесь
      // подстраховываемся, чтобы случайно не записать 0₽.
      pricePerHour: (priceHour != null && priceHour > 0) ? priceHour : null,
      pricePerDay: (priceDay != null && priceDay > 0) ? priceDay : null,
      minHours: (minHours != null && minHours > 0) ? minHours : null,
      photos: uploadedUrls,
      locationAddress: _address,
      locationLat: _addressLat,
      locationLng: _addressLng,
      radiusKm: radiusKm,
    );
  }

  double? _parsePrice(String s) {
    final String cleaned = s.replaceAll(RegExp(r'\s'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  /// Возвращает id сохранённой услуги (для create — новый, для edit —
  /// существующий) либо null при ошибке (snackbar уже показан).
  Future<String?> _save() async {
    final ServiceDraft draft = await _currentDraft();
    try {
      String id;
      if (_isEdit) {
        await MyServicesService.instance.update(widget.serviceId!, draft);
        id = widget.serviceId!;
      } else {
        id = await MyServicesService.instance.create(draft);
      }
      await ServiceData.refresh();
      return id;
    } on PostgrestException catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: ${e.message}')),
      );
      return null;
    } catch (_) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить услугу.')),
      );
      return null;
    }
  }

  Future<void> _onCreateTap() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final String? id = await _save();
      if (id == null || !mounted) return;
      if (_isEdit) {
        // Редактирование — услуга уже была оплачена ранее, просто
        // показываем подтверждение и закрываем экран.
        await showServicePublishedDialog(context);
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }
      // Только что созданная услуга по умолчанию `is_paid=false` — она не
      // видна в каталоге. Сразу уводим юзера на оплату со `service_id`,
      // после успешной оплаты trigger `apply_payment_success` поставит
      // `is_paid=true` и услуга появится в каталоге.
      Navigator.of(context).pop(); // закрываем форму создания
      // Открываем paywall «Оплатите размещение услуги» с фоном-картинкой;
      // оттуда юзер тапом «Продолжить» уходит на шторку выбора способа
      // оплаты. Прямой переход на голую шторку убран — без paywall'а
      // фон оставался чёрным.
      if (mounted) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => ServicePaywall(serviceId: id),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openAddressSheet() async {
    final DadataAddress? result = await showModalBottomSheet<DadataAddress>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddressBottomSheet(),
    );
    if (result != null && mounted) {
      setState(() {
        _address = result.value;
        _addressLat = result.lat;
        _addressLng = result.lon;
        // Дефолт 10 км сразу после выбора адреса — иначе юзер ввёл
        // локацию, не тапнул чип радиуса, и кнопка «Опубликовать»
        // остаётся disabled (`_canCreate` требует _radiusIndex >= 0).
        // Можно вручную поменять на 20/50.
        if (_radiusIndex < 0) _radiusIndex = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _isEdit
          ? const DarkSubAppBar(title: 'Редактирование услуги')
          : _CreateAppBar(onClose: () => Navigator.of(context).maybePop()),
      body: _loadingDetail
          ? const Center(child: CircularProgressIndicator())
          : _buildManualMode(),
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

  /// Хотя бы одно поле цены заполнено и парсится в число > 0. Цены 0/-N
  /// БД не отвергает (CHECK на >0 нет), но услуга бесплатной быть не
  /// может — отсекаем на UI.
  bool get _hasValidPrice {
    final double? hour = _parsePrice(_priceHourCtrl.text);
    final double? day = _parsePrice(_priceDayCtrl.text);
    return (hour != null && hour > 0) || (day != null && day > 0);
  }

  /// Минимальное количество часов — целое число строго больше 0.
  bool get _hasValidMinHours {
    final int? n = int.tryParse(_minHoursCtrl.text.trim());
    return n != null && n > 0;
  }

  bool get _canCreate =>
      _selCat.isNotEmpty &&
      _selMach.isNotEmpty &&
      _titleCtrl.text.trim().isNotEmpty &&
      _descCtrl.text.trim().isNotEmpty &&
      _hasValidPrice &&
      _hasValidMinHours &&
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
            enabled: _canCreate && !_saving,
            onPressed: _canCreate && !_saving ? _onCreateTap : null,
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
            final String? id = await _save();
            if (id == null || !mounted) return;
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
                child: imageFromPath(
                  photos[i],
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

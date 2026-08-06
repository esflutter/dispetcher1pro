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
import 'package:dispatcher_1/core/settings/settings_service.dart';
import 'package:dispatcher_1/core/storage/storage_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
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
  static const _radiusOptions = [
    'В радиусе 10 км',
    'В радиусе 20 км',
    'В радиусе 50 км',
  ];

  // Справочник техники тянем из CatalogService — он кэширует его в памяти.
  // Без актуальных id↔title из БД маппинг при INSERT (services.machinery_ids)
  // промахнётся.
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
    if (mc != null) {
      _machinery =
          mc.map((cat.MachineryRef e) => e.title).toList(growable: false);
    }
    if (mc == null) {
      _loadDirectories();
    }
    if (widget.aiDraft != null && !_isEdit) {
      _applyAiDraft(widget.aiDraft!, mc);
    }
  }

  /// Применяет ИИ-черновик к полям формы (best-effort).
  void _applyAiDraft(
    Map<String, dynamic> draft,
    List<cat.MachineryRef>? mcCached,
  ) {
    final title = (draft['title'] as String? ?? '').trim();
    if (title.isNotEmpty) _titleCtrl.text = title;
    // Описание и категории услуги убраны из формы — ассистентские значения
    // не подставляем, чтобы услуга не сохранялась с тем, чего не видно.

    final ph = draft['price_per_hour'];
    final pd = draft['price_per_day'];
    final mh = draft['min_hours'];
    if (ph is num) _priceHourCtrl.text = ph.toString();
    if (pd is num) _priceDayCtrl.text  = pd.toString();
    if (mh is num) _minHoursCtrl.text  = mh.toString();

    // Фото из формы услуги убраны (услуга = вид техники + цена + мин. заказ),
    // поэтому ассистентские ai_photos НЕ подставляем — иначе услуга
    // публиковалась бы с фото, которыми исполнитель не управляет и которых
    // не видит в форме.

    final machIds = (draft['machinery_ids'] is List)
        ? (draft['machinery_ids'] as List).whereType<int>().toSet()
        : <int>{};

    void mapIds() {
      final mc = mcCached ?? CatalogService.instance.cachedMachinery;
      if (mc != null) {
        // Услуга — одна техника, она же название. Берём первый матч.
        for (final m in mc) {
          if (machIds.contains(m.id)) {
            _selMach.add(m.title);
            if (_selMach.isNotEmpty) break;
          }
        }
      }
    }

    mapIds();
    if (mcCached == null) {
      // Ждём реальный прогрев справочника, а не фиксированную паузу: на
      // холодном старте/медленной сети за 100 мс кэш мог не успеть, и
      // распознанная ассистентом техника не подставлялась — кнопка
      // «Создать» оставалась серой без объяснения. Как в форме заказа.
      CatalogService.instance.warmup().then((_) {
        if (!mounted) return;
        setState(mapIds);
      }).catchError((Object _) {
        // Прогрев не удался (нет сети) — техника подставится при обычной
        // загрузке экрана; молча гасим, чтобы исключение не всплыло.
      });
    }

    // Радиус может прийти числом, дробью или строкой («20») — разбираем
    // устойчиво, как форма карточки исполнителя, иначе при строковом
    // значении кнопка «Создать» оставалась серой без объяснения.
    final int? radiusKm = switch (draft['radius_km']) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v.trim()),
      _ => null,
    };
    if (radiusKm != null) {
      const map = <int, int>{10: 0, 20: 1, 50: 2};
      _radiusIndex = map[radiusKm] ?? -1;
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
      if (!mounted) return;
      setState(() {
        _machinery =
            m.map((cat.MachineryRef e) => e.title).toList(growable: false);
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
      // Название услуги = выбранный вид техники (поле «Название» убрано).
      title: _selMach.isEmpty ? 'Новая услуга' : _selMach.first,
      // «Описание» и «Категории» убраны из формы. Насильно не обнуляем: при
      // редактировании старой услуги контроллеры держат прежние значения и
      // пишут их обратно (текст/категории не теряются), у новой услуги — пусто.
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
      // Бесплатный режим: сервер публикует услугу сразу при создании, платить
      // не за что. Показываем то же подтверждение, что и при редактировании,
      // вместо экрана оплаты. Сам экран оплаты не удаляем — он вернётся
      // вместе с платным режимом.
      if (_isEdit || SettingsService.instance.freeModeCached) {
        // Редактирование — услуга уже была оплачена ранее, просто
        // показываем подтверждение и закрываем экран.
        // Новая услуга в бесплатном режиме публикуется сразу, но пока по ней
        // не одобрены документы, заказчики её не увидят — говорим об этом
        // прямо, иначе человек будет ждать заказов, которых не будет.
        await showServicePublishedDialog(
          context,
          needsDocs:
              !_isEdit && SettingsService.instance.perServiceDocsCached,
        );
        if (!mounted) return;
        Navigator.of(context).pop(_isEdit ? null : true);
        return;
      }
      // Только что созданная услуга по умолчанию `is_paid=false` — она не
      // видна в каталоге. Сразу уводим юзера на оплату со `service_id`,
      // после успешной оплаты trigger `apply_payment_success` поставит
      // `is_paid=true` и услуга появится в каталоге.
      // true — услуга создана из черновика ассистента: handoff-карточка
      // погасит свою кнопку, чтобы повторными тапами не плодить дубли услуги.
      Navigator.of(context).pop(true); // закрываем форму создания
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
    if (!mounted) return;
    // Гасим фокус ПОСЛЕ закрытия шита адреса в post-frame: Flutter
    // восстанавливает фокус на ранее активное поле (описание) уже после
    // синхронного unfocus(), отменяя его. Post-frame перебивает восстановление.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).unfocus();
    });
    if (result != null) {
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
                // Услуга = один вид спецтехники. Название услуги берётся
                // автоматически из выбранного вида (отдельного поля нет).
                _SectionTitle('Спецтехника'),
                SizedBox(height: 8.h),
                _MachineryDropdown(
                  items: _machinery,
                  selected: _selMach.isEmpty ? null : _selMach.first,
                  onSelected: (String v) => setState(() {
                    _selMach
                      ..clear()
                      ..add(v);
                  }),
                ),
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
      _selMach.isNotEmpty &&
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
        // «Заполнить автоматически» нужна только при РУЧНОМ создании — увести к
        // ассистенту, чтобы он собрал услугу. Когда форма УЖЕ открыта из
        // черновика ассистента (aiDraft), кнопка лишняя и запускала новую услугу
        // с нуля, теряя черновик — поэтому прячем её. Поля и фото правятся здесь.
        if (widget.aiDraft == null) ...<Widget>[
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
      ],
    );
  }

  Widget _editButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PrimaryButton(
          label: 'Сохранить',
          // Тот же guard, что в _onCreateTap: без него двойной тап
          // повторно заливал новые фото и слал второй UPDATE.
          enabled: !_saving,
          onPressed: () async {
            if (_saving) return;
            setState(() => _saving = true);
            try {
              final String? id = await _save();
              if (id == null || !mounted) return;
              Navigator.of(context).pop();
            } finally {
              if (mounted) setState(() => _saving = false);
            }
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
    this.keyboardType,
    this.maxLength,
    this.suffix,
    this.prefix,
    this.thousandSeparator = false,
    this.digitsOnly = false,
  });
  final TextEditingController controller;
  final String hint;
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
      maxLines: 1,
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

/// Выпадающий список выбора вида спецтехники (одиночный выбор). По тапу
/// открывает нижнюю шторку со списком; выбранный отмечается галочкой.
class _MachineryDropdown extends StatelessWidget {
  const _MachineryDropdown({
    required this.items,
    required this.selected,
    required this.onSelected,
  });
  final List<String> items;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final bool empty = selected == null;
    return GestureDetector(
      onTap: items.isEmpty ? null : () => _openPicker(context),
      child: Container(
        height: 52.h,
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(
          color: AppColors.fieldFill,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                empty ? 'Выберите вид техники' : selected!,
                style: AppTextStyles.body.copyWith(
                  color:
                      empty ? AppColors.textTertiary : AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.textTertiary, size: 24.r),
          ],
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(height: 12.h),
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (BuildContext _, int i) {
                  final String m = items[i];
                  final bool on = m == selected;
                  return ListTile(
                    title: Text(m, style: AppTextStyles.body),
                    trailing: on
                        ? Icon(Icons.check_rounded,
                            color: AppColors.primary, size: 22.r)
                        : null,
                    onTap: () => Navigator.of(ctx).pop(m),
                  );
                },
              ),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
    if (picked != null) onSelected(picked);
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

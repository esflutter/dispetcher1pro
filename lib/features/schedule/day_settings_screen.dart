import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/ai/ai_navigation.dart';
import 'package:dispatcher_1/core/dadata/dadata_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/schedule/schedule_screen.dart';
import 'package:dispatcher_1/features/schedule/widgets/schedule_alerts.dart';
import 'package:dispatcher_1/features/services/my_services_screen.dart';

/// Экран «Параметры дня» для группы «Мой график».
class DaySettingsScreen extends StatefulWidget {
  const DaySettingsScreen({
    super.key,
    required this.dayLabel,
    required this.initialState,
    this.initial = const DaySettings(),
  });

  final String dayLabel;
  final DayState initialState;

  /// Сохранённые ранее параметры дня. Родитель хранит их в
  /// `Map<DateTime, DaySettings>` и подставляет сюда, чтобы при
  /// повторном открытии форма была заполнена.
  final DaySettings initial;

  @override
  State<DaySettingsScreen> createState() => _DaySettingsScreenState();
}

class _DaySettingsScreenState extends State<DaySettingsScreen> {
  late DayState _state;
  late bool _accepting;
  TimeOfDay? _timeFrom;
  TimeOfDay? _timeTo;
  bool _allDay = false;
  String? _openPicker;
  int _radiusIndex = -1;
  String? _location;
  // Координаты выбранного через DaData адреса. Без них серверный
  // radius-матчинг для этого дня не работает: `schedule_day_overrides
  // .location_lat/lng` остаются NULL.
  double? _locationLat;
  double? _locationLng;

  /// Якорь на раскрываемый пикер времени — чтобы после открытия
  /// скроллить форму до центра вьюпорта и пикер не выпадал ниже.
  final GlobalKey _pickerAnchorKey = GlobalKey();

  final Set<String> _selMach = {};
  final Set<String> _selCat = {};

  static const List<String> _radiusOptions = DaySettings.radiusOptions;

  /// Чипы спецтехники собираем из РЕАЛЬНЫХ услуг исполнителя. Если у
  /// него ещё нет ни одной — список пустой (показываем hint, см. ниже).
  /// Раньше тут был fallback на `ServiceData.presets` (3 фейк-услуги:
  /// Экскаватор/Самосвал/Автовышка) — после миграции он попадал на
  /// экран «Параметры дня» и предлагал чужую технику.
  List<String> get _machinery => ServiceData.services
      .expand((ServiceMock s) => s.machinery)
      .toSet()
      .toList();

  List<String> get _categories => ServiceData.services
      .expand((ServiceMock s) => s.categories)
      .toSet()
      .toList();

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
    _accepting = widget.initial.accepting;
    _timeFrom = widget.initial.timeFrom;
    _timeTo = widget.initial.timeTo;
    _allDay = widget.initial.allDay;
    _radiusIndex = widget.initial.radiusIndex;
    _location = widget.initial.location;
    _locationLat = widget.initial.locationLat;
    _locationLng = widget.initial.locationLng;
    _selMach.addAll(widget.initial.machinery);
    _selCat.addAll(widget.initial.categories);
  }

  Future<void> _toggleAccepting(bool value) async {
    if (!value) {
      final bool? ok = await ScheduleAlerts.showCloseAcceptance(context);
      if (ok != true) return;
    }
    // Тумблер «Приём заказов» отвечает ТОЛЬКО за приём новых заказов;
    // признак «выходной» меняется отдельно — оранжевой кнопкой
    // «Отметить нерабочим» в графике. Поэтому `_state` здесь не
    // трогаем.
    setState(() => _accepting = value);
  }

  /// Сборка DaySettings из текущих полей формы. Используется и при
  /// «Сохранить», и при системной back-кнопке (PopScope), чтобы родитель
  /// получил одинаковый объект независимо от того, как пользователь
  /// закрыл экран. `clearDayOff=true`, если изначально день был
  /// нерабочим, а сейчас — нет (пользователь нажал «Отметить рабочим»).
  DaySettings _buildResult() => DaySettings(
        accepting: _accepting,
        timeFrom: _timeFrom,
        timeTo: _timeTo,
        allDay: _allDay,
        radiusIndex: _radiusIndex,
        location: _location,
        locationLat: _locationLat,
        locationLng: _locationLng,
        machinery: Set<String>.from(_selMach),
        categories: Set<String>.from(_selCat),
        clearDayOff: widget.initialState == DayState.dayOff &&
            _state != DayState.dayOff,
      );

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      // Когда система/AppBar back-кнопка пытаются закрыть экран — мы
      // сами делаем pop с DaySettings, чтобы родитель применил
      // clearDayOff (или просто сохранил отредактированные поля).
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        Navigator.of(context).pop(_buildResult());
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Параметры дня'),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 88.h),
        child: AiAssistantFab(onTap: () => openAssistantChat(context)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildBody()),
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
                label: _state == DayState.dayOff ? 'Отметить рабочим' : 'Сохранить',
                onPressed: () {
                  if (_state == DayState.dayOff) {
                    // «Отметить рабочим» — переключаемся в noOrders и
                    // даём пользователю настроить параметры дня (время,
                    // радиус, техника). Применится по «Сохранить» или
                    // по back-кнопке (PopScope ниже сам сложит DaySettings
                    // с clearDayOff=true, если initial был dayOff).
                    setState(() => _state = DayState.noOrders);
                  } else {
                    Navigator.of(context).pop(_buildResult());
                  }
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildBody() {
    if (_state == DayState.dayOff) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
            child: Text(widget.dayLabel,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                )),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.w),
                child: Text(
                  'Вы отметили этот день выходным — заказы на него не принимаются',
                  style: AppTextStyles.body.copyWith(color: AppColors.textPrimary, height: 1.3),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Text(widget.dayLabel,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                )),
          ),
          SizedBox(height: AppSpacing.md),
          Divider(height: 1, thickness: 0.5, color: Colors.grey.shade300),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            child: Row(
              children: [
                Expanded(
                  child: Text('Приём заказов',
                      style: AppTextStyles.button),
                ),
                ScheduleToggle(
                  value: _accepting,
                  onChanged: _toggleAccepting,
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: Colors.grey.shade300),
          SizedBox(height: AppSpacing.md),
          if (_accepting)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _acceptingBody(),
              ),
            ),
        ],
      ),
    );
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _togglePicker(String key) {
    final bool willOpen = _openPicker != key;
    setState(() => _openPicker = willOpen ? key : null);
    if (!willOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? ctx = _pickerAnchorKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  List<Widget> _acceptingBody() {
    return [
      Text('Время работы',
          style: AppTextStyles.bodyL.copyWith(fontWeight: FontWeight.w700)),
      SizedBox(height: 12.h),
      Row(
        children: [
          Expanded(
            child: PickerField(
              hint: 'С',
              value: _timeFrom == null ? null : _fmtTime(_timeFrom!),
              iconAsset: 'assets/icons/ui/clock_active.webp',
              iconAssetInactive: 'assets/icons/ui/clock_inactive.webp',
              active: _openPicker == 'timeFrom',
              enabled: !_allDay,
              onTap: _allDay ? null : () => _togglePicker('timeFrom'),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: PickerField(
              hint: 'По',
              value: _timeTo == null ? null : _fmtTime(_timeTo!),
              iconAsset: 'assets/icons/ui/clock_active.webp',
              iconAssetInactive: 'assets/icons/ui/clock_inactive.webp',
              active: _openPicker == 'timeTo',
              enabled: !_allDay,
              onTap: _allDay ? null : () => _togglePicker('timeTo'),
            ),
          ),
        ],
      ),
      if (_openPicker == 'timeFrom' || _openPicker == 'timeTo') ...[
        SizedBox(height: 8.h),
        InlineTimePicker(
          key: _pickerAnchorKey,
          selected: _openPicker == 'timeFrom' ? _timeFrom : _timeTo,
          onDone: (TimeOfDay t) {
            setState(() {
              if (_openPicker == 'timeFrom') {
                _timeFrom = t;
              } else {
                _timeTo = t;
              }
              _openPicker = null;
            });
          },
          onCancel: () => setState(() => _openPicker = null),
        ),
      ],
      SizedBox(height: 8.h),
      CheckRow(
        label: 'Весь день',
        value: _allDay,
        onChanged: (bool v) => setState(() {
          _allDay = v;
          if (v) _openPicker = null;
        }),
      ),
      SizedBox(height: 24.h),
      Text('Спецтехника',
          style: AppTextStyles.bodyL.copyWith(fontWeight: FontWeight.w700)),
      SizedBox(height: 12.h),
      if (_machinery.isEmpty)
        _NoServicesHint()
      else
        _buildChipGrid(_machinery, _selMach),
      SizedBox(height: 24.h),
      Text('Категории услуг',
          style: AppTextStyles.bodyL.copyWith(fontWeight: FontWeight.w700)),
      SizedBox(height: 12.h),
      if (_categories.isEmpty)
        _NoServicesHint()
      else
        _buildChipGrid(_categories, _selCat),
      SizedBox(height: 24.h),
      Text('Местоположение',
          style: AppTextStyles.bodyL.copyWith(fontWeight: FontWeight.w700)),
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
          if (result != null && mounted) {
            setState(() {
              _location = result.value;
              _locationLat = result.lat;
              _locationLng = result.lon;
              // Дефолт 10 км — день уезжает в БД с осмысленной зоной
              // действия. Юзер может сменить чипом на 20/50.
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
            children: [
              Expanded(
                child: Text(
                  _location ?? 'Введите адрес',
                  style: AppTextStyles.body.copyWith(
                    color: _location == null
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
        _buildRadioRow(_radiusOptions[i], _radiusIndex == i, () =>
            setState(() => _radiusIndex = i)),
      SizedBox(height: 16.h),
    ];
  }

  Widget _buildChipGrid(List<String> values, Set<String> selected) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: values.map((v) {
        final sel = selected.contains(v);
        return GestureDetector(
          onTap: () => setState(() {
            sel ? selected.remove(v) : selected.add(v);
          }),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary : AppColors.surface,
              border: Border.all(color: AppColors.primary, width: 1),
              borderRadius: BorderRadius.circular(100.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(v,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.chip.copyWith(
                      color: sel ? Colors.white : AppColors.textPrimary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w400,
                    )),
                if (sel) ...[
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

  Widget _buildRadioRow(String label, bool selected, VoidCallback onTap) {
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
            Flexible(
              child: Text(label,
                  style: AppTextStyles.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// Подсказка вместо чип-сетки, когда у исполнителя нет ни одной услуги.
/// Раньше на этом месте показывались фейк-услуги из `ServiceData.presets`
/// (Экскаватор/Самосвал/Автовышка) — пользователь мог их выбрать, но
/// они не имели отношения к его реальному прайсу.
class _NoServicesHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.fieldFill,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(
        'Сначала добавьте услуги в разделе «Мои услуги» — '
        'из них соберутся доступные техника и категории.',
        style: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}
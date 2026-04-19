import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';

/// Длинная форма фильтра каталога. Точная вёрстка по Figma «фильтр»:
/// — Категории услуг (chips, выбранные оранжево-залитые с ×)
/// — Спецтехника (chips)
/// — Дата аренды (поля «С» / «По» + чек «Точная дата»)
/// — Время работы (поля «С» / «По» + чек «Весь день»)
/// — Местоположение (поле адреса + 3 радиуса)
class CatalogFilterScreen extends StatefulWidget {
  const CatalogFilterScreen({super.key});

  @override
  State<CatalogFilterScreen> createState() => _CatalogFilterScreenState();
}

class _CatalogFilterScreenState extends State<CatalogFilterScreen> {
  static const List<String> _serviceCategories = <String>[
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

  static const List<String> _equipment = <String>[
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

  final Set<String> _selectedCategories = <String>{};
  final Set<String> _selectedEquipment = <String>{};

  bool _exactDate = false;
  bool _wholeDay = false;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  TimeOfDay? _timeFrom;
  TimeOfDay? _timeTo;
  int? _radiusKm; // 10/20/50
  String? _address;

  /// Якорь на раскрываемый пикер даты/времени. После открытия скроллим
  /// SingleChildScrollView так, чтобы этот блок оказался примерно в
  /// центре вьюпорта — иначе на маленьких экранах он выпадает ниже
  /// видимой области и приходится руками скроллить вниз.
  final GlobalKey _pickerAnchorKey = GlobalKey();

  /// Какой инлайн-пикер сейчас открыт: null / 'dateFrom' / 'dateTo' /
  /// 'timeFrom' / 'timeTo'. Одновременно виден только один.
  String? _openPicker;

  @override
  void initState() {
    super.initState();
    _selectedCategories.addAll(AppliedFilter.categories);
    _selectedEquipment.addAll(AppliedFilter.equipment);
    _dateFrom = AppliedFilter.dateFrom;
    _dateTo = AppliedFilter.dateTo;
    _exactDate = AppliedFilter.exactDate;
    _timeFrom = AppliedFilter.timeFrom;
    _timeTo = AppliedFilter.timeTo;
    _wholeDay = AppliedFilter.wholeDay;
    _radiusKm = AppliedFilter.radiusKm;
    _address = AppliedFilter.address;
  }

  void _applyFilter() {
    AppliedFilter.categories
      ..clear()
      ..addAll(_selectedCategories);
    AppliedFilter.equipment
      ..clear()
      ..addAll(_selectedEquipment);
    AppliedFilter.dateFrom = _dateFrom;
    AppliedFilter.dateTo = _dateTo;
    AppliedFilter.exactDate = _exactDate;
    AppliedFilter.timeFrom = _timeFrom;
    AppliedFilter.timeTo = _timeTo;
    AppliedFilter.wholeDay = _wholeDay;
    AppliedFilter.radiusKm = _radiusKm;
    AppliedFilter.address = _address;
    AppliedFilter.revision.value = AppliedFilter.revision.value + 1;
    Navigator.of(context).pop(true);
  }

  static const List<String> _monthNamesGen = <String>[
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  String _formatDate(DateTime d) =>
      '${d.day} ${_monthNamesGen[d.month - 1]}';

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _togglePicker(String key) {
    final bool willOpen = _openPicker != key;
    setState(() => _openPicker = willOpen ? key : null);
    if (!willOpen) return;
    // Ждём кадр — к этому моменту пикер уже встроен в дерево и имеет
    // свой BuildContext с RenderBox, так что Scrollable.ensureVisible
    // может корректно вычислить смещение. alignment: 0.5 — блок в
    // центре вьюпорта.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20.r),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Фильтр',
            style: AppTextStyles.titleS.copyWith(color: Colors.white)),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 88.h),
        child: AiAssistantFab(
          onTap: () => GoRouter.of(context).push('/assistant/chat'),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _SectionTitle('Категории услуг'),
                      SizedBox(height: 12.h),
                      _ChipGrid(
                        values: _serviceCategories,
                        selected: _selectedCategories,
                        onToggle: (String v) => setState(() {
                          if (!_selectedCategories.add(v)) {
                            _selectedCategories.remove(v);
                          }
                        }),
                      ),
                      SizedBox(height: 24.h),
                      _SectionTitle('Спецтехника'),
                      SizedBox(height: 12.h),
                      _ChipGrid(
                        values: _equipment,
                        selected: _selectedEquipment,
                        onToggle: (String v) => setState(() {
                          if (!_selectedEquipment.add(v)) {
                            _selectedEquipment.remove(v);
                          }
                        }),
                      ),
                      SizedBox(height: 24.h),
                      _SectionTitle('Дата аренды'),
                      SizedBox(height: 12.h),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: PickerField(
                              hint: _exactDate ? '' : 'С',
                              value: _dateFrom == null
                                  ? null
                                  : _formatDate(_dateFrom!),
                              iconAsset: 'assets/icons/ui/calendar_active.webp',
                              iconAssetInactive: 'assets/icons/ui/calendar_inactive.webp',
                              active: _openPicker == 'dateFrom',
                              onTap: () => _togglePicker('dateFrom'),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: PickerField(
                              hint: 'По',
                              value: _dateTo == null
                                  ? null
                                  : _formatDate(_dateTo!),
                              iconAsset: 'assets/icons/ui/calendar_active.webp',
                              iconAssetInactive: 'assets/icons/ui/calendar_inactive.webp',
                              active: _openPicker == 'dateTo',
                              enabled: !_exactDate,
                              onTap: _exactDate
                                  ? null
                                  : () => _togglePicker('dateTo'),
                            ),
                          ),
                        ],
                      ),
                      if (_openPicker == 'dateFrom' ||
                          _openPicker == 'dateTo') ...<Widget>[
                        SizedBox(height: 8.h),
                        KeyedSubtree(
                          key: _pickerAnchorKey,
                          child: _InlineCalendar(
                          selected: _openPicker == 'dateFrom'
                              ? _dateFrom
                              : (_dateTo ?? _dateFrom),
                          minDate: _openPicker == 'dateTo'
                              ? _dateFrom
                              : null,
                          onChanged: (DateTime d) {
                            setState(() {
                              if (_openPicker == 'dateFrom') {
                                _dateFrom = d;
                                // Сбросить «По» если она раньше «С».
                                if (_dateTo != null &&
                                    _dateTo!.isBefore(d)) {
                                  _dateTo = null;
                                }
                              } else {
                                _dateTo = d;
                              }
                              _openPicker = null;
                            });
                          },
                          onCancel: () =>
                              setState(() => _openPicker = null),
                        ),
                        ),
                      ],
                      SizedBox(height: 8.h),
                      CheckRow(
                        label: 'Точная дата',
                        value: _exactDate,
                        onChanged: (bool v) => setState(() {
                          _exactDate = v;
                          if (v && _openPicker == 'dateTo') {
                            _openPicker = null;
                          }
                        }),
                      ),
                      SizedBox(height: 16.h),
                      _SectionTitle('Время работы'),
                      SizedBox(height: 12.h),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: PickerField(
                              hint: 'С',
                              value: _timeFrom == null
                                  ? null
                                  : _formatTime(_timeFrom!),
                              iconAsset: 'assets/icons/ui/clock_active.webp',
                              iconAssetInactive: 'assets/icons/ui/clock_inactive.webp',
                              active: _openPicker == 'timeFrom',
                              enabled: !_wholeDay,
                              onTap: _wholeDay
                                  ? null
                                  : () => _togglePicker('timeFrom'),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: PickerField(
                              hint: 'По',
                              value: _timeTo == null
                                  ? null
                                  : _formatTime(_timeTo!),
                              iconAsset: 'assets/icons/ui/clock_active.webp',
                              iconAssetInactive: 'assets/icons/ui/clock_inactive.webp',
                              active: _openPicker == 'timeTo',
                              enabled: !_wholeDay,
                              onTap: _wholeDay
                                  ? null
                                  : () => _togglePicker('timeTo'),
                            ),
                          ),
                        ],
                      ),
                      if (_openPicker == 'timeFrom' ||
                          _openPicker == 'timeTo') ...<Widget>[
                        SizedBox(height: 8.h),
                        InlineTimePicker(
                          key: _pickerAnchorKey,
                          selected: _openPicker == 'timeFrom'
                              ? _timeFrom
                              : _timeTo,
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
                          onCancel: () =>
                              setState(() => _openPicker = null),
                        ),
                      ],
                      SizedBox(height: 8.h),
                      CheckRow(
                        label: 'Весь день',
                        value: _wholeDay,
                        onChanged: (bool v) => setState(() {
                          _wholeDay = v;
                          if (v && (_openPicker == 'timeFrom' ||
                              _openPicker == 'timeTo')) {
                            _openPicker = null;
                          }
                        }),
                      ),
                      SizedBox(height: 16.h),
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
                            setState(() => _address = result);
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
                                  _address ?? 'Введите адрес',
                                  style: AppTextStyles.body.copyWith(
                                    color: _address == null
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
                      for (int km in const <int>[10, 20, 50])
                        _RadioRow(
                          label: 'В радиусе $km км',
                          selected: _radiusKm == km,
                          onTap: () => setState(() => _radiusKm = km),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              boxShadow: <BoxShadow>[
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
                16.h + MediaQuery.of(context).padding.bottom),
            child: PrimaryButton(
              label: 'Применить',
              onPressed: _applyFilter,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: AppTextStyles.bodyL
            .copyWith(fontWeight: FontWeight.w700));
  }
}

class _ChipGrid extends StatelessWidget {
  const _ChipGrid({
    required this.values,
    required this.selected,
    required this.onToggle,
  });
  final List<String> values;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: values.map((String v) {
        final bool sel = selected.contains(v);
        return GestureDetector(
          onTap: () => onToggle(v),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary : AppColors.surface,
              border: Border.all(color: AppColors.primary, width: 1),
              borderRadius: BorderRadius.circular(100.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  v,
                  style: AppTextStyles.chip.copyWith(
                    color: sel ? Colors.white : AppColors.textPrimary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (sel) ...<Widget>[
                  SizedBox(width: 6.w),
                  Icon(Icons.close_rounded,
                      size: 14.r, color: Colors.white),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.hint,
    required this.value,
    this.iconAsset,
    this.iconAssetInactive,
    this.onTap,
    this.active = false,
    this.enabled = true,
  });
  final String hint;
  final String? value;
  final String? iconAsset;
  final String? iconAssetInactive;
  final VoidCallback? onTap;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final String? assetToUse = enabled
        ? iconAsset
        : (iconAssetInactive ?? iconAsset);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 44.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.fieldFill
              : const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: active && enabled
                ? AppColors.primary
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                value ?? hint,
                style: AppTextStyles.bodyMRegular.copyWith(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w400,
                  color: enabled
                      ? (value == null
                          ? AppColors.textTertiary
                          : AppColors.textPrimary)
                      : Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
            if (assetToUse != null)
              Image.asset(assetToUse, width: 22.r, height: 22.r,
                  fit: BoxFit.contain),
          ],
        ),
      ),
    );
  }
}

class CheckRow extends StatelessWidget {
  const CheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6.h),
        child: Row(
          children: <Widget>[
            Container(
              width: 20.r,
              height: 20.r,
              decoration: BoxDecoration(
                color: value ? AppColors.primary : AppColors.surface,
                border: Border.all(
                  color: value ? AppColors.primary : AppColors.border,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(4.r),
              ),
              child: value
                  ? Icon(Icons.check, size: 14.r, color: Colors.white)
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

/// Инлайн-календарь, встроенный в скролл фильтра.
class _InlineCalendar extends StatefulWidget {
  const _InlineCalendar({
    required this.selected,
    required this.onChanged,
    required this.onCancel,
    this.minDate,
  });

  final DateTime? selected;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onCancel;
  /// Минимально допустимая дата (для пикера «По» — дата «С»).
  final DateTime? minDate;

  @override
  State<_InlineCalendar> createState() => _InlineCalendarState();
}

class _InlineCalendarState extends State<_InlineCalendar> {
  late DateTime _picked;
  late DateTime _displayedMonth;
  late DateTime _firstDate;
  late DateTime _lastDate;
  late PageController _pageCtrl;
  late int _totalMonths;

  static const List<String> _monthNames = <String>[
    'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
    'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
  ];

  static const List<String> _weekDays = <String>[
    'П', 'В', 'С', 'Ч', 'П', 'С', 'В',
  ];

  @override
  void initState() {
    super.initState();
    _picked = widget.selected ?? DateTime.now();
    _displayedMonth = DateTime(_picked.year, _picked.month);
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    _firstDate = widget.minDate != null && widget.minDate!.isAfter(today)
        ? DateUtils.dateOnly(widget.minDate!)
        : today;
    _lastDate = today.add(const Duration(days: 365));
    _totalMonths = (_lastDate.year - _firstDate.year) * 12 +
        _lastDate.month - _firstDate.month + 1;
    final int initPage = (_displayedMonth.year - _firstDate.year) * 12 +
        _displayedMonth.month - _firstDate.month;
    _pageCtrl = PageController(initialPage: initPage);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  DateTime _monthFromPage(int page) {
    final int m = _firstDate.month + page;
    return DateTime(_firstDate.year + (m - 1) ~/ 12, (m - 1) % 12 + 1);
  }

  bool get _canGoBack {
    final DateTime prev = DateTime(_displayedMonth.year, _displayedMonth.month - 1);
    return !prev.isBefore(DateTime(_firstDate.year, _firstDate.month));
  }

  bool get _canGoForward {
    final DateTime next = DateTime(_displayedMonth.year, _displayedMonth.month + 1);
    return !next.isAfter(DateTime(_lastDate.year, _lastDate.month));
  }

  void _prevMonth() {
    if (!_canGoBack) return;
    _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _nextMonth() {
    if (!_canGoForward) return;
    _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _onPageChanged(int page) {
    setState(() => _displayedMonth = _monthFromPage(page));
  }

  int _rowCountForMonth(DateTime month) {
    final DateTime first = DateTime(month.year, month.month, 1);
    final int daysCount = DateUtils.getDaysInMonth(month.year, month.month);
    final int leadingCount = first.weekday - 1;
    final int totalCells = leadingCount + daysCount;
    return (totalCells / 7).ceil();
  }

  List<DateTime> _daysForMonth(DateTime displayedMonth) {
    final int year = displayedMonth.year;
    final int month = displayedMonth.month;
    final DateTime first = DateTime(year, month, 1);
    final int daysCount = DateUtils.getDaysInMonth(year, month);
    final int startWeekday = first.weekday; // Пн=1 .. Вс=7
    final int leadingCount = startWeekday - 1;

    final List<DateTime> cells = <DateTime>[];
    // Дни предыдущего месяца.
    if (leadingCount > 0) {
      final DateTime prevMonth = DateTime(year, month, 0); // последний день пред. месяца
      for (int i = leadingCount - 1; i >= 0; i--) {
        cells.add(DateTime(prevMonth.year, prevMonth.month, prevMonth.day - i));
      }
    }
    // Дни текущего месяца.
    for (int d = 1; d <= daysCount; d++) {
      cells.add(DateTime(year, month, d));
    }
    // Дни следующего месяца (добить до полных недель).
    final int trailing = (7 - cells.length % 7) % 7;
    for (int d = 1; d <= trailing; d++) {
      cells.add(DateTime(year, month + 1, d));
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final String header =
        '${_monthNames[_displayedMonth.month - 1]} ${_displayedMonth.year} г.';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFFD1D1D6)),
      ),
      padding: EdgeInsets.symmetric(vertical: 16.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Хедер: < месяц год г. >
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: <Widget>[
                GestureDetector(
                  onTap: _canGoBack ? _prevMonth : null,
                  child: Icon(Icons.chevron_left,
                      size: 20.r,
                      color: _canGoBack
                          ? AppColors.textPrimary
                          : AppColors.textTertiary),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      header,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _canGoForward ? _nextMonth : null,
                  child: Icon(Icons.chevron_right,
                      size: 20.r,
                      color: _canGoForward
                          ? AppColors.textPrimary
                          : AppColors.textTertiary),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          // Заголовки дней недели (статичные, не свайпятся).
          Row(
            children: _weekDays
                .map((String d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          SizedBox(height: 8.h),
          // Сетка дней — PageView для свайпа пальцем.
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            height: 40.h * _rowCountForMonth(_displayedMonth),
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: _totalMonths,
              onPageChanged: _onPageChanged,
              itemBuilder: (BuildContext context, int page) {
                final DateTime month = _monthFromPage(page);
                final List<DateTime> days = _daysForMonth(month);
                final int rowCount = (days.length / 7).ceil();
                return Table(
                  children: <TableRow>[
                    for (int r = 0; r < rowCount; r++)
                      TableRow(
                        children: <Widget>[
                          for (int c = 0; c < 7; c++)
                            () {
                              final int idx = r * 7 + c;
                              if (idx >= days.length) {
                                return const SizedBox.shrink();
                              }
                              final DateTime date = days[idx];
                              final DateTime dateOnly =
                                  DateUtils.dateOnly(date);
                              final bool isCurrentMonth =
                                  date.month == month.month;
                              final bool isSelected =
                                  DateUtils.dateOnly(_picked) == dateOnly;
                              final bool isToday = dateOnly == today;
                              final bool disabled =
                                  dateOnly.isBefore(_firstDate) ||
                                      dateOnly.isAfter(_lastDate);

                              Color bg = Colors.transparent;
                              Color fg = isCurrentMonth
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary;
                              Border? border;

                              if (isSelected && isCurrentMonth) {
                                bg = AppColors.primary;
                                fg = Colors.white;
                              } else if (isToday) {
                                border = Border.all(
                                    color: AppColors.primary, width: 1.5);
                                fg = AppColors.primary;
                              }
                              if (disabled) fg = AppColors.textTertiary;

                              return GestureDetector(
                                onTap: disabled || !isCurrentMonth
                                    ? null
                                    : () =>
                                        setState(() => _picked = dateOnly),
                                child: Center(
                                  child: Container(
                                    width: 34.r,
                                    height: 34.r,
                                    margin: EdgeInsets.symmetric(
                                        vertical: 3.h),
                                    decoration: BoxDecoration(
                                      color: bg,
                                      borderRadius:
                                          BorderRadius.circular(8.r),
                                      border: border,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: 14.sp,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: fg,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }(),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
          SizedBox(height: 5.h),
          // Кнопки.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onCancel,
                  child: Text(
                    'Отмена',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(width: 24.w),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onChanged(_picked),
                  child: Text(
                    'Готово',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Инлайн-пикер времени (два колеса: часы + минуты).
class InlineTimePicker extends StatefulWidget {
  const InlineTimePicker({
    super.key,
    required this.selected,
    required this.onDone,
    required this.onCancel,
  });

  final TimeOfDay? selected;
  final ValueChanged<TimeOfDay> onDone;
  final VoidCallback onCancel;

  @override
  State<InlineTimePicker> createState() => InlineTimePickerState();
}

class InlineTimePickerState extends State<InlineTimePicker> {
  late int _hour;
  late int _minute;
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minuteCtrl;

  @override
  void initState() {
    super.initState();
    _hour = widget.selected?.hour ?? TimeOfDay.now().hour;
    _minute = widget.selected?.minute ?? 0;
    _hourCtrl = FixedExtentScrollController(initialItem: _hour);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  void _commit() {
    widget.onDone(TimeOfDay(hour: _hour, minute: _minute));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFFD1D1D6)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.r, vertical: 12.r),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 229,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 24.w),
                    child: ListWheelScrollView.useDelegate(
                      controller: _hourCtrl,
                      itemExtent: 42,
                      physics: const FixedExtentScrollPhysics(),
                      onSelectedItemChanged: (int i) {
                        _hour = i;
                        setState(() {});
                      },
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: 24,
                        builder: (BuildContext context, int i) {
                          final bool sel = i == _hour;
                          return Center(
                            child: Container(
                              padding:
                                  EdgeInsets.symmetric(horizontal: 19.w),
                              decoration: sel
                                  ? BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.12),
                                      borderRadius:
                                          BorderRadius.circular(8.r),
                                    )
                                  : null,
                              child: Text(
                                i.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 25,
                                  fontWeight:
                                      sel ? FontWeight.w600 : FontWeight.w400,
                                  color: sel
                                      ? AppColors.textPrimary
                                      : AppColors.textTertiary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Text(
                  ':',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 25.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: 24.w),
                    child: ListWheelScrollView.useDelegate(
                      controller: _minuteCtrl,
                      itemExtent: 42,
                      physics: const FixedExtentScrollPhysics(),
                      onSelectedItemChanged: (int i) {
                        _minute = i;
                        setState(() {});
                      },
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: 60,
                        builder: (BuildContext context, int i) {
                          final bool sel = i == _minute;
                          return Center(
                            child: Container(
                              padding:
                                  EdgeInsets.symmetric(horizontal: 19.w),
                              decoration: sel
                                  ? BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.12),
                                      borderRadius:
                                          BorderRadius.circular(8.r),
                                    )
                                  : null,
                              child: Text(
                                i.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 25,
                                  fontWeight:
                                      sel ? FontWeight.w600 : FontWeight.w400,
                                  color: sel
                                      ? AppColors.textPrimary
                                      : AppColors.textTertiary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onCancel,
                child: Text(
                  'Отмена',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              SizedBox(width: 24.w),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _commit,
                child: Text(
                  'Готово',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom Sheet для выбора адреса в фильтре «Местоположение».
class AddressBottomSheet extends StatefulWidget {
  const AddressBottomSheet({super.key});

  @override
  State<AddressBottomSheet> createState() => AddressBottomSheetState();
}

class AddressBottomSheetState extends State<AddressBottomSheet> {
  final TextEditingController _ctrl = TextEditingController();
  String _query = '';

  static const List<MockAddress> _all = <MockAddress>[
    MockAddress('Моё местоположение', null),
    MockAddress('Адрес', 'Москва, Московская область'),
    MockAddress('Адрес', 'Москва, Московская область'),
    MockAddress('Адрес', 'Москва, Московская область'),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
          ),
          child: Column(
            children: <Widget>[
              SizedBox(height: 16.h),
              // Поле поиска.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Container(
                  height: 44.h,
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: const Color(0xFF949393)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Image.asset(
                        'assets/icons/ui/location.webp',
                        width: 20.r,
                        height: 20.r,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          autofocus: true,
                          inputFormatters: [LengthLimitingTextInputFormatter(100)],
                          onChanged: (String v) =>
                              setState(() => _query = v),
                          style: AppTextStyles.bodyMRegular.copyWith(
                            fontSize: 16.sp,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Введите адрес',
                            hintStyle: AppTextStyles.bodyMRegular.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 16.sp,
                            ),
                            isDense: true,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              // Список адресов.
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  itemCount: _all.length,
                  itemBuilder: (BuildContext context, int i) {
                    final MockAddress a = _all[i];
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(a.title),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        child: Row(
                          children: <Widget>[
                            Image.asset(
                              'assets/icons/ui/location.webp',
                              width: 20.r,
                              height: 20.r,
                              fit: BoxFit.contain,
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    a.title,
                                    style: AppTextStyles.bodyMRegular
                                        .copyWith(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  if (a.subtitle != null) ...<Widget>[
                                    SizedBox(height: 2.h),
                                    Text(
                                      a.subtitle!,
                                      style: AppTextStyles.bodyMRegular
                                          .copyWith(
                                        fontSize: 13.sp,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Глобальное состояние применённого фильтра каталога. Лента заказов
/// слушает `revision` и пересчитывает выдачу при изменении.
class AppliedFilter {
  AppliedFilter._();

  static final Set<String> categories = <String>{};
  static final Set<String> equipment = <String>{};
  static DateTime? dateFrom;
  static DateTime? dateTo;
  static bool exactDate = false;
  static TimeOfDay? timeFrom;
  static TimeOfDay? timeTo;
  static bool wholeDay = false;
  static int? radiusKm;
  static String? address;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void clear() {
    categories.clear();
    equipment.clear();
    dateFrom = null;
    dateTo = null;
    exactDate = false;
    timeFrom = null;
    timeTo = null;
    wholeDay = false;
    radiusKm = null;
    address = null;
    revision.value = revision.value + 1;
  }
}

class MockAddress {
  const MockAddress(this.title, this.subtitle);
  final String title;
  final String? subtitle;
}

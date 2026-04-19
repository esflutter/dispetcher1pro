import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/schedule/schedule_screen.dart';
import 'package:dispatcher_1/features/schedule/widgets/schedule_alerts.dart';

/// Экран «Параметры дня» для группы «Мой график».
class DaySettingsScreen extends StatefulWidget {
  const DaySettingsScreen({
    super.key,
    required this.dayLabel,
    required this.initialState,
  });

  final String dayLabel;
  final DayState initialState;

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

  /// Якорь на раскрываемый пикер времени — чтобы после открытия
  /// скроллить форму до центра вьюпорта и пикер не выпадал ниже.
  final GlobalKey _pickerAnchorKey = GlobalKey();

  final Set<String> _selMach = {};
  final Set<String> _selCat = {};

  static const _radiusOptions = [
    'В радиусе 10 км',
    'В радиусе 20 км',
    'В радиусе 50 км',
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

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
    _accepting = _state == DayState.hasOrders;
  }

  Future<void> _toggleAccepting(bool value) async {
    if (!value && _state == DayState.hasOrders) {
      final bool? ok = await ScheduleAlerts.showCloseAcceptance(context);
      if (ok != true) return;
    }
    setState(() {
      _accepting = value;
      _state = value ? DayState.hasOrders : DayState.noOrders;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Параметры дня'),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 88.h),
        child: AiAssistantFab(onTap: () => context.push('/assistant/chat')),
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
                label: 'Сохранить',
                onPressed: () => Navigator.of(context).pop(_state),
              ),
            ),
          ],
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
      _buildChipGrid(_machinery, _selMach),
      SizedBox(height: 24.h),
      Text('Категории услуг',
          style: AppTextStyles.bodyL.copyWith(fontWeight: FontWeight.w700)),
      SizedBox(height: 12.h),
      _buildChipGrid(_categories, _selCat),
      SizedBox(height: 24.h),
      Text('Местоположение',
          style: AppTextStyles.bodyL.copyWith(fontWeight: FontWeight.w700)),
      SizedBox(height: 12.h),
      GestureDetector(
        onTap: () async {
          final String? result = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const AddressBottomSheet(),
          );
          if (result != null) setState(() => _location = result);
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
            Text(label, style: AppTextStyles.body),
          ],
        ),
      ),
    );
  }
}

class _HourField extends StatelessWidget {
  const _HourField({
    required this.label,
    required this.hour,
    required this.onChanged,
  });

  final String label;
  final int hour;
  final ValueChanged<int> onChanged;

  String _f(int v) => '${v.toString().padLeft(2, '0')}:00';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: hour, minute: 0),
        );
        if (picked != null) onChanged(picked.hour);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52.h,
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.fieldFill,
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        ),
        child: Row(
          children: [
            Text('$label   ', style: AppTextStyles.body),
            Expanded(child: Text(_f(hour), style: AppTextStyles.body)),
            Icon(Icons.access_time_rounded,
                size: 20.r, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

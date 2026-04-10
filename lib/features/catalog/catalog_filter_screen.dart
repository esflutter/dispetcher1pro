import 'package:flutter/material.dart';
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
    'Погрузчик',
    'Миниэкскаватор',
    'Минипогрузчик',
    'Буроям',
    'Самогруз',
    'Автокран',
    'Самосвалы (до 5тн, 15, 25)',
    'Бетононасос',
    'Эвакуатор',
    'Автовышка',
    'Манипулятор',
    'Минитрактор',
    'Экскаватор',
    'Инертные материалы',
  ];

  final Set<String> _selectedCategories = <String>{
    'Земляные работы',
    'Погрузочно-разгрузочные работы',
  };
  final Set<String> _selectedEquipment = <String>{
    'Экскаватор-погрузчик',
    'Погрузчик',
  };

  bool _exactDate = false;
  bool _wholeDay = false;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  TimeOfDay? _timeFrom;
  TimeOfDay? _timeTo;
  int? _radiusKm; // 10/20/50

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${(d.year % 100).toString().padLeft(2, '0')}';

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool isFrom) async {
    final DateTime now = DateTime.now();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_dateFrom ?? now) : (_dateTo ?? now),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null) return;
    setState(() {
      if (isFrom) {
        _dateFrom = d;
      } else {
        _dateTo = d;
      }
    });
  }

  Future<void> _pickTime(bool isFrom) async {
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: isFrom ? (_timeFrom ?? TimeOfDay.now()) : (_timeTo ?? TimeOfDay.now()),
    );
    if (t == null) return;
    setState(() {
      if (isFrom) {
        _timeFrom = t;
      } else {
        _timeTo = t;
      }
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
        padding: EdgeInsets.only(bottom: 24.h),
        child: AiAssistantFab(
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
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
                            child: _PickerField(
                              hint: 'С',
                              value: _dateFrom == null
                                  ? null
                                  : _formatDate(_dateFrom!),
                              icon: Icons.calendar_today_outlined,
                              onTap: () => _pickDate(true),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: _PickerField(
                              hint: 'По',
                              value: _dateTo == null
                                  ? null
                                  : _formatDate(_dateTo!),
                              icon: Icons.calendar_today_outlined,
                              onTap: () => _pickDate(false),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      _CheckRow(
                        label: 'Точная дата',
                        value: _exactDate,
                        onChanged: (bool v) =>
                            setState(() => _exactDate = v),
                      ),
                      SizedBox(height: 16.h),
                      _SectionTitle('Время работы'),
                      SizedBox(height: 12.h),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _PickerField(
                              hint: 'С',
                              value: _timeFrom == null
                                  ? null
                                  : _formatTime(_timeFrom!),
                              icon: Icons.access_time,
                              onTap: () => _pickTime(true),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: _PickerField(
                              hint: 'По',
                              value: _timeTo == null
                                  ? null
                                  : _formatTime(_timeTo!),
                              icon: Icons.access_time,
                              onTap: () => _pickTime(false),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      _CheckRow(
                        label: 'Весь день',
                        value: _wholeDay,
                        onChanged: (bool v) =>
                            setState(() => _wholeDay = v),
                      ),
                      SizedBox(height: 16.h),
                      _SectionTitle('Местоположение'),
                      SizedBox(height: 12.h),
                      _AddressField(),
                      SizedBox(height: 12.h),
                      for (int km in const <int>[10, 20, 50])
                        _RadioRow(
                          label: 'В радиусе $km км',
                          selected: _radiusKm == km,
                          onTap: () => setState(() => _radiusKm = km),
                        ),
                      SizedBox(height: 24.h),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                child: PrimaryButton(
                  label: 'Применить',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
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
        style: AppTextStyles.bodyMedium
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

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.hint,
    required this.value,
    required this.icon,
    required this.onTap,
  });
  final String hint;
  final String? value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                value ?? hint,
                style: AppTextStyles.bodyMRegular.copyWith(
                  color: value == null
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            Icon(icon, size: 18.r, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
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
            Text(label, style: AppTextStyles.bodyMRegular),
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
        padding: EdgeInsets.symmetric(vertical: 6.h),
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
            Text(label, style: AppTextStyles.bodyMRegular),
          ],
        ),
      ),
    );
  }
}

class _AddressField extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44.h,
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: AppColors.fieldFill,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              style: AppTextStyles.bodyMRegular,
              decoration: InputDecoration(
                hintText: 'Введите адрес',
                hintStyle: AppTextStyles.bodyMRegular
                    .copyWith(color: AppColors.textTertiary),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

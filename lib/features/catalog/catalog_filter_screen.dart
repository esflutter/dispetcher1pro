import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Длинная форма фильтра каталога (Figma 16:4545).
/// Секции: Категории услуг → Спецтехника → Дата аренды → Время работы.
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
  DateTimeRange? _dateRange;
  RangeValues _hours = const RangeValues(2, 12);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: AppColors.surface,
        elevation: 0,
        title: Text('Фильтр',
            style: AppTextStyles.titleS.copyWith(color: AppColors.surface)),
        actions: <Widget>[
          TextButton(
            onPressed: () => setState(() {
              _selectedCategories.clear();
              _selectedEquipment.clear();
              _dateRange = null;
              _hours = const RangeValues(2, 12);
            }),
            child: Text('Сбросить',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.primary)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSpacing.screenH),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SectionTitle('Категории услуг'),
                    SizedBox(height: AppSpacing.sm),
                    _ChipGrid(
                      values: _serviceCategories,
                      selected: _selectedCategories,
                      onToggle: (String v) => setState(() {
                        _selectedCategories.contains(v)
                            ? _selectedCategories.remove(v)
                            : _selectedCategories.add(v);
                      }),
                    ),
                    SizedBox(height: AppSpacing.xl),
                    _SectionTitle('Спецтехника'),
                    SizedBox(height: AppSpacing.sm),
                    _ChipGrid(
                      values: _equipment,
                      selected: _selectedEquipment,
                      onToggle: (String v) => setState(() {
                        _selectedEquipment.contains(v)
                            ? _selectedEquipment.remove(v)
                            : _selectedEquipment.add(v);
                      }),
                    ),
                    SizedBox(height: AppSpacing.xl),
                    _SectionTitle('Дата аренды'),
                    SizedBox(height: AppSpacing.sm),
                    _DatePickerField(
                      range: _dateRange,
                      onTap: () async {
                        final DateTime now = DateTime.now();
                        final DateTimeRange? r = await showDateRangePicker(
                          context: context,
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 365)),
                        );
                        if (r != null) {
                          setState(() => _dateRange = r);
                        }
                      },
                    ),
                    SizedBox(height: AppSpacing.xl),
                    _SectionTitle('Время работы'),
                    RangeSlider(
                      min: 1,
                      max: 24,
                      divisions: 23,
                      values: _hours,
                      labels: RangeLabels(
                        '${_hours.start.round()} ч',
                        '${_hours.end.round()} ч',
                      ),
                      activeColor: AppColors.primary,
                      inactiveColor: AppColors.divider,
                      onChanged: (RangeValues v) =>
                          setState(() => _hours = v),
                    ),
                    SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(AppSpacing.screenH),
              child: PrimaryButton(
                label: 'Применить',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTextStyles.bodyMedium);
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
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: values.map((String v) {
        final bool sel = selected.contains(v);
        return GestureDetector(
          onTap: () => onToggle(v),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 6.h,
            ),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Text(
              v,
              style: AppTextStyles.chip.copyWith(
                color: sel ? AppColors.surface : AppColors.textPrimary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({required this.range, required this.onTap});
  final DateTimeRange? range;
  final VoidCallback onTap;

  String _format(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final String text = range == null
        ? 'Выбрать даты'
        : '${_format(range!.start)} — ${_format(range!.end)}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56.h,
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.calendar_today_outlined,
                size: 20.r, color: AppColors.textSecondary),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.bodyMRegular.copyWith(
                  color: range == null
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';

/// Горизонтальный ряд оранжевых чипов с применёнными фильтрами.
/// По тапу на × чип удаляется и `AppliedFilter.revision` инкрементится.
class AppliedFilterChips extends StatelessWidget {
  const AppliedFilterChips({super.key, required this.onChanged});

  final VoidCallback onChanged;

  static const List<String> _months = <String>[
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _bump() {
    AppliedFilter.revision.value = AppliedFilter.revision.value + 1;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final List<_ChipSpec> chips = <_ChipSpec>[];

    for (final String v in AppliedFilter.equipment) {
      chips.add(_ChipSpec(v, () {
        AppliedFilter.equipment.remove(v);
        _bump();
      }));
    }
    for (final String v in AppliedFilter.categories) {
      chips.add(_ChipSpec(v, () {
        AppliedFilter.categories.remove(v);
        _bump();
      }));
    }

    if (AppliedFilter.dateFrom != null) {
      final String label = AppliedFilter.exactDate ||
              AppliedFilter.dateTo == null ||
              AppliedFilter.dateTo == AppliedFilter.dateFrom
          ? _fmtDate(AppliedFilter.dateFrom!)
          : '${_fmtDate(AppliedFilter.dateFrom!)} – ${_fmtDate(AppliedFilter.dateTo!)}';
      chips.add(_ChipSpec(label, () {
        AppliedFilter.dateFrom = null;
        AppliedFilter.dateTo = null;
        AppliedFilter.exactDate = false;
        _bump();
      }));
    }

    if (AppliedFilter.wholeDay) {
      chips.add(_ChipSpec('Весь день', () {
        AppliedFilter.wholeDay = false;
        _bump();
      }));
    } else if (AppliedFilter.timeFrom != null &&
        AppliedFilter.timeTo != null) {
      chips.add(_ChipSpec(
          '${_fmtTime(AppliedFilter.timeFrom!)}–${_fmtTime(AppliedFilter.timeTo!)}',
          () {
        AppliedFilter.timeFrom = null;
        AppliedFilter.timeTo = null;
        _bump();
      }));
    }

    if (AppliedFilter.radiusKm != null) {
      chips.add(_ChipSpec('В радиусе ${AppliedFilter.radiusKm} км', () {
        AppliedFilter.radiusKm = null;
        _bump();
      }));
    }
    if (AppliedFilter.address != null && AppliedFilter.address!.isNotEmpty) {
      chips.add(_ChipSpec(AppliedFilter.address!, () {
        AppliedFilter.address = null;
        _bump();
      }));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < chips.length; i++) ...<Widget>[
              if (i > 0) SizedBox(width: 8.w),
              _FilterChip(label: chips[i].label, onRemove: chips[i].onRemove),
            ],
          ],
        ),
      ),
    );
  }
}

/// Есть ли хотя бы один активный фильтр — удобный геттер для красной
/// точки-бейджа над иконкой фильтров.
bool hasActiveFilter() {
  return AppliedFilter.categories.isNotEmpty ||
      AppliedFilter.equipment.isNotEmpty ||
      AppliedFilter.dateFrom != null ||
      AppliedFilter.dateTo != null ||
      AppliedFilter.timeFrom != null ||
      AppliedFilter.timeTo != null ||
      AppliedFilter.wholeDay ||
      AppliedFilter.radiusKm != null ||
      (AppliedFilter.address != null && AppliedFilter.address!.isNotEmpty);
}

class _ChipSpec {
  const _ChipSpec(this.label, this.onRemove);
  final String label;
  final VoidCallback onRemove;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // Стиль — идентичный выбранным чипам в фильтре (_ChipGrid).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onRemove,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: AppColors.primary,
          border: Border.all(color: AppColors.primary, width: 1),
          borderRadius: BorderRadius.circular(100.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: AppTextStyles.chip.copyWith(
                color: Colors.white,
                fontSize: 13.sp,
                fontWeight: FontWeight.w400,
              ),
            ),
            SizedBox(width: 6.w),
            Icon(Icons.close_rounded, size: 14.r, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

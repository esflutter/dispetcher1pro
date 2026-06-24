import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';

/// Горизонтальный ряд оранжевых чипов с применёнными фильтрами.
/// По тапу на × чип удаляется и `AppliedFilter.revision` инкрементится.
class AppliedFilterChips extends StatelessWidget {
  const AppliedFilterChips({
    super.key,
    required this.onChanged,
    this.topPadding,
  });

  final VoidCallback onChanged;

  /// Вертикальный отступ сверху. По умолчанию 12.h — симметрично снизу,
  /// как в ленте каталога. На карте шапка компактнее, там передаётся 0,
  /// чтобы чипы шли сразу под строкой поиска.
  final double? topPadding;

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

    // Один чип на «адрес + радиус» — это одна логическая настройка.
    // Показываем радиус, по крестику снимаем оба поля.
    if (AppliedFilter.radiusKm != null) {
      chips.add(_ChipSpec('В радиусе ${AppliedFilter.radiusKm} км', () {
        AppliedFilter.radiusKm = null;
        AppliedFilter.address = null;
        AppliedFilter.addressLat = null;
        AppliedFilter.addressLng = null;
        _bump();
      }));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(16.w, topPadding ?? 12.h, 16.w, 12.h),
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

/// True только если реально отрисуется хотя бы один chip. Значения,
/// которые не попадают ни в один chip (например, одиночный `timeFrom`
/// без `timeTo`, `address` без `radiusKm`), не делают фильтр
/// «активным» — иначе зажигалась бы красная точка над иконкой без
/// видимой причины, и чип-ряд прибавлял бы ноль-высотный паддинг,
/// прижимая верхнюю карточку к AppBar.
bool hasActiveFilter() {
  if (AppliedFilter.categories.isNotEmpty) return true;
  if (AppliedFilter.equipment.isNotEmpty) return true;
  if (AppliedFilter.dateFrom != null) return true;
  if (AppliedFilter.wholeDay) return true;
  if (AppliedFilter.timeFrom != null && AppliedFilter.timeTo != null) {
    return true;
  }
  if (AppliedFilter.radiusKm != null) return true;
  return false;
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

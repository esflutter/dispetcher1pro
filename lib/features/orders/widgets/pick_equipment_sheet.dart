import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Шторка-подтверждение «по каким техникам берёшь заказ» для статуса
/// `waitingConfirm`. Реальный `service_id` уже зафиксирован в
/// `order_matches` при предложении заказчиком — этот выбор не меняет
/// привязку, нужен только как UX-чеклист, чтобы исполнитель ещё раз
/// явно подтвердил, что готов работать всеми указанными в заказе
/// видами техники. Возвращает выбранные `List<String>` через
/// `Navigator.pop`. Отмена возвращает `null`.
class PickEquipmentSheet extends StatefulWidget {
  const PickEquipmentSheet({
    super.key,
    required this.options,
    this.ctaLabel = 'Подтвердить',
  });

  final List<String> options;
  final String ctaLabel;

  @override
  State<PickEquipmentSheet> createState() => _PickEquipmentSheetState();
}

class _PickEquipmentSheetState extends State<PickEquipmentSheet> {
  final Set<String> _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16.w,
        12.h,
        16.w,
        16.h + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(height: 16.h),
          Text(
            'Подтвердите технику, на которой\nвы готовы выполнить работу',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          SizedBox(height: 16.h),
          for (final String e in widget.options)
            _CheckRow(
              label: e,
              checked: _picked.contains(e),
              onTap: () {
                setState(() {
                  if (!_picked.add(e)) _picked.remove(e);
                });
              },
            ),
          SizedBox(height: 16.h),
          PrimaryButton(
            label: widget.ctaLabel,
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.of(context).pop(_picked.toList()),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        child: Row(
          children: <Widget>[
            Container(
              width: 24.r,
              height: 24.r,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(6.r),
                color: checked ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color:
                      checked ? AppColors.primary : AppColors.textTertiary,
                  width: 1.5,
                ),
              ),
              child: checked
                  ? Icon(Icons.check_rounded, size: 18.r, color: Colors.white)
                  : null,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

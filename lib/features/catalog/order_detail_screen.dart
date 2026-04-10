import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/customer_card_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/widgets/respond_bottom_sheet.dart';

/// Карточка заказа (детали). По Figma — заголовок заказчика сверху,
/// далее «номер заказа → заголовок → дата публикации → секции».
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.multipleEquipment = false,
  });

  final String orderId;
  final bool multipleEquipment;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  static const List<String> _multiEquipment = <String>[
    'Экскаватор',
    'Автокран',
    'Манипулятор',
    'Погрузчик',
    'Автовышка',
  ];

  bool _verified = true;

  Future<void> _onRespondTap() async {
    if (widget.multipleEquipment) {
      final List<String>? picked = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _PickEquipmentSheet(options: _multiEquipment),
      );
      if (picked == null || !mounted) {
        return;
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => RespondModalDialog(verified: _verified),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> equipment = widget.multipleEquipment
        ? _multiEquipment
        : const <String>['Экскаватор'];

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
        title: Text(
          'Нужен экскаватор для копки тран...',
          style: AppTextStyles.titleS.copyWith(color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          // Переключатель «верифицирован» только для прототипа.
          IconButton(
            icon: Icon(
              _verified ? Icons.verified : Icons.verified_outlined,
              color: Colors.white,
              size: 22.r,
            ),
            onPressed: () => setState(() => _verified = !_verified),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 24.h),
        child: AiAssistantFab(
          onTap: () => context.push('/assistant/chat'),
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
                      _CustomerHeader(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const CustomerCardScreen(customerId: '1'),
                          ),
                        ),
                      ),
                      SizedBox(height: 14.h),
                      Text('№123456',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textTertiary)),
                      SizedBox(height: 4.h),
                      Text('Разработка котлована под фундамент',
                          style: AppTextStyles.titleL.copyWith(
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 4.h),
                      Text('Вчера в 14:30',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textTertiary)),
                      SizedBox(height: 16.h),
                      _Section(
                        title: 'Дата и время аренды',
                        child: Text('15 июня · 09:00–18:00',
                            style: AppTextStyles.bodyMRegular),
                      ),
                      _Section(
                        title: 'Адрес',
                        child: Text(
                            'Московская область, Москва, Улица1, д 144',
                            style: AppTextStyles.bodyMRegular),
                      ),
                      _Section(
                        title: 'Требуемая спецтехника',
                        child: Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: equipment
                              .map((String e) => _OutlinedChip(label: e))
                              .toList(),
                        ),
                      ),
                      _Section(
                        title: 'Категория работ',
                        child: Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: const <Widget>[
                            _OutlinedChip(label: 'Земляные работы'),
                            _OutlinedChip(
                                label: 'Подготовка строительной площадки'),
                          ],
                        ),
                      ),
                      _Section(
                        title: 'Характер работ',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('Разработка грунта — 40 м³',
                                style: AppTextStyles.bodyMRegular),
                            Text('Планировка участка — 2 × 12 × 15 м',
                                style: AppTextStyles.bodyMRegular),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                child: PrimaryButton(
                  label: 'Откликнуться',
                  onPressed: _onRespondTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 24.r,
            backgroundColor: AppColors.primaryTint,
            child: Icon(Icons.person, color: AppColors.primary, size: 28.r),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Александр Иванов',
                    style: AppTextStyles.bodyMMedium
                        .copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: 2.h),
                Row(
                  children: <Widget>[
                    Icon(Icons.star_rounded,
                        size: 16.r, color: AppColors.ratingStar),
                    SizedBox(width: 4.w),
                    Text('4,5',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textPrimary)),
                    SizedBox(width: 8.w),
                    Text('15 отзывов',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: AppTextStyles.bodyMedium
                  .copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 4.h),
          child,
        ],
      ),
    );
  }
}

class _OutlinedChip extends StatelessWidget {
  const _OutlinedChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.primary, width: 1),
        borderRadius: BorderRadius.circular(100.r),
      ),
      child: Text(label,
          style: AppTextStyles.chip.copyWith(color: AppColors.textPrimary)),
    );
  }
}

class _PickEquipmentSheet extends StatefulWidget {
  const _PickEquipmentSheet({required this.options});
  final List<String> options;

  @override
  State<_PickEquipmentSheet> createState() => _PickEquipmentSheetState();
}

class _PickEquipmentSheetState extends State<_PickEquipmentSheet> {
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
          Center(
            child: Container(
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(100.r),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Выберите технику, на которой\nвы готовы выполнить работу',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleS
                .copyWith(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 16.h),
          for (final String e in widget.options)
            _CheckRow(
              label: e,
              checked: _picked.contains(e),
              onTap: () => setState(() {
                if (!_picked.add(e)) _picked.remove(e);
              }),
            ),
          SizedBox(height: 16.h),
          PrimaryButton(
            label: 'Откликнуться',
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
              width: 22.r,
              height: 22.r,
              decoration: BoxDecoration(
                color: checked ? AppColors.primary : AppColors.surface,
                border: Border.all(
                  color: checked ? AppColors.primary : AppColors.border,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(4.r),
              ),
              child: checked
                  ? Icon(Icons.check, size: 16.r, color: Colors.white)
                  : null,
            ),
            SizedBox(width: 16.w),
            Text(label, style: AppTextStyles.bodyMRegular),
          ],
        ),
      ),
    );
  }
}

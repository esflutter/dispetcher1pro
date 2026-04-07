import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/customer_card_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/respond_bottom_sheet.dart';

/// Карточка заказа (детали).
class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.multipleEquipment = false,
  });

  final String orderId;
  final bool multipleEquipment;

  static const List<String> _equipment = <String>[
    'Экскаватор-погрузчик',
    'Самосвал 10т',
  ];

  @override
  Widget build(BuildContext context) {
    final List<String> equipment =
        multipleEquipment ? _equipment : const <String>['Экскаватор-погрузчик'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: AppColors.surface,
        elevation: 0,
        title: Text('Нужен экскаватор для копки траншеи',
            style: AppTextStyles.titleS.copyWith(color: AppColors.surface)),
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
                    Text('№$orderId',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textTertiary)),
                    SizedBox(height: AppSpacing.xs),
                    Text('Разработка котлована под фундамент',
                        style: AppTextStyles.titleL),
                    SizedBox(height: AppSpacing.xxs),
                    Text('Вчера в 14:30',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textTertiary)),
                    SizedBox(height: AppSpacing.md),
                    _Section(
                      title: 'Дата и время аренды',
                      child: Text('15 июня · 09:00–18:00',
                          style: AppTextStyles.bodyMRegular),
                    ),
                    _Section(
                      title: 'Адрес',
                      child: Text('Московская область, Москва, Улица1, д 144',
                          style: AppTextStyles.bodyMRegular),
                    ),
                    _Section(
                      title: 'Требуемая спецтехника',
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: equipment
                            .map((String e) => _Chip(label: e))
                            .toList(),
                      ),
                    ),
                    _Section(
                      title: 'Категория работ',
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: const <Widget>[
                          _Chip(label: 'Земляные работы'),
                          _Chip(label: 'Подготовка строительной площадки'),
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
                    _Section(
                      title: 'Заказчик',
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const CustomerCardScreen(customerId: '1'),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            CircleAvatar(
                              radius: 24.r,
                              backgroundColor: AppColors.primaryTint,
                              child: const Icon(Icons.person,
                                  color: AppColors.primary),
                            ),
                            SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text('Александр Иванов',
                                      style: AppTextStyles.bodyMedium),
                                  Text('★ 4,5 · 15 отзывов',
                                      style: AppTextStyles.caption),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: AppColors.textTertiary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(AppSpacing.screenH),
              child: PrimaryButton(
                label: 'Откликнуться',
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const RespondBottomSheet(verified: true),
                ),
              ),
            ),
          ],
        ),
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
          Text(title, style: AppTextStyles.bodyMedium),
          SizedBox(height: 4.h),
          DefaultTextStyle.merge(
            style: AppTextStyles.subBody.copyWith(
              color: AppColors.textPrimary,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(label,
          style:
              AppTextStyles.chip.copyWith(color: AppColors.primaryDark)),
    );
  }
}

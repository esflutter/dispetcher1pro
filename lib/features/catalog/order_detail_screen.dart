import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/customer_card_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/widgets/respond_bottom_sheet.dart';
import 'package:dispatcher_1/features/catalog/widgets/subscription_paywall.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';

/// Карточка заказа (детали). По Figma — заголовок заказчика сверху,
/// далее «номер заказа → заголовок → дата публикации → секции».
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.multipleEquipment = false,
    this.price = '80 000 – 100 000 ₽',
  });

  final String orderId;
  final bool multipleEquipment;
  final String price;

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

  bool get _verified => VerificationStatus.current.isVerified;
  bool get _hasSubscription => VerificationStatus.hasSubscription;

  // Моковый список техники из заказа.
  List<String> get _orderEquipment => widget.multipleEquipment
      ? _multiEquipment
      : const <String>['Экскаватор', 'Автокран', 'Манипулятор', 'Погрузчик', 'Автовышка'];

  Future<void> _onRespondTap() async {
    // 1. Проверка верификации — в процессе.
    if (VerificationStatus.current == VerificationStatus.inProgress) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) => _InProgressDialog(),
      );
      return;
    }

    // 2. Верификация не пройдена — предлагаем отправить документы.
    if (!_verified) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) => RespondModalDialog(verified: false),
      );
      if (mounted) setState(() {});
      return;
    }

    // 3. Проверка подписки.
    if (!_hasSubscription) {
      final bool? subscribed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) => const SubscriptionPaywall(),
        ),
      );
      if (subscribed != true || !mounted) return;
      VerificationStatus.hasSubscription = true;
    }

    // 4. Выбор техники (если несколько).
    final List<String> eq = _orderEquipment;
    if (eq.length > 1) {
      final List<String>? picked = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PickEquipmentSheet(options: eq),
      );
      if (picked == null || !mounted) {
        return;
      }
    }

    // 5. Отклик отправлен.
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => RespondModalDialog(verified: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> equipment = _orderEquipment;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 48.h,
        leading: Padding(
          padding: EdgeInsets.only(top: 2.h),
          child: IconButton(
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
            icon: Padding(
              padding: EdgeInsets.only(left: 8.w),
              child: Image.asset(
                'assets/icons/ui/back_arrow.webp',
                width: 24.r,
                height: 24.r,
                fit: BoxFit.contain,
              ),
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Padding(
          padding: EdgeInsets.only(top: 2.h),
          child: Text(
            'Нужен экскаватор для копки тран...',
            style: AppTextStyles.titleS.copyWith(color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: const <Widget>[],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 88.h),
        child: AiAssistantFab(
          onTap: () => context.push('/assistant/chat'),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
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
                      SizedBox(height: 10.h),
                      Text('№123456',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textTertiary)),
                      SizedBox(height: 4.h),
                      Text('Разработка котлована под фундамент',
                          style: AppTextStyles.titleL.copyWith(height: 1.2)),
                      SizedBox(height: 7.h),
                      Text('Вчера в 14:30',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textTertiary)),
                      SizedBox(height: 11.h),
                      _Section(
                        title: 'Дата и время аренды',
                        child: Text('15 июня · 09:00–18:00',
                            style: AppTextStyles.subBody.copyWith(fontWeight: FontWeight.w400)),
                      ),
                      _Section(
                        title: 'Адрес',
                        child: Text(
                            'Московская область, Москва, Улица1, д 144',
                            style: AppTextStyles.subBody.copyWith(
                              fontWeight: FontWeight.w400,
                              decoration: TextDecoration.underline,
                            )),
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
                                style: AppTextStyles.subBody.copyWith(fontWeight: FontWeight.w400)),
                            Text('Планировка участка — 2 × 12 × 15 м',
                                style: AppTextStyles.subBody.copyWith(fontWeight: FontWeight.w400)),
                          ],
                        ),
                      ),
                      _Section(
                        title: 'Стоимость',
                        child: Text(widget.price,
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            )),
                      ),
                    ],
                  ),
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
              label: 'Откликнуться',
              onPressed: _onRespondTap,
            ),
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
            radius: 28.r,
            backgroundColor: AppColors.primaryTint,
            backgroundImage:
                const AssetImage('assets/images/catalog/avatar_placeholder.webp'),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Александр Иванов',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    )),
                SizedBox(height: 2.h),
                Row(
                  children: <Widget>[
                    Image.asset('assets/images/catalog/star.webp',
                        width: 20.r, height: 20.r),
                    SizedBox(width: 4.w),
                    Text('4,5',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                          color: AppColors.textPrimary,
                        )),
                    SizedBox(width: 16.w),
                    Text('15 отзывов',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                          color: AppColors.textPrimary,
                        )),
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
      padding: EdgeInsets.only(bottom: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                height: 1.3,
              )),
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
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.primary, width: 1),
        borderRadius: BorderRadius.circular(100.r),
      ),
      child: Text(label,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 13.sp,
            fontWeight: FontWeight.w400,
            height: 1.3,
            color: AppColors.textPrimary,
          )),
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
          SizedBox(height: 16.h),
          Text(
            'Выберите технику, на которой\nвы готовы выполнить работу',
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
            Text(label, style: AppTextStyles.body),
          ],
        ),
      ),
    );
  }
}

class _InProgressDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 16.w),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.r, 14.r, 16.r, 22.r),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Icon(Icons.close_rounded,
                    size: 22.r, color: AppColors.textTertiary),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Ваши документы ещё\nна проверке',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8.h),
            Text(
              'Вы получите уведомление, когда проверка завершится',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMRegular
                  .copyWith(color: AppColors.textSecondary),
            ),
            SizedBox(height: 18.h),
            PrimaryButton(
              label: 'Ок',
              onPressed: () => Navigator.of(context).pop(),
            ),
            SizedBox(height: 12.h),
          ],
        ),
      ),
    );
  }
}

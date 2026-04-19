import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/orders/review_screen.dart';
import 'package:dispatcher_1/features/orders/widgets/order_alerts.dart';
import 'package:dispatcher_1/features/orders/widgets/order_status_pill.dart';

/// Состояние экрана деталей «моего» заказа.
enum MyOrderDetailState {
  /// Заказ только пришёл — нужно «Подтвердить / Отклонить».
  /// Без секции «Номер телефона».
  waitingConfirm,

  /// Исполнитель уже подтвердил — показываем телефон заказчика
  /// и единственную кнопку «Отказаться от заказа».
  confirmed,

  /// Заказ выполнен. Виден телефон, кнопка «Оставить отзыв».
  completed,

  /// Заказ не принят (выбран другой / отклонён / снят). Без телефона и кнопок.
  rejected,
}

/// Детали моего заказа (НЕ путать с публичной карточкой из features/catalog).
class MyOrderDetailScreen extends StatefulWidget {
  const MyOrderDetailScreen({
    super.key,
    required this.state,
    this.title = 'Нужен экскаватор для копки траншеи',
    this.equipment = const <String>[
      'Экскаватор',
      'Автокран',
      'Манипулятор',
      'Погрузчик',
      'Автовышка',
    ],
    this.workCategories = const <String>[
      'Земляные работы',
      'Погрузочно-разгрузочные работы',
    ],
    this.rentDate = '15 июня · 09:00–18:00',
    this.address = 'Московская область, Москва, Улица1, д 144',
    this.customerName = 'Александр Иванов',
    this.customerPhone = '+7 999 123-45-67',
    this.customerEmail,
    this.publishedAgo = 'Вчера в 14:30',
    this.orderNumber = '№123456',
    this.workDescription = const <String>[
      'Разработка грунта — 40 м³',
      'Планировка участка — 2 × 12 × 15 м',
    ],
    this.rejectedStatus = MyOrderStatus.rejectedOther,
    this.onDecline,
    this.onRefuse,
    this.onConfirm,
    this.isBlocked = false,
    this.price = '80 000 – 100 000 ₽',
  });

  final MyOrderDetailState state;
  final String title;
  final List<String> equipment;
  final List<String> workCategories;
  final String rentDate;
  final String address;
  final String customerName;
  final String customerPhone;
  final String? customerEmail;
  final String publishedAgo;
  final String orderNumber;
  final List<String> workDescription;

  /// Какой именно красный статус показывать в state == rejected.
  final MyOrderStatus rejectedStatus;

  /// Колбэк «Отклонить заказ» (исполнитель не подтвердил) — обычно
  /// здесь parent перемещает заказ из «Новые» в «Не принятые» со
  /// статусом `rejectedDeclined` и закрывает экран.
  final VoidCallback? onDecline;

  /// Колбэк «Отказаться от заказа» (исполнитель уже подтвердил).
  final VoidCallback? onRefuse;

  /// Колбэк «Подтвердить» (исполнитель принимает заказ) — обычно
  /// parent переносит заказ из «Новые» в «Принятые» со статусом
  /// `accepted` и закрывает экран.
  final VoidCallback? onConfirm;

  final bool isBlocked;
  final String price;

  @override
  State<MyOrderDetailScreen> createState() => _MyOrderDetailScreenState();
}

class _MyOrderDetailScreenState extends State<MyOrderDetailScreen> {
  static final Set<String> _reviewedOrders = {};

  late MyOrderDetailState _state;
  late MyOrderStatus _rejectedStatus;
  bool _reviewLeft = false;

  @override
  void initState() {
    super.initState();
    _state = widget.state;
    _rejectedStatus = widget.rejectedStatus;
    _reviewLeft = _reviewedOrders.contains(widget.orderNumber);
  }

  MyOrderStatus get _pillStatus {
    switch (_state) {
      case MyOrderDetailState.waitingConfirm:
        // «Новые»: зелёная пилюля «Ждёт подтверждения».
        return MyOrderStatus.waiting;
      case MyOrderDetailState.confirmed:
        // «Принятые»: бирюзовая пилюля «Свяжитесь с заказчиком».
        return MyOrderStatus.accepted;
      case MyOrderDetailState.completed:
        return MyOrderStatus.completed;
      case MyOrderDetailState.rejected:
        return _rejectedStatus;
    }
  }

  bool get _showPhone =>
      _state == MyOrderDetailState.confirmed ||
      _state == MyOrderDetailState.completed;

  @override
  Widget build(BuildContext context) {
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
            widget.title,
            style: AppTextStyles.titleS.copyWith(color: Colors.white),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: _state == MyOrderDetailState.waitingConfirm ? 148.h : _hasBottomBar ? 88.h : 24.h),
        child: AiAssistantFab(onTap: () => context.push('/assistant/chat')),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w,
                  _hasBottomBar ? 24.h : 24.h + MediaQuery.of(context).padding.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  OrderStatusPill(status: _pillStatus),
                  SizedBox(height: 12.h),
                  _CustomerHeader(
                    name: widget.customerName,
                    onTap: () {},
                  ),
                  if (_showPhone) ...<Widget>[
                    SizedBox(height: 12.h),
                    Text(
                      'Номер телефона',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      widget.customerPhone,
                      style: AppTextStyles.subBody
                          .copyWith(fontWeight: FontWeight.w400),
                    ),
                    if (widget.customerEmail != null &&
                        widget.customerEmail!.trim().isNotEmpty) ...<Widget>[
                      SizedBox(height: 12.h),
                      Text(
                        'Электронная почта',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        widget.customerEmail!,
                        style: AppTextStyles.subBody
                            .copyWith(fontWeight: FontWeight.w400),
                      ),
                    ],
                  ],
                  SizedBox(height: 11.h),
                  Text(
                    widget.orderNumber,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textTertiary),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    widget.title,
                    style: AppTextStyles.titleL.copyWith(height: 1.2),
                  ),
                  SizedBox(height: 7.h),
                  Text(
                    widget.publishedAgo,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textTertiary),
                  ),
                  SizedBox(height: 11.h),
                  _Section(
                    title: 'Дата и время аренды',
                    child: Text(
                      widget.rentDate,
                      style: AppTextStyles.subBody
                          .copyWith(fontWeight: FontWeight.w400),
                    ),
                  ),
                  _Section(
                    title: 'Адрес',
                    child: Text(
                      widget.address,
                      style: AppTextStyles.subBody.copyWith(
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  _Section(
                    title: 'Требуемая спецтехника',
                    child: Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: widget.equipment
                          .map((String e) => _OutlinedChip(label: e))
                          .toList(),
                    ),
                  ),
                  _Section(
                    title: 'Категория работ',
                    child: Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: widget.workCategories
                          .map((String e) => _OutlinedChip(label: e))
                          .toList(),
                    ),
                  ),
                  _Section(
                    title: 'Характер работ',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final String line in widget.workDescription)
                          Text(
                            line,
                            style: AppTextStyles.subBody
                                .copyWith(fontWeight: FontWeight.w400),
                          ),
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
          if (_hasBottomBar) _buildBottomBar(),
        ],
      ),
    );
  }

  bool get _hasBottomBar =>
      _state != MyOrderDetailState.rejected &&
      !(_state == MyOrderDetailState.completed && _reviewLeft);

  Widget _buildBottomBar() {
    return Container(
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
        16.h + MediaQuery.of(context).padding.bottom,
      ),
      child: _buildAction(),
    );
  }

  Widget _buildAction() {
    switch (_state) {
      case MyOrderDetailState.waitingConfirm:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PrimaryButton(
              label: 'Подтвердить',
              enabled: !widget.isBlocked,
              onPressed: () => showConfirmAcceptDialog(
                context,
                onConfirm: () {
                  widget.onConfirm?.call();
                  setState(() => _state = MyOrderDetailState.confirmed);
                },
              ),
            ),
            SizedBox(height: 8.h),
            SecondaryButton(
              label: 'Отклонить',
              onPressed: () => showConfirmDeclineDialog(
                context,
                onDecline: () {
                  widget.onDecline?.call();
                  if (mounted) Navigator.of(context).maybePop();
                },
              ),
            ),
          ],
        );
      case MyOrderDetailState.confirmed:
        return PrimaryButton(
          label: 'Отказаться от заказа',
          onPressed: () => showConfirmRefuseDialog(
            context,
            onRefuse: () {
              widget.onRefuse?.call();
              if (mounted) Navigator.of(context).maybePop();
            },
          ),
        );
      case MyOrderDetailState.completed:
        if (_reviewLeft) return const SizedBox.shrink();
        return PrimaryButton(
          label: 'Оставить отзыв',
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ReviewScreen(),
              ),
            );
            if (mounted) {
              _reviewedOrders.add(widget.orderNumber);
              setState(() => _reviewLeft = true);
            }
          },
        );
      case MyOrderDetailState.rejected:
        return const SizedBox.shrink();
    }
  }
}

class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader({required this.name, required this.onTap});

  final String name;
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
            backgroundImage: const AssetImage(
              'assets/images/catalog/avatar_placeholder.webp',
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name.trim().isEmpty ? CropResult.namePlaceholder : name,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 2.h),
                Row(
                  children: <Widget>[
                    Image.asset(
                      'assets/images/catalog/star.webp',
                      width: 20.r,
                      height: 20.r,
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      '4,5',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(width: 16.w),
                    Text(
                      '15 отзывов',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                        color: AppColors.textPrimary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
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
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
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
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 13.sp,
          fontWeight: FontWeight.w400,
          height: 1.3,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

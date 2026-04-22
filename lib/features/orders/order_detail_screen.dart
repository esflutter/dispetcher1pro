import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/phone_dial.dart';
import 'package:dispatcher_1/core/utils/photo_source.dart';
import 'package:dispatcher_1/core/widgets/customer_header.dart';
import 'package:dispatcher_1/core/widgets/labeled_section.dart';
import 'package:dispatcher_1/core/widgets/photo_gallery_screen.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/customer_card_screen.dart';
import 'package:dispatcher_1/features/catalog/order_detail_screen.dart'
    show PickEquipmentSheet;
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/orders/review_screen.dart';
import 'package:dispatcher_1/features/orders/widgets/order_alerts.dart';
import 'package:dispatcher_1/features/orders/widgets/order_status_pill.dart';
import 'package:dispatcher_1/features/profile/reviews_screen.dart';
import 'package:dispatcher_1/features/services/my_services_screen.dart';

/// Состояние экрана деталей «моего» заказа.
enum MyOrderDetailState {
  /// Исполнитель отправил отклик, но заказчик ещё не ответил.
  /// Одна кнопка «Отозвать отклик». Телефон скрыт.
  offerSent,

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
    this.customerId,
    this.customerName = 'Александр Иванов',
    this.customerPhone = '+7 999 123-45-67',
    this.customerEmail,
    this.customerRating = 4.6,
    this.customerReviews = 10,
    this.publishedAgo = 'Вчера в 14:30',
    this.orderNumber = '№123456',
    this.workDescription = const <String>[
      'Разработка грунта — 40 м³',
      'Планировка участка — 2 × 12 × 15 м',
    ],
    this.description = '',
    this.photos = const <String>[],
    this.rejectedStatus = MyOrderStatus.rejectedOther,
    this.onDecline,
    this.onRefuse,
    this.onConfirm,
    this.onWithdraw,
    this.isBlocked = false,
  });

  final MyOrderDetailState state;
  final String title;
  final List<String> equipment;
  final List<String> workCategories;
  final String rentDate;
  final String address;
  final String? customerId;
  final String customerName;
  final String customerPhone;
  final String? customerEmail;
  final double customerRating;
  final int customerReviews;
  final String publishedAgo;
  final String orderNumber;
  final List<String> workDescription;

  /// Общее описание заказа — текстовый блок, который заказчик ввёл
  /// при создании. Пустая строка → блок не показывается.
  final String description;

  /// Прикреплённые фото — пути ассетов или файлов на устройстве.
  /// Если список пуст, блок «Фото» целиком скрыт (даже заголовок).
  final List<String> photos;

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

  /// Колбэк «Отозвать отклик» (заказчик ещё не ответил) — обычно
  /// parent переносит заказ из «Новые» в «Не принятые» со статусом
  /// `rejectedDeclined` и закрывает экран.
  final VoidCallback? onWithdraw;

  final bool isBlocked;

  @override
  State<MyOrderDetailScreen> createState() => _MyOrderDetailScreenState();
}

class _MyOrderDetailScreenState extends State<MyOrderDetailScreen> {
  static final Set<String> _reviewedOrders = {};

  late MyOrderDetailState _state;
  late MyOrderStatus _rejectedStatus;
  bool _reviewLeft = false;

  /// Контроллер прокрутки тела экрана — нужен, чтобы после подтверждения
  /// заказа и закрытия попапа автоматически вернуть пользователя к
  /// шапке заказчика, где появились телефон и иконка вызова.
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _state = widget.state;
    _rejectedStatus = widget.rejectedStatus;
    _reviewLeft = _reviewedOrders.contains(widget.orderNumber);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  MyOrderStatus get _pillStatus {
    switch (_state) {
      case MyOrderDetailState.offerSent:
        // «Новые»: оранжевая пилюля «Ожидает ответа заказчика».
        return MyOrderStatus.offerSent;
      case MyOrderDetailState.waitingConfirm:
        // «Новые»: зелёная пилюля «Ждёт подтверждения».
        return MyOrderStatus.pendingConfirmation;
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
              controller: _scrollCtrl,
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w,
                  _hasBottomBar ? 16.h : 16.h + MediaQuery.of(context).padding.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  OrderStatusPill(status: _pillStatus),
                  SizedBox(height: 12.h),
                  CustomerHeader(
                    name: widget.customerName,
                    rating: widget.customerRating,
                    reviews: widget.customerReviews,
                    onTap: widget.customerId == null
                        ? () {}
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CustomerCardScreen(
                                  customerId: widget.customerId!,
                                  customerName: widget.customerName,
                                  customerRating: widget.customerRating,
                                  customerReviews: widget.customerReviews,
                                  customerPhone: widget.customerPhone,
                                  customerEmail: widget.customerEmail,
                                  // Контакты раскрываем, когда у исполнителя
                                  // уже подтверждена сделка с этим заказчиком
                                  // (тот же критерий, что и у номера телефона
                                  // на экране деталей заказа).
                                  hasMatch: _showPhone,
                                ),
                              ),
                            ),
                    onReviewsTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ReviewsScreen(
                          subject: ReviewSubject.customer,
                        ),
                      ),
                    ),
                    // Кнопка вызова справа — только в статусе «Свяжитесь
                    // с заказчиком» (accepted). В остальных статусах
                    // у исполнителя нет прав связываться напрямую.
                    onCall: _pillStatus == MyOrderStatus.accepted
                        ? () => dialPhone(context, widget.customerPhone)
                        : null,
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
                  LabeledSection(
                    title: 'Дата и время аренды',
                    child: Text(
                      widget.rentDate,
                      style: AppTextStyles.subBody
                          .copyWith(fontWeight: FontWeight.w400),
                    ),
                  ),
                  LabeledSection(
                    title: 'Адрес',
                    child: Text(
                      widget.address,
                      style: AppTextStyles.subBody.copyWith(
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  if (widget.description.trim().isNotEmpty)
                    LabeledSection(
                      title: 'Описание заказа',
                      child: Text(
                        widget.description,
                        style: AppTextStyles.subBody
                            .copyWith(fontWeight: FontWeight.w400),
                      ),
                    ),
                  LabeledSection(
                    title: 'Требуемая спецтехника',
                    child: Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: widget.equipment
                          .map((String e) => _OutlinedChip(label: e))
                          .toList(),
                    ),
                  ),
                  LabeledSection(
                    title: 'Категория работ',
                    child: Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: widget.workCategories
                          .map((String e) => _OutlinedChip(label: e))
                          .toList(),
                    ),
                  ),
                  LabeledSection(
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
                  // Блок «Стоимость услуг» — показывается всегда, когда
                  // среди моих услуг есть релевантные по требуемой в
                  // заказе технике. Если релевантных нет — блок
                  // скрывается автоматически (SizedBox.shrink).
                  Builder(
                    builder: (BuildContext _) {
                      final Set<String> neededEq = widget.equipment.toSet();
                      final List<ServiceMock> matched = <ServiceMock>[];
                      for (final ServiceMock s in ServiceData.services) {
                        if (s.machinery.isEmpty) continue;
                        if (neededEq.contains(s.machinery.first)) {
                          matched.add(s);
                        }
                      }
                      if (matched.isEmpty) return const SizedBox.shrink();
                      return LabeledSection(
                        title: 'Цена',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            for (int i = 0; i < matched.length; i++) ...<Widget>[
                              if (i > 0) SizedBox(height: 2.h),
                              _PriceLine(service: matched[i]),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  if (widget.photos.isNotEmpty)
                    LabeledSection(
                      title: 'Фото',
                      child: _PhotosGrid(photos: widget.photos),
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
      case MyOrderDetailState.offerSent:
        return PrimaryButton(
          label: 'Отозвать отклик',
          onPressed: () => showConfirmWithdrawDialog(
            context,
            onWithdraw: () {
              widget.onWithdraw?.call();
              if (mounted) Navigator.of(context).maybePop();
            },
          ),
        );
      case MyOrderDetailState.waitingConfirm:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PrimaryButton(
              label: 'Подтвердить',
              enabled: !widget.isBlocked,
              onPressed: () async {
                // Шторка выбора техники — исполнитель отмечает, на
                // какой из требуемой в заказе техники он выходит.
                // Возвращает List<String> по «Подтвердить», либо null
                // при закрытии шторки (отмена).
                final List<String>? picked =
                    await showModalBottomSheet<List<String>>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => PickEquipmentSheet(
                    options: widget.equipment,
                    ctaLabel: 'Подтвердить',
                  ),
                );
                if (picked == null || picked.isEmpty || !mounted) return;
                widget.onConfirm?.call();
                setState(() => _state = MyOrderDetailState.confirmed);
                // Мэтч: заказ подтверждён — показываем попап с подсказкой
                // связаться с заказчиком. Контакты уже открылись на
                // текущей странице (accepted), куда попадает пользователь
                // после `setState` выше.
                if (mounted) await showOrderAcceptedDialog(context);
                // После закрытия попапа автоскроллим наверх — там шапка
                // заказчика с номером телефона и иконкой вызова, которые
                // только что появились.
                if (mounted && _scrollCtrl.hasClients) {
                  _scrollCtrl.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              },
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
            // Отзыв фиксируем только если пользователь реально отправил
            // его (`true` из ReviewScreen), а не просто вернулся назад —
            // иначе кнопка сразу пропадала, даже без оценки.
            final bool? submitted =
                await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) => ReviewScreen(
                  orderId: widget.orderNumber,
                  customerId: widget.customerId,
                ),
              ),
            );
            if (submitted == true && mounted) {
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


class _PhotosGrid extends StatelessWidget {
  const _PhotosGrid({required this.photos});
  final List<String> photos;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: <Widget>[
        for (int i = 0; i < photos.length; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => PhotoGalleryScreen(
                  photos: photos,
                  initialIndex: i,
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10.r),
              child: isAssetPath(photos[i])
                  ? Image.asset(
                      photos[i],
                      width: 72.r,
                      height: 72.r,
                      fit: BoxFit.cover,
                    )
                  : Image.file(
                      File(photos[i]),
                      width: 72.r,
                      height: 72.r,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
      ],
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

/// Строка блока «Стоимость услуг»: «Экскаватор — 3 500 ₽/час, 17 000 ₽/день».
/// Цены (primary-цветом) — из `ServiceMock`. Если цена пустая или «0» —
/// соответствующий кусок строки просто не выводится.
class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.service});
  final ServiceMock service;

  bool _hasPrice(String v) => v.isNotEmpty && v != '0';

  @override
  Widget build(BuildContext context) {
    final String eq =
        service.machinery.isEmpty ? service.title : service.machinery.first;
    final TextStyle base = TextStyle(
      fontFamily: 'Roboto',
      fontSize: 14.sp,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: AppColors.textPrimary,
    );
    final TextStyle priceDigits = base.copyWith(
      fontSize: 16.sp,
      fontWeight: FontWeight.w600,
      color: AppColors.primary,
    );
    final TextStyle priceUnit = base.copyWith(
      fontSize: 16.sp,
      fontWeight: FontWeight.w600,
      color: AppColors.primary,
    );
    final List<TextSpan> spans = <TextSpan>[TextSpan(text: '$eq — ')];
    final bool hasHour = _hasPrice(service.pricePerHour);
    final bool hasDay = _hasPrice(service.pricePerDay);
    if (hasHour) {
      spans.add(
          TextSpan(text: service.pricePerHour, style: priceDigits));
      spans.add(TextSpan(text: ' ₽/час', style: priceUnit));
    }
    if (hasHour && hasDay) spans.add(const TextSpan(text: '   '));
    if (hasDay) {
      spans.add(
          TextSpan(text: service.pricePerDay, style: priceDigits));
      spans.add(TextSpan(text: ' ₽/день', style: priceUnit));
    }
    return Text.rich(TextSpan(children: spans), style: base);
  }
}

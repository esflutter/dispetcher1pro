import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/my_orders/my_orders_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/clickable_address.dart';
import 'package:dispatcher_1/core/utils/phone_dial.dart';
import 'package:dispatcher_1/core/utils/photo_source.dart';
import 'package:dispatcher_1/core/widgets/customer_header.dart';
import 'package:dispatcher_1/core/widgets/labeled_section.dart';
import 'package:dispatcher_1/core/widgets/photo_gallery_screen.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/customer_card_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/orders/review_screen.dart';
import 'package:dispatcher_1/features/orders/widgets/order_alerts.dart';
import 'package:dispatcher_1/features/orders/widgets/order_status_pill.dart';
import 'package:dispatcher_1/features/orders/widgets/pick_equipment_sheet.dart';
import 'package:dispatcher_1/features/profile/reviews_screen.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';

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
    this.title = '',
    this.equipment = const <String>[],
    this.workCategories = const <String>[],
    this.rentDate = '',
    this.address = '',
    this.customerId,
    this.customerName = '',
    this.customerPhone = '',
    this.customerEmail,
    this.customerRating = 0,
    this.customerReviews = 0,
    this.publishedAgo = '',
    this.orderNumber = '',
    this.workDescription = const <String>[],
    this.description = '',
    this.photos = const <String>[],
    this.rejectedStatus = MyOrderStatus.rejectedOther,
    this.onDecline,
    this.onRefuse,
    this.onConfirm,
    this.onWithdraw,
    this.isBlocked = false,
    this.matchId,
    this.agreedPricePerHour,
    this.agreedPricePerDay,
    this.serviceMachineryTitle,
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

  /// id соответствующего `order_matches` — нужен экранам, которые пишут
  /// результат обратно в БД (review_screen → INSERT reviews с match_id).
  final String? matchId;

  /// Снапшот цены, зафиксированный триггером `snapshot_match_price` в
  /// момент создания мэтча. Это та цена, которая отображалась у
  /// заказчика, когда он отправил отклик/принял предложение —
  /// последующие правки услуги её не меняют.
  final double? agreedPricePerHour;
  final double? agreedPricePerDay;

  /// Техника услуги, по которой шёл отклик. Подпись к строке «Цена».
  final String? serviceMachineryTitle;

  @override
  State<MyOrderDetailScreen> createState() => _MyOrderDetailScreenState();
}

class _MyOrderDetailScreenState extends State<MyOrderDetailScreen> {
  static final Set<String> _reviewedOrders = {};

  late MyOrderDetailState _state;
  late MyOrderStatus _rejectedStatus;
  bool _reviewLeft = false;

  /// Подгружаемые из БД контакты заказчика — доступны RLS-политикой
  /// `profiles_private` только участнику accepted-мэтча. До загрузки
  /// показываем то, что пришло в _effectivePhone (обычно пустая
  /// строка, т.к. заказчик ещё не открыл свой номер).
  String? _dbCustomerPhone;
  String? _dbCustomerEmail;

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
    if (_state == MyOrderDetailState.confirmed ||
        _state == MyOrderDetailState.completed) {
      _loadContacts();
    }
  }

  Future<void> _loadContacts() async {
    final String? customerId = widget.customerId;
    if (customerId == null || customerId.isEmpty) return;
    try {
      final ({String? phone, String? email})? c =
          await MyOrdersService.instance.getCustomerContacts(customerId);
      if (c == null || !mounted) return;
      setState(() {
        _dbCustomerPhone = c.phone;
        _dbCustomerEmail = c.email;
      });
    } catch (_) {/* RLS не пропустил — оставим то что есть */}
  }

  bool get _hasAgreedPrice =>
      (widget.agreedPricePerHour != null &&
              widget.agreedPricePerHour! > 0) ||
      (widget.agreedPricePerDay != null && widget.agreedPricePerDay! > 0);

  /// «1000» → «1 000». Пустая строка для null/<=0 — _PriceLine сам
  /// скрывает соответствующую часть.
  String _fmtAgreedPrice(double? v) {
    if (v == null || v <= 0) return '';
    final int i = v.round();
    final String s = i.toString();
    final StringBuffer b = StringBuffer();
    final int n = s.length;
    for (int k = 0; k < n; k++) {
      if (k > 0 && (n - k) % 3 == 0) b.write(' ');
      b.write(s[k]);
    }
    return b.toString();
  }

  String get _effectivePhone =>
      (_dbCustomerPhone != null && _dbCustomerPhone!.isNotEmpty)
          ? _dbCustomerPhone!
          : widget.customerPhone;

  String? get _effectiveEmail =>
      (_dbCustomerEmail != null && _dbCustomerEmail!.isNotEmpty)
          ? _dbCustomerEmail
          : widget.customerEmail;

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
                                  customerPhone: _effectivePhone,
                                  customerEmail: _effectiveEmail,
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
                        builder: (_) => ReviewsScreen(
                          subject: ReviewSubject.customer,
                          targetUserId: widget.customerId,
                          initialRating: widget.customerRating,
                          initialCount: widget.customerReviews,
                        ),
                      ),
                    ),
                    // Кнопка вызова справа — только в статусе «Свяжитесь
                    // с заказчиком» (accepted). В остальных статусах
                    // у исполнителя нет прав связываться напрямую.
                    onCall: _pillStatus == MyOrderStatus.accepted
                        ? () => dialPhone(context, _effectivePhone)
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
                      _effectivePhone,
                      style: AppTextStyles.subBody
                          .copyWith(fontWeight: FontWeight.w400),
                    ),
                    if (_effectiveEmail != null &&
                        _effectiveEmail!.trim().isNotEmpty) ...<Widget>[
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
                        _effectiveEmail!,
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
                    child: ClickableAddress(
                      widget.address,
                      baseStyle: AppTextStyles.subBody
                          .copyWith(fontWeight: FontWeight.w400),
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
                  // Блок «Цена» — снапшот ставок из `order_matches`,
                  // зафиксированный триггером в момент создания мэтча.
                  // Показывается в статусах, когда мэтч уже состоялся
                  // («Ожидает ответа заказчика»/«Ждёт подтверждения»/
                  //  «Свяжитесь с заказчиком»/«Завершён»). Цена
                  // привязана к одной услуге, поэтому одна строка с
                  // подписью техники этой услуги.
                  if (_state != MyOrderDetailState.rejected &&
                      _hasAgreedPrice)
                    LabeledSection(
                      title: 'Цена',
                      child: _PriceLine(
                        equipment: widget.serviceMachineryTitle ?? '',
                        pricePerHour: _fmtAgreedPrice(widget.agreedPricePerHour),
                        pricePerDay: _fmtAgreedPrice(widget.agreedPricePerDay),
                      ),
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
                if (!VerificationStatus.hasSubscription) {
                  final bool? go = await showSubscriptionPausedDialog(context);
                  if (go == true && mounted) context.push('/subscription');
                  return;
                }
                // На `waiting_executor` → `accepted` уже зафиксирована
                // конкретная услуга (`order_matches.service_id`), её
                // менять нельзя. Шторка-чеклист «по каким техникам
                // готов выполнить» — это UX-подтверждение для
                // исполнителя, чтобы при заказе с 2+ техниками он
                // явно отметил, что согласен. Реальный service_id
                // в БД остаётся прежним.
                if (widget.equipment.length > 1) {
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
                }
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
                  matchId: widget.matchId,
                  targetId: widget.customerId,
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
              child: photoSmartImage(
                photos[i],
                bucket: 'order-photos',
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

/// Строка блока «Цена»: «Экскаватор — 1 500 ₽/час   12 000 ₽/день».
/// Цифры и единицы — оранжевые (primary). Если какая-то из цен пустая
/// или «0» — соответствующий кусок строки не выводится.
class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.equipment,
    required this.pricePerHour,
    required this.pricePerDay,
  });
  final String equipment;
  final String pricePerHour;
  final String pricePerDay;

  bool _hasPrice(String v) => v.isNotEmpty && v != '0';

  @override
  Widget build(BuildContext context) {
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
    final List<TextSpan> spans = <TextSpan>[TextSpan(text: '$equipment — ')];
    final bool hasHour = _hasPrice(pricePerHour);
    final bool hasDay = _hasPrice(pricePerDay);
    if (hasHour) {
      spans.add(TextSpan(text: pricePerHour, style: priceDigits));
      spans.add(TextSpan(text: ' ₽/час', style: priceUnit));
    }
    if (hasHour && hasDay) spans.add(const TextSpan(text: '   '));
    if (hasDay) {
      spans.add(TextSpan(text: pricePerDay, style: priceDigits));
      spans.add(TextSpan(text: ' ₽/день', style: priceUnit));
    }
    return Text.rich(TextSpan(children: spans), style: base);
  }
}

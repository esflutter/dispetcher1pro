import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/ai/ai_navigation.dart';
import 'package:dispatcher_1/core/my_orders/models.dart';
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
import 'package:dispatcher_1/features/catalog/widgets/subscription_paywall.dart';
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
  /// Локальная метка «уже оставил отзыв» по `orderNumber`. Сохраняется
  /// между переходами между экранами в одной сессии. Сбрасывается через
  /// [resetReviewedOrders] при logout/delete account.
  static final Set<String> _reviewedOrders = <String>{};

  /// Сбрасывает локальную метку «уже оставил отзыв». Вызывается из
  /// `auth_reset._clearAll()` при logout — иначе следующий пользователь
  /// на том же устройстве не увидит кнопку «Оставить отзыв» на заказах
  /// с совпадающим `display_number`.
  static void resetReviewedOrders() => MyOrderDetailScreen._reviewedOrders.clear();

  /// Проверка локальной метки «уже оставил отзыв» — нужна списку
  /// заказов, чтобы текст пилюли «Завершён. Оставьте отзыв» сменить на
  /// короткое «Завершён» сразу после возврата с экрана отзыва.
  static bool isOrderReviewed(String orderNumber) =>
      MyOrderDetailScreen._reviewedOrders.contains(orderNumber);

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
    this.customerAvatarUrl,
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
  final String? customerAvatarUrl;
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
  final Future<bool> Function()? onDecline;

  /// Колбэк «Отказаться от заказа» (исполнитель уже подтвердил).
  final Future<bool> Function()? onRefuse;

  /// Колбэк «Подтвердить» (исполнитель принимает заказ). Возвращает
  /// `true`, если БД успешно зафиксировала переход в `accepted`.
  /// `false` — если, например, заказчик одновременно выбрал другого
  /// (UNIQUE-индекс `order_matches_single_accepted`). UI не должен
  /// переходить в состояние confirmed раньше, чем БД ответила, иначе
  /// исполнитель видит «Подтверждено» и контакты заказчика, хотя
  /// в БД мэтч остался в `awaiting_executor` или ушёл в rejected.
  final Future<bool> Function()? onConfirm;

  /// Колбэк «Отозвать отклик» (заказчик ещё не ответил) — обычно
  /// parent переносит заказ из «Новые» в «Не принятые» со статусом
  /// `rejectedDeclined` и закрывает экран.
  final Future<bool> Function()? onWithdraw;

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

  late MyOrderDetailState _state;
  late MyOrderStatus _rejectedStatus;
  bool _reviewLeft = false;

  /// Идёт async-операция (подтвердить / отклонить / отозвать /
  /// отказаться). Пока true, кнопки в `_buildAction` дисабилятся и
  /// игнорируют повторные тапы. Без этого пользователь успевал
  /// нажать «Отклонить» и сразу «Подтвердить»; первый запрос летел
  /// в БД, второй уходил уже после изменения статуса и БД отдавала
  /// 23514 «Нельзя изменить финальный статус» (см. validate_match_transition).
  bool _busy = false;

  /// Подгружаемые из БД контакты заказчика — доступны RLS-политикой
  /// `profiles_private` только участнику accepted-мэтча. До загрузки
  /// показываем то, что пришло в _effectivePhone (обычно пустая
  /// строка, т.к. заказчик ещё не открыл свой номер).
  String? _dbCustomerPhone;
  String? _dbCustomerEmail;

  /// Даты работ заказа (`orders.date_from` / `date_to`) — подгружаются по
  /// matchId для правила видимости кнопки «Отметить выполненным»: она
  /// появляется, когда по локальному времени устройства наступил
  /// ПОСЛЕДНИЙ день заказа (date_to, а без него date_from). В сам экран
  /// даты не передаются — в `rentDate` уже готовая строка для показа.
  DateTime? _orderDateFrom;
  DateTime? _orderDateTo;

  /// Локальный снапшот рейтинга/количества отзывов заказчика. Изначально
  /// = widget.customerRating/customerReviews; после возврата с экрана
  /// отзыва обновляется через [getCustomerRatingSnapshot], чтобы шапка
  /// сразу показывала свежее значение (триггер `recalculate_profile_rating`
  /// уже пересчитал в БД).
  late double _customerRating;
  late int _customerReviews;

  /// Контроллер прокрутки тела экрана — нужен, чтобы после подтверждения
  /// заказа и закрытия попапа автоматически вернуть пользователя к
  /// шапке заказчика, где появились телефон и иконка вызова.
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _state = widget.state;
    _rejectedStatus = widget.rejectedStatus;
    _reviewLeft = MyOrderDetailScreen._reviewedOrders.contains(widget.orderNumber);
    _customerRating = widget.customerRating;
    _customerReviews = widget.customerReviews;
    if (_state == MyOrderDetailState.confirmed ||
        _state == MyOrderDetailState.completed) {
      _loadContacts();
    }
    if (_state == MyOrderDetailState.confirmed) {
      _loadOrderDates();
    }
    if (_state == MyOrderDetailState.completed) {
      _checkExistingReview();
    }
    // Live-обновление ОТКРЫТОГО экрана: realtime поднимает маяк при изменении
    // мэтча — сразу подтягиваем новый статус, не дожидаясь возврата в список.
    MyOrdersService.changeBeacon.addListener(_onRealtimeBeacon);
  }

  /// Маппинг статуса мэтча → состояние экрана (зеркало логики в списке).
  static MyOrderDetailState _detailStateForStatus(MyMatchStatus s) {
    switch (s) {
      case MyMatchStatus.awaitingCustomer: return MyOrderDetailState.offerSent;
      case MyMatchStatus.awaitingExecutor: return MyOrderDetailState.waitingConfirm;
      case MyMatchStatus.accepted:         return MyOrderDetailState.confirmed;
      case MyMatchStatus.completed:        return MyOrderDetailState.completed;
      case MyMatchStatus.rejectedByCustomer:
      case MyMatchStatus.rejectedByExecutor:
      case MyMatchStatus.expired:          return MyOrderDetailState.rejected;
    }
  }

  /// realtime изменил какой-то мэтч — перезапрашиваем СВОЙ и, если статус
  /// сменился (заказчик принял/отклонил, заказ завершился), обновляем экран
  /// на месте. _busy-гард: не вмешиваемся, пока идёт своё действие.
  Future<void> _onRealtimeBeacon() async {
    final String? matchId = widget.matchId;
    if (matchId == null || !mounted || _busy) return;
    try {
      final List<MyOrderMatch> matches = await MyOrdersService.instance.listMine();
      MyOrderMatch? found;
      for (final MyOrderMatch x in matches) {
        if (x.matchId == matchId) { found = x; break; }
      }
      if (found == null || !mounted) return;
      final MyOrderMatch m = found;
      final MyOrderDetailState next = _detailStateForStatus(m.status);
      if (next == _state) return;
      setState(() {
        _state = next;
        if (m.status == MyMatchStatus.rejectedByCustomer) {
          _rejectedStatus = MyOrderStatus.rejectedOther;
        } else if (m.status == MyMatchStatus.rejectedByExecutor) {
          _rejectedStatus = MyOrderStatus.rejectedDeclined;
        } else if (m.status == MyMatchStatus.expired) {
          _rejectedStatus = MyOrderStatus.rejectedRemoved;
        }
      });
      if (next == MyOrderDetailState.confirmed || next == MyOrderDetailState.completed) {
        _loadContacts();
      }
      if (next == MyOrderDetailState.confirmed) {
        _loadOrderDates();
      }
    } catch (_) {/* сеть/доступ — оставим текущее состояние */}
  }

  /// Тянем даты работ заказа для правила времени кнопки «Отметить
  /// выполненным». Ошибка сети — кнопка просто не появится до следующего
  /// захода на экран (правило «не показывать, пока не уверены»).
  Future<void> _loadOrderDates() async {
    final String? matchId = widget.matchId;
    if (matchId == null || _orderDateFrom != null) return;
    final ({DateTime dateFrom, DateTime? dateTo})? dates =
        await MyOrdersService.instance.getMatchOrderDates(matchId);
    if (dates == null || !mounted) return;
    setState(() {
      _orderDateFrom = dates.dateFrom;
      _orderDateTo = dates.dateTo;
    });
  }

  /// Правило видимости «Отметить выполненным»: мэтч принят (state ==
  /// confirmed гарантирует accepted) И по локальному времени устройства
  /// уже наступил последний день заказа (date_to, без него date_from).
  /// Сервер проверяет то же по московской дате (для Сибири мягче
  /// клиента), поэтому ложного too_early при видимой кнопке не будет.
  bool get _canCompleteNow {
    if (widget.matchId == null) return false;
    final DateTime? from = _orderDateFrom;
    if (from == null) return false;
    final DateTime finalDay = _orderDateTo ?? from;
    final DateTime finalDayStart =
        DateTime(finalDay.year, finalDay.month, finalDay.day);
    return !DateTime.now().isBefore(finalDayStart);
  }

  /// «Отметить выполненным»: подтверждение → RPC → перевод экрана в
  /// completed (появится существующая кнопка «Оставить отзыв»).
  /// `already_completed` — тоже успех (крон или заказчик успели раньше).
  Future<void> _completeManually() async {
    if (_busy) return;
    final bool? confirmed = await showConfirmCompleteDialog(context);
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await MyOrdersService.instance
          .completeMatchManually(widget.matchId!);
      if (!mounted) return;
      setState(() => _state = MyOrderDetailState.completed);
      // Список «Мои заказы» под этим экраном ещё держит старый статус —
      // будим его, чтобы при возврате заказ уже был в «Завершённых».
      MyOrdersService.bumpChangeBeacon();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заказ завершён')),
      );
    } on CompleteMatchException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось завершить заказ. Попробуйте ещё раз.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// При открытии завершённого мэтча проверяем в БД, оставил ли я уже
  /// отзыв заказчику. Локальный кэш `_reviewedOrders` сбрасывается при
  /// Hot Restart и при первом запуске на новом устройстве — без этой
  /// проверки кнопка «Оставить отзыв» снова показывается, и второй
  /// INSERT падает на UNIQUE-индексе.
  Future<void> _checkExistingReview() async {
    if (_reviewLeft) return;
    if (widget.matchId == null) return;
    final bool exists =
        await MyOrdersService.instance.hasMyReviewOnMatch(widget.matchId!);
    if (!mounted || !exists) return;
    MyOrderDetailScreen._reviewedOrders.add(widget.orderNumber);
    setState(() => _reviewLeft = true);
  }

  /// После того, как исполнитель оставил отзыв заказчику и вернулся
  /// на экран деталей, тянем свежий рейтинг/количество отзывов из БД
  /// и обновляем локальный state шапки. Без этого «0 отзывов» висел
  /// до полного refetch списка «Мои заказы».
  Future<void> _refreshCustomerStats() async {
    if (widget.customerId == null) return;
    final ({double rating, int reviewCount})? snap =
        await MyOrdersService.instance
            .getCustomerRatingSnapshot(widget.customerId!);
    if (!mounted || snap == null) return;
    setState(() {
      _customerRating = snap.rating;
      _customerReviews = snap.reviewCount;
    });
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
    MyOrdersService.changeBeacon.removeListener(_onRealtimeBeacon);
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
        // 148.h — когда в нижней панели ДВЕ кнопки (waitingConfirm, а также
        // confirmed с доступной «Отметить выполненным»), 88.h — одна.
        padding: EdgeInsets.only(
          bottom: _state == MyOrderDetailState.waitingConfirm ||
                  (_state == MyOrderDetailState.confirmed && _canCompleteNow)
              ? 148.h
              : _hasBottomBar
                  ? 88.h
                  : 24.h,
        ),
        child: AiAssistantFab(onTap: () => openAssistantChat(context)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              // Нижний отступ зависит от наличия панели кнопок: если
              // кнопки есть — отбиваемся от их верхнего края (16.h),
              // т.к. сама панель уже учитывает системный safe-area.
              // Если кнопок нет — добавляем safe-area сюда, иначе
              // последняя секция уезжает под жесты/навбар.
              padding: EdgeInsets.fromLTRB(
                16.w,
                16.h,
                16.w,
                _hasBottomBar
                    ? 16.h
                    : 16.h + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  OrderStatusPill(status: _pillStatus, reviewLeft: _reviewLeft),
                  SizedBox(height: 12.h),
                  CustomerHeader(
                    name: widget.customerName,
                    avatarUrl: widget.customerAvatarUrl,
                    rating: _customerRating,
                    reviews: _customerReviews,
                    onTap: widget.customerId == null
                        ? () {}
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CustomerCardScreen(
                                  customerId: widget.customerId!,
                                  customerName: widget.customerName,
                                  customerRating: _customerRating,
                                  customerReviews: _customerReviews,
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
                          initialRating: _customerRating,
                          initialCount: _customerReviews,
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

  /// Общая обёртка для деструктивных действий «Отозвать / Отклонить /
  /// Отказаться»: показать confirm-диалог, дождаться БД, при успехе
  /// закрыть экран; при ошибке — НЕ закрывать, чтобы юзер увидел
  /// сообщение из родительского `_doAction` и понял, что произошло.
  /// `_busy` блокирует повторные тапы, пока запрос летит.
  Future<void> _runRemove({
    required Future<bool?> Function() showDialog,
    required Future<bool> Function()? action,
  }) async {
    if (_busy) return;
    final bool? confirmed = await showDialog();
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final bool ok = await (action?.call() ?? Future<bool>.value(true));
      if (!ok || !mounted) return;
      Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildAction() {
    switch (_state) {
      case MyOrderDetailState.offerSent:
        return PrimaryButton(
          label: 'Отозвать отклик',
          enabled: !_busy,
          onPressed: () => _runRemove(
            showDialog: () => showConfirmWithdrawDialog(context),
            action: widget.onWithdraw,
          ),
        );
      case MyOrderDetailState.waitingConfirm:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PrimaryButton(
              label: 'Подтвердить',
              // Кнопка остаётся активной при блокировке — иначе тап молчал
              // и причина (низкий рейтинг) нигде не всплывала. Объяснение
              // показываем первым же шагом ниже.
              enabled: !_busy,
              onPressed: () async {
                if (_busy) return;
                if (widget.isBlocked) {
                  await showAccountBlockedDialog(context);
                  return;
                }
                if (!VerificationStatus.hasSubscription) {
                  // «Приостановлена» (возобновить) показываем ТОЛЬКО пока
                  // оплаченный период ещё не истёк — тогда выключено лишь
                  // автосписание. Если период закончился (paid_until в прошлом
                  // или его нет) — подписка реально закончилась, и предлагать
                  // «возобновить» нечего: ведём в маркетинговый paywall, как и
                  // в гейте отклика. На текст диалога ориентироваться нельзя —
                  // он остаётся заполненным и у полностью истёкшей подписки.
                  final DateTime? paidUntil =
                      VerificationStatus.subscriptionPaidUntil;
                  if (paidUntil != null && paidUntil.isAfter(DateTime.now())) {
                    final bool? go =
                        await showSubscriptionPausedDialog(context);
                    if (go == true && mounted) {
                      context.push('/subscription/manage');
                    }
                    return;
                  }
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => const SubscriptionPaywall(),
                    ),
                  );
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
                // Ждём результат БД-запроса до смены UI-state. Если
                // заказчик одновременно выбрал другого, БД отвергнет
                // переход — нельзя показывать «Подтверждено» и контакты.
                setState(() => _busy = true);
                bool ok = false;
                try {
                  ok = await (widget.onConfirm?.call() ??
                      Future<bool>.value(true));
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
                if (!ok || !mounted) return;
                setState(() => _state = MyOrderDetailState.confirmed);
                // Заказ принят прямо здесь — телефон заказчика только что стал
                // доступен по RLS, но в переданном объекте его не было.
                // Подгружаем контакты сразу, иначе номер появлялся только
                // после перезахода на экран.
                _loadContacts();
                // И даты работ — от них зависит появление кнопки
                // «Отметить выполненным» в только что открывшемся confirmed.
                _loadOrderDates();
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
              onPressed: _busy
                  ? null
                  : () => _runRemove(
                        showDialog: () => showConfirmDeclineDialog(context),
                        action: widget.onDecline,
                      ),
            ),
          ],
        );
      case MyOrderDetailState.confirmed:
        // Деструктивное действие на уже принятом заказе — выводим
        // outline-стилем (SecondaryButton), чтобы визуально отличить
        // от основных оранжевых CTA («Подтвердить», «Оставить отзыв»)
        // и снизить вероятность случайного тапа. Выше неё — «Отметить
        // выполненным», когда наступил последний день работ заказа.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_canCompleteNow) ...<Widget>[
              PrimaryButton(
                label: 'Отметить выполненным',
                enabled: !_busy,
                onPressed: _completeManually,
              ),
              SizedBox(height: 8.h),
            ],
            SecondaryButton(
              label: 'Отказаться от заказа',
              onPressed: _busy
                  ? null
                  : () => _runRemove(
                        showDialog: () => showConfirmRefuseDialog(context),
                        action: widget.onRefuse,
                      ),
            ),
          ],
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
              MyOrderDetailScreen._reviewedOrders.add(widget.orderNumber);
              setState(() => _reviewLeft = true);
              // Триггер `recalculate_profile_rating` в БД пересчитал
              // рейтинг/счётчик сразу после INSERT в reviews. Тянем
              // свежие значения, чтобы шапка показала «1 отзыв» вместо
              // устаревших «0 отзывов».
              _refreshCustomerStats();
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
                  bucket: 'order-photos',
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
                cacheWidth: 300,
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

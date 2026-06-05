import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/catalog/format.dart';
import 'package:dispatcher_1/core/catalog/models.dart';
import 'package:dispatcher_1/core/my_orders/models.dart';
import 'package:dispatcher_1/core/my_orders/my_orders_service.dart';
import 'package:dispatcher_1/core/push/pending_deep_link.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/utils/phone_dial.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/orders/order_detail_screen.dart';
import 'package:dispatcher_1/features/orders/widgets/my_order_card.dart';
import 'package:dispatcher_1/features/orders/widgets/order_status_pill.dart';
import 'package:dispatcher_1/features/profile/account_block.dart';

/// «Мои заказы» исполнителя. Источник — таблица `order_matches` JOIN
/// `orders` + `profiles` (заказчик). Три вкладки — Новые / Принятые /
/// Не принятые — делят список по [MyMatchStatus].
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen(
      {super.key, this.onGoToCatalog, this.isBlocked = false});

  final VoidCallback? onGoToCatalog;
  final bool isBlocked;

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersData {
  const _MyOrdersData({required this.matches, required this.phones});
  final List<MyOrderMatch> matches;

  /// Ключ — `customerId`. Значение — телефон из `profiles_private`,
  /// читаем только для accepted/completed мэтчей; для остальных — null.
  final Map<String, String?> phones;
}

class _MyOrdersScreenState extends State<MyOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late Future<_MyOrdersData> _future;

  bool get _blocked => AccountBlock.isBlocked || widget.isBlocked;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    AccountBlock.notifier.addListener(_refresh);
    // Глобальный маяк: меняется, когда другие экраны (например, график)
    // отменяют мэтчи. Без подписки список «Мои заказы» оставался
    // устаревшим до pull-to-refresh.
    MyOrdersService.changeBeacon.addListener(_refresh);
    pendingOrderDeepLink.addListener(_onPendingDeepLink);
    _future = _fetch();
    // Если пуш стрельнул раньше, чем экран успел подписаться — обработать
    // отложенный orderId после первого рендера, когда _future уже стартовал.
    if (pendingOrderDeepLink.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingDeepLink());
    }
  }

  @override
  void dispose() {
    AccountBlock.notifier.removeListener(_refresh);
    MyOrdersService.changeBeacon.removeListener(_refresh);
    pendingOrderDeepLink.removeListener(_onPendingDeepLink);
    _tab.dispose();
    super.dispose();
  }

  Future<void> _onPendingDeepLink() async {
    final String? orderId = pendingOrderDeepLink.value;
    if (orderId == null || !mounted) return;

    // Ждём текущую загрузку, потом ищем мэтч с этим order_id.
    _MyOrdersData data;
    try {
      data = await _future;
    } catch (_) {
      // Если первая загрузка упала — попробуем перезапросить.
      data = await _fetch();
    }
    if (!mounted) return;

    MyOrderMatch? match;
    for (final MyOrderMatch m in data.matches) {
      if (m.orderId == orderId) {
        match = m;
        break;
      }
    }

    pendingOrderDeepLink.value = null;
    if (match != null) {
      _openMatchDetail(context, match, data.phones[match.customerId]);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Отклик на этот заказ не найден'),
        ),
      );
    }
  }

  /// Открывает экран деталей конкретного мэтча. Вынесена отдельно
  /// (раньше была инлайн в onTap) — переиспользуется при тапе по
  /// карточке и при deep-link от пуша.
  Future<void> _openMatchDetail(
      BuildContext context, MyOrderMatch m, String? phone) async {
    final MyOrderStatus uiStatus = _uiStatus(m.status);
    final String rentDate = _rentDate(m);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyOrderDetailScreen(
          title: m.orderTitle,
          equipment: m.orderMachineryTitles,
          workCategories: m.orderCategoryTitles,
          workDescription: m.orderWorks,
          description: m.orderDescription,
          photos: m.orderPhotos,
          rentDate: rentDate,
          address: m.orderAddress,
          publishedAgo: formatPublishedAgo(m.orderPublishedAt),
          orderNumber:
              '№${m.orderDisplayNumber.toString().padLeft(8, '0')}',
          customerId: m.customerId,
          customerName: m.customerName,
          customerAvatarUrl: m.customerAvatarUrl,
          customerPhone: phone ?? '',
          customerEmail: null,
          customerRating: m.customerRating,
          customerReviews: m.customerReviewCount,
          state: _detailStateForStatus(m.status),
          rejectedStatus: uiStatus,
          matchId: m.matchId,
          agreedPricePerHour: m.agreedPricePerHour,
          agreedPricePerDay: m.agreedPricePerDay,
          serviceMachineryTitle: m.serviceMachineryTitle,
          onWithdraw: () =>
              _doAction(() => MyOrdersService.instance.withdraw(m.matchId)),
          onConfirm: () => _doAction(
            () => MyOrdersService.instance.acceptMatch(m.matchId),
          ),
          onDecline: () =>
              _doAction(() => MyOrdersService.instance.declineMatch(m.matchId)),
          onRefuse: () =>
              _doAction(() => MyOrdersService.instance.declineMatch(m.matchId)),
          isBlocked: _blocked,
        ),
      ),
    );
    _refresh();
  }

  /// Загружает мэтчи + телефоны заказчиков для accepted/completed
  /// (RLS пропускает только участникам соответствующих мэтчей).
  Future<_MyOrdersData> _fetch() async {
    final List<MyOrderMatch> matches =
        await MyOrdersService.instance.listMine();
    final Set<String> needContact = <String>{
      for (final MyOrderMatch m in matches)
        if (m.status == MyMatchStatus.accepted ||
            m.status == MyMatchStatus.completed)
          m.customerId,
    };
    // Bulk-запрос: один SELECT с inFilter вместо N отдельных
    // `eq().maybeSingle()`. Раньше 20 заказов = 20 параллельных
    // HTTP-запросов к profiles_private.
    final Map<String, ({String? phone, String? email})> bulk =
        await MyOrdersService.instance.getCustomerContactsBulk(needContact);
    final Map<String, String?> phones = <String, String?>{
      for (final String id in needContact) id: bulk[id]?.phone,
    };
    return _MyOrdersData(matches: matches, phones: phones);
  }

  void _refresh() {
    if (!mounted) return;
    // Блочный синтаксис обязателен: arrow-форма `() => _future = _fetch()`
    // возвращает Future, и Flutter ругается «setState callback returned a
    // Future» (см. RefreshIndicator unhandled exception в логах).
    setState(() {
      _future = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16.w,
        toolbarHeight: 64.h,
        title: Text(
          'Мои заказы',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 28.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.2,
          ),
        ),
      ),
      body: FutureBuilder<_MyOrdersData>(
        future: _future,
        builder: (BuildContext context,
            AsyncSnapshot<_MyOrdersData> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _RetryView(onRetry: _refresh);
          }
          final _MyOrdersData data =
              snap.data ?? const _MyOrdersData(matches: [], phones: {});
          final List<MyOrderMatch> all = data.matches;
          if (all.isEmpty) {
            return _EmptyOrders(onGoToCatalog: widget.onGoToCatalog);
          }
          final List<MyOrderMatch> active = all
              .where((MyOrderMatch m) =>
                  m.status == MyMatchStatus.awaitingCustomer ||
                  m.status == MyMatchStatus.awaitingExecutor)
              .toList();
          final List<MyOrderMatch> accepted = all
              .where((MyOrderMatch m) =>
                  m.status == MyMatchStatus.accepted ||
                  m.status == MyMatchStatus.completed)
              .toList();
          final List<MyOrderMatch> rejected = all
              .where((MyOrderMatch m) => m.status.isRejected)
              .toList();
          return _buildWithTabs(active, accepted, rejected, data.phones);
        },
      ),
    );
  }

  Widget _buildWithTabs(
    List<MyOrderMatch> active,
    List<MyOrderMatch> accepted,
    List<MyOrderMatch> rejected,
    Map<String, String?> phones,
  ) {
    return Column(
      children: <Widget>[
        Container(
          color: AppColors.background,
          padding: EdgeInsets.fromLTRB(16.w, 17.h, 16.w, 5.h),
          child: _OrdersSegmented(
            controller: _tab,
            items: const <String>['Новые', 'Принятые', 'Не принятые'],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: <Widget>[
              _buildList(active, phones),
              _buildList(accepted, phones),
              _buildList(rejected, phones),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onRefresh() async {
    final Future<_MyOrdersData> next = _fetch();
    setState(() {
      _future = next;
    });
    await next;
  }

  Widget _buildList(List<MyOrderMatch> items, Map<String, String?> phones) {
    if (items.isEmpty) {
      // LayoutBuilder + ConstrainedBox(minHeight) нужны, чтобы заглушка
      // получила полную высоту вьюпорта и сцентрировалась через
      // mainAxisAlignment.center. Без них ListView отдаёт child его
      // intrinsic-высоту, и заглушка прилипает к верху (визуально это
      // выглядело как «вертикальное выравнивание сломалось»).
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _onRefresh,
        child: LayoutBuilder(
          builder: (BuildContext _, BoxConstraints constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: _EmptyOrders(onGoToCatalog: widget.onGoToCatalog),
              ),
            );
          },
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _onRefresh,
      child: MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: items.length,
        itemBuilder: (BuildContext context, int i) {
          final MyOrderMatch m = items[i];
          final bool isLast = i == items.length - 1;
          final MyOrderStatus uiStatus = _uiStatus(m.status);
          final String rentDate = _rentDate(m);
          final String orderNumber =
              '№${m.orderDisplayNumber.toString().padLeft(8, '0')}';
          // Телефон тянется только для accepted/completed мэтчей. У
          // остальных карточек звонить ещё рано — кнопка должна быть
          // визуально, но не выполнять никакого действия.
          final String? phone = phones[m.customerId];
          final bool canCall = phone != null && phone.trim().isNotEmpty;
          // Таймер всегда от момента последнего изменения мэтча
          // (`updated_at`). На INSERT триггер `moddatetime` ставит
          // `updated_at = now()`, на каждый UPDATE статуса — снова
          // обновляет. Поэтому «только что откликнулся / приняли /
          // отозвал» — карточка показывает «Только что» и едет наверх.
          final DateTime timerSource = m.statusChangedAt;
          return Column(
            children: <Widget>[
              MyOrderCard(
                status: uiStatus,
                title: m.orderTitle,
                equipment: m.orderMachineryTitles,
                rentDate: rentDate,
                address: m.orderAddress,
                publishedAgo: formatPublishedAgo(timerSource),
                reviewLeft:
                    MyOrderDetailScreen.isOrderReviewed(orderNumber),
                customerName: m.customerName,
                customerPhone: phone,
                customerAvatar: m.customerAvatarUrl,
                onTap: () => _openMatchDetail(context, m, phone),
                onContact: canCall ? () => dialPhone(context, phone) : null,
              ),
              if (!isLast)
                const Divider(
                  height: 1,
                  thickness: 0.5,
                  color: AppColors.primary,
                ),
            ],
          );
        },
      ),
      ),
    );
  }

  /// Защищает от двойного клика на «Принять/Отказаться/Отозвать»: пока
  /// идёт первый запрос, повторные нажатия игнорируются. Без флага
  /// одновременно уходило два UPDATE — первый успешный, второй ловил
  /// 23505 и показывал «уже выбрали другого», хотя с точки зрения
  /// пользователя он ничего лишнего не делал.
  bool _busy = false;

  Future<bool> _doAction(Future<void> Function() op) async {
    if (_busy) return false;
    _busy = true;
    try {
      await op();
    } on MatchAlreadyTakenException {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Заказчик уже выбрал другого исполнителя.'),
        ),
      );
      _refresh();
      return false;
    } on MatchEngageBlockedException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить статус: $e')),
      );
      return false;
    } finally {
      _busy = false;
    }
    _refresh();
    return true;
  }

  MyOrderStatus _uiStatus(MyMatchStatus s) {
    switch (s) {
      case MyMatchStatus.awaitingCustomer:
        return MyOrderStatus.offerSent;
      case MyMatchStatus.awaitingExecutor:
        return MyOrderStatus.pendingConfirmation;
      case MyMatchStatus.accepted:
        return MyOrderStatus.accepted;
      case MyMatchStatus.completed:
        return MyOrderStatus.completed;
      case MyMatchStatus.rejectedByCustomer:
        return MyOrderStatus.rejectedOther;
      case MyMatchStatus.rejectedByExecutor:
        return MyOrderStatus.rejectedDeclined;
      case MyMatchStatus.expired:
        return MyOrderStatus.rejectedRemoved;
    }
  }

  MyOrderDetailState _detailStateForStatus(MyMatchStatus s) {
    switch (s) {
      case MyMatchStatus.awaitingCustomer:
        return MyOrderDetailState.offerSent;
      case MyMatchStatus.awaitingExecutor:
        return MyOrderDetailState.waitingConfirm;
      case MyMatchStatus.accepted:
        return MyOrderDetailState.confirmed;
      case MyMatchStatus.completed:
        return MyOrderDetailState.completed;
      case MyMatchStatus.rejectedByCustomer:
      case MyMatchStatus.rejectedByExecutor:
      case MyMatchStatus.expired:
        return MyOrderDetailState.rejected;
    }
  }

  String _rentDate(MyOrderMatch m) {
    final OrderListItem adapter = OrderListItem(
      id: m.orderId,
      displayNumber: 0,
      title: m.orderTitle,
      address: m.orderAddress,
      dateFrom: m.orderDateFrom,
      dateTo: m.orderDateTo,
      timeFrom: m.orderTimeFrom,
      timeTo: m.orderTimeTo,
      exactDate: m.orderExactDate,
      wholeDay: m.orderWholeDay,
      machineryTitles: m.orderMachineryTitles,
      publishedAt: m.orderPublishedAt,
      customer: CustomerSummary(
        id: m.customerId,
        name: m.customerName,
        ratingAsCustomer: m.customerRating,
        reviewCountAsCustomer: m.customerReviewCount,
      ),
    );
    return formatRentDate(adapter);
  }
}

class _OrdersSegmented extends StatelessWidget {
  const _OrdersSegmented({required this.controller, required this.items});

  final TabController controller;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        final int index = controller.index;
        final double radius = 22.r;
        return Container(
          height: 40.h,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.primary, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < items.length; i++) ...<Widget>[
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => controller.animateTo(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        alignment: Alignment.center,
                        color: i == index
                            ? AppColors.primary
                            : AppColors.surface,
                        child: Text(
                          items[i],
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w400,
                            height: 1.3,
                            color: i == index
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i < items.length - 1 && i != index && i + 1 != index)
                    Container(width: 1, color: AppColors.primary),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders({this.onGoToCatalog});

  final VoidCallback? onGoToCatalog;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Здесь появятся ваши отклики',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 20.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 6.h),
          Text(
            'Откликнитесь на заказ и получайте\nпредложения от заказчиков',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16.sp,
              fontWeight: FontWeight.w400,
              height: 1.3,
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 26.h),
          PrimaryButton(label: 'В каталог', onPressed: onGoToCatalog),
        ],
      ),
    );
  }
}

class _RetryView extends StatelessWidget {
  const _RetryView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Не удалось загрузить заказы',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16.sp,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 12.h),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

// _pluralMin/_pluralH/_pluralD оставлены как публичные утилиты для
// старых callsite'ов в `features/orders/order_detail_screen.dart`.
String pluralMin(int n) {
  if (n % 10 == 1 && n % 100 != 11) return 'минуту';
  if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
    return 'минуты';
  }
  return 'минут';
}

String pluralH(int n) {
  if (n % 10 == 1 && n % 100 != 11) return 'час';
  if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
    return 'часа';
  }
  return 'часов';
}

String pluralD(int n) {
  if (n % 10 == 1 && n % 100 != 11) return 'день';
  if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
    return 'дня';
  }
  return 'дней';
}

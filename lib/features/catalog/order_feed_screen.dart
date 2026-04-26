import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/catalog/catalog_service.dart';
import 'package:dispatcher_1/core/catalog/format.dart';
import 'package:dispatcher_1/core/catalog/models.dart';
import 'package:dispatcher_1/core/location_permission.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/catalog/order_detail_screen.dart';
import 'package:dispatcher_1/features/catalog/orders_map_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/applied_filter_chips.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/widgets/order_card.dart';
import 'package:dispatcher_1/features/shell/main_shell.dart';
import 'package:dispatcher_1/features/shell/widgets/main_bottom_nav_bar.dart';

/// Лента заказов категории. Источник — `public.orders` через
/// [CatalogService.listPublishedOrders]. Фильтры (техника/категории)
/// по-прежнему живут в глобальном [AppliedFilter]; строка поиска —
/// локальная, с небольшим debounce перед запросом.
class OrderFeedScreen extends StatefulWidget {
  const OrderFeedScreen({
    super.key,
    required this.categoryId,
    required this.categoryTitle,
  });

  final String categoryId;
  final String categoryTitle;

  @override
  State<OrderFeedScreen> createState() => _OrderFeedScreenState();
}

class _OrderFeedScreenState extends State<OrderFeedScreen> {
  int _tab = 0;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  bool _addressSelected = false;
  Timer? _debounceTimer;
  late Future<List<OrderListItem>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    AppliedFilter.revision.addListener(_onFilterChanged);
    _ordersFuture = _fetchOrders();
  }

  @override
  void dispose() {
    AppliedFilter.revision.removeListener(_onFilterChanged);
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<OrderListItem>> _fetchOrders() {
    return CatalogService.instance.listPublishedOrders(
      machineryTitles: AppliedFilter.equipment,
      categoryTitles: AppliedFilter.categories,
      search: _query.trim().isEmpty ? null : _query,
      dateFrom: AppliedFilter.dateFrom,
      dateTo: AppliedFilter.exactDate ? null : AppliedFilter.dateTo,
      addressContains: AppliedFilter.address,
      timeFrom: _hhmm(AppliedFilter.timeFrom),
      timeTo: _hhmm(AppliedFilter.timeTo),
      wholeDay: AppliedFilter.wholeDay ? true : null,
    );
  }

  /// `TimeOfDay(h:9, m:30)` → `'09:30'`. Возвращает null, если нет
  /// значения, чтобы не ставить пустое условие в SELECT.
  String? _hhmm(TimeOfDay? t) {
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  void _onFilterChanged() {
    if (!mounted) return;
    setState(() => _ordersFuture = _fetchOrders());
  }

  void _onSearchChanged(String v) {
    setState(() {
      _query = v;
      _addressSelected = false;
    });
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _ordersFuture = _fetchOrders());
    });
  }

  bool get _hasActiveFilter => hasActiveFilter();

  void _openFilter() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CatalogFilterScreen(),
      ),
    );
  }

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
            icon: Image.asset(
              'assets/icons/ui/back_arrow.webp',
              width: 24.r,
              height: 24.r,
              fit: BoxFit.contain,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Padding(
          padding: EdgeInsets.only(top: 2.h),
          child: Text(
            'Лента заказов',
            style: AppTextStyles.titleS.copyWith(color: Colors.white),
          ),
        ),
      ),
      bottomNavigationBar: MainBottomNavBar(
        items: kMainNavItems,
        currentIndex: 0,
        onTap: (int i) {
          MainShell.selectedTab.value = i;
          Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
        },
      ),
      floatingActionButton: _tab == 0
          ? Padding(
              padding: EdgeInsets.only(bottom: 24.h),
              child: AiAssistantFab(
                onTap: () => context.push('/assistant/chat'),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                color: AppColors.navBarDark,
                child: CatalogSearchBar(
                  controller: _searchCtrl,
                  hintText: _tab == 1 ? 'Поиск по адресу' : 'Поиск',
                  onFilterTap: _openFilter,
                  onChanged: _onSearchChanged,
                  showFilterBadge: _hasActiveFilter,
                ),
              ),
              SizedBox(height: 12.h),
              CatalogSegmented(
                index: _tab,
                items: const <String>['Списком', 'На карте'],
                onChanged: (int v) {
                  setState(() => _tab = v);
                  if (v == 1) ensureLocationPermission();
                },
              ),
              if (_hasActiveFilter)
                AppliedFilterChips(onChanged: () => setState(() {}))
              else
                SizedBox(height: 16.h),
              Expanded(
                child: FutureBuilder<List<OrderListItem>>(
                  future: _ordersFuture,
                  builder: (BuildContext context,
                      AsyncSnapshot<List<OrderListItem>> snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return _FeedError(
                        onRetry: () => setState(() {
                          _ordersFuture = _fetchOrders();
                        }),
                      );
                    }
                    final List<OrderListItem> orders =
                        snap.data ?? const <OrderListItem>[];
                    return IndexedStack(
                      index: _tab,
                      children: <Widget>[
                        orders.isEmpty
                            ? const _EmptyOrdersState()
                            : _OrderList(orders: orders),
                        _OrdersMapWithCard(orders: orders),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          if (_tab == 1 && _query.trim().isNotEmpty && !_addressSelected)
            Positioned(
              top: 44.h + 3.h,
              left: 16.w,
              right: 16.w,
              child: _AddressSuggestions(
                query: _query,
                onSelect: (String address) {
                  _searchCtrl.text = address;
                  setState(() {
                    _query = address;
                    _addressSelected = true;
                    _ordersFuture = _fetchOrders();
                  });
                  FocusScope.of(context).unfocus();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({required this.orders});
  final List<OrderListItem> orders;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
        itemCount: orders.length,
        separatorBuilder: (_, _) => SizedBox(height: 16.h),
        itemBuilder: (BuildContext context, int i) {
          final OrderListItem o = orders[i];
          return Container(
            decoration: BoxDecoration(
              color: AppColors.fieldFill,
              borderRadius: BorderRadius.circular(14.r),
            ),
            clipBehavior: Clip.antiAlias,
            child: OrderCard(
              title: o.title,
              address: o.address,
              rentDate: formatRentDate(o),
              publishedAgo: formatPublishedAgo(o.publishedAt),
              equipment: o.machineryTitles,
              highlightEquipment: AppliedFilter.equipment,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OrderDetailScreen(
                    orderId: o.id,
                    initialTitle: o.title,
                    multipleEquipment: o.machineryTitles.length > 1,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyOrdersState extends StatelessWidget {
  const _EmptyOrdersState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Image.asset(
              'assets/icons/profile/no_orders.webp',
              width: 80.r,
              height: 80.r,
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            'Заказы не найдены',
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
            'Попробуйте изменить фильтры',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16.sp,
              fontWeight: FontWeight.w400,
              height: 1.3,
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.onRetry});
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
              'Не удалось загрузить ленту',
              style: AppTextStyles.bodyMRegular
                  .copyWith(color: AppColors.textPrimary),
            ),
            SizedBox(height: 12.h),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

/// Карта-заглушка + плашка снизу с одним заказом. Свайп вверх по плашке
/// переключает на следующий заказ в списке (циклически).
class _OrdersMapWithCard extends StatefulWidget {
  const _OrdersMapWithCard({required this.orders});

  final List<OrderListItem> orders;

  @override
  State<_OrdersMapWithCard> createState() => _OrdersMapWithCardState();
}

class _OrdersMapWithCardState extends State<_OrdersMapWithCard> {
  int _current = 0;
  int _direction = 1;

  @override
  void didUpdateWidget(covariant _OrdersMapWithCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameOrders(oldWidget.orders, widget.orders)) {
      _current = 0;
      _direction = 1;
    }
  }

  bool _sameOrders(List<OrderListItem> a, List<OrderListItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _shift(int delta) {
    if (widget.orders.isEmpty) return;
    setState(() {
      _direction = delta;
      _current = (_current + delta) % widget.orders.length;
      if (_current < 0) _current += widget.orders.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orders.isEmpty) {
      return const OrdersMapScreen();
    }
    final int idx = _current % widget.orders.length;
    final OrderListItem o = widget.orders[idx];
    final String firstMachinery =
        o.machineryTitles.isEmpty ? '' : o.machineryTitles.first;
    return Stack(
      children: <Widget>[
        const Positioned.fill(child: OrdersMapScreen()),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (DragEndDetails d) {
              final double v = d.primaryVelocity ?? 0;
              if (v < -150) {
                _shift(1);
              } else if (v > 150) {
                _shift(-1);
              }
            },
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OrderDetailScreen(
                  orderId: o.id,
                  initialTitle: o.title,
                  multipleEquipment: o.machineryTitles.length > 1,
                ),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              reverseDuration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutQuint,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder:
                  (Widget? current, List<Widget> previous) => Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  ...previous,
                  ?current,
                ],
              ),
              transitionBuilder: (Widget child, Animation<double> anim) {
                final bool isIncoming = child.key == ValueKey<int>(idx);
                final double dir = _direction.toDouble();
                final Animation<Offset> slide = Tween<Offset>(
                  begin: isIncoming ? Offset(0, 0.55 * dir) : Offset.zero,
                  end: isIncoming ? Offset.zero : Offset(0, -0.9 * dir),
                ).animate(anim);
                final Animation<double> scale = Tween<double>(
                  begin: isIncoming ? 0.88 : 1.0,
                  end: isIncoming ? 1.0 : 0.94,
                ).animate(anim);
                final Animation<double> fade = CurvedAnimation(
                  parent: anim,
                  curve: isIncoming
                      ? const Interval(0.15, 1.0, curve: Curves.easeOut)
                      : const Interval(0.0, 0.7, curve: Curves.easeIn),
                );
                return SlideTransition(
                  position: slide,
                  child: ScaleTransition(
                    scale: scale,
                    child: FadeTransition(opacity: fade, child: child),
                  ),
                );
              },
              child: Container(
                key: ValueKey<int>(idx),
                margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 20.h),
                padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 12.h),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16.r),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          firstMachinery,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 12.sp,
                            color: AppliedFilter.equipment
                                    .contains(firstMachinery)
                                ? AppColors.primary
                                : AppColors.textTertiary,
                            height: 1.3,
                          ),
                        ),
                        Text(
                          formatPublishedAgo(o.publishedAt),
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 12.sp,
                            color: AppColors.textTertiary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      o.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleS.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    _MapCardLine(
                        label: 'Дата аренды:', value: formatRentDate(o)),
                    SizedBox(height: 4.h),
                    _MapCardLine(label: 'Адрес:', value: o.address),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapCardLine extends StatelessWidget {
  const _MapCardLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12.sp,
          color: AppColors.textPrimary,
          height: 1.4,
        ),
        children: <TextSpan>[
          TextSpan(
            text: '$label ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Выпадающий список моковых адресов для вкладки «На карте».
/// Пока статический список — подключение геокодера это отдельная задача.
class _AddressSuggestions extends StatelessWidget {
  const _AddressSuggestions({
    required this.query,
    required this.onSelect,
  });

  final String query;
  final ValueChanged<String> onSelect;

  static const List<String> _all = <String>[
    'Московская область, Москва, ул. Ленина, д. 10',
    'Московская область, Москва, ул. Пушкина, д. 25',
    'Московская область, Москва, пр. Мира, д. 3',
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12.r),
      color: AppColors.surface,
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.symmetric(vertical: 8.h),
        itemCount: _all.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          thickness: 0.5,
          indent: 16.w,
          endIndent: 16.w,
          color: AppColors.divider,
        ),
        itemBuilder: (BuildContext context, int i) {
          return InkWell(
            onTap: () => onSelect(_all[i]),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: 16.w, vertical: 12.h),
              child: Row(
                children: <Widget>[
                  Icon(Icons.location_on_outlined,
                      size: 20.r, color: AppColors.textTertiary),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      _all[i],
                      style: AppTextStyles.bodyMRegular.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 14.sp,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

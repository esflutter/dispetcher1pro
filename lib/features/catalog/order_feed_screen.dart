import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

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

/// Лента заказов категории. Соответствует Figma «Лента заказов»:
/// тёмный AppBar → строка поиска + оранжевый фильтр → pill-табы
/// «Списком / На карте» → список карточек или карта.
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

  @override
  void initState() {
    super.initState();
    AppliedFilter.revision.addListener(_onFilterChanged);
  }

  @override
  void dispose() {
    AppliedFilter.revision.removeListener(_onFilterChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasActiveFilter => hasActiveFilter();

  List<_MockOrder> get _visibleOrders {
    final String q = _query.trim().toLowerCase();
    Iterable<_MockOrder> res = _orders;

    if (AppliedFilter.categories.isNotEmpty) {
      res = res.where((_MockOrder o) =>
          o.categories.any(AppliedFilter.categories.contains));
    }
    if (AppliedFilter.equipment.isNotEmpty) {
      res = res.where((_MockOrder o) =>
          o.equipment.any(AppliedFilter.equipment.contains));
    }

    if (q.isNotEmpty) {
      res = res.where((_MockOrder o) {
        if (o.title.toLowerCase().contains(q)) return true;
        if (o.address.toLowerCase().contains(q)) return true;
        for (final String e in o.equipment) {
          if (e.toLowerCase().contains(q)) return true;
        }
        return false;
      });
    }

    return res.toList();
  }

  static const List<_MockOrder> _orders = <_MockOrder>[
    _MockOrder(
      id: '1',
      title: 'Нужен экскаватор для копки траншеи',
      address: 'Московская область, Москва, Улица1, д 144',
      rentDate: '15 июня · 09:00–18:00',
      publishedAgo: '2 часа назад',
      equipment: <String>['Экскаватор'],
      categories: <String>['Земляные работы'],
    ),
    _MockOrder(
      id: '2',
      title: 'Земляные работы',
      address: 'Московская область, Москва, Улица1, д 144',
      rentDate: '15 июня · 09:00–18:00',
      publishedAgo: 'Сегодня в 11:30',
      equipment: <String>['Автокран', 'Экскаватор'],
      categories: <String>['Земляные работы', 'Строительные работы'],
      price: '120 000 – 150 000 ₽',
    ),
    _MockOrder(
      id: '3',
      title: 'Разработка котлована под фундамент',
      address: 'Московская область, Москва, Улица1, д 144',
      rentDate: '15 июня · 09:00–18:00',
      publishedAgo: 'Сегодня в 11:30',
      equipment: <String>[
        'Экскаватор',
        'Автокран',
        'Эвакуатор',
        'Манипулятор',
        'Автовышка',
      ],
      categories: <String>['Земляные работы', 'Строительные работы'],
    ),
    _MockOrder(
      id: '4',
      title: 'Нужен экскаватор для копки траншеи',
      address: 'Московская область, Москва, Улица1, д 144',
      rentDate: '15 июня · 09:00–18:00',
      publishedAgo: '2 часа назад',
      equipment: <String>['Экскаватор'],
      categories: <String>['Земляные работы'],
    ),
  ];

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
        // +2 сверху и -10 снизу: добавляем верхний паддинг статус-бару
        // самой AppBar, общий toolbarHeight сокращаем на 8 — в сумме
        // даёт сдвиг вверх на 10 снизу и прибавку 2 сверху.
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
          // Сначала выставляем нужный таб в shell через общий notifier,
          // затем возвращаемся к корневому маршруту shell.
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
                  onChanged: (String v) => setState(() {
                    _query = v;
                    _addressSelected = false;
                  }),
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
                SizedBox(height: 12.h),
              Expanded(
                // IndexedStack вместо ternary — чтобы состояние обоих табов
                // (ввод в поиске, позиция скролла, карта) сохранялось при
                // переключении и не сбрасывалось при setState от ввода текста.
                child: IndexedStack(
                  index: _tab,
                  children: <Widget>[
                    _visibleOrders.isEmpty
                        ? const _EmptyOrdersState()
                        : MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: _visibleOrders.length,
                              itemBuilder: (BuildContext context, int i) {
                                final _MockOrder o = _visibleOrders[i];
                                final bool isLast =
                                    i == _visibleOrders.length - 1;
                                return Column(
                                  children: <Widget>[
                                    OrderCard(
                                      title: o.title,
                                      address: o.address,
                                      rentDate: o.rentDate,
                                      publishedAgo: o.publishedAgo,
                                      equipment: o.equipment,
                                      highlightEquipment:
                                          AppliedFilter.equipment,
                                      price: o.price,
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => OrderDetailScreen(
                                            orderId: o.id,
                                            multipleEquipment:
                                                o.equipment.length > 1,
                                            price: o.price,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (!isLast)
                                      Container(
                                        height: 1 /
                                            MediaQuery.of(context)
                                                .devicePixelRatio,
                                        color: AppColors.primary,
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                    _OrdersMapWithCard(orders: _visibleOrders),
                  ],
                ),
              ),
            ],
          ),
          // Выпадающий список адресов при вводе на вкладке «На карте».
          if (_tab == 1 && _query.trim().isNotEmpty && !_addressSelected)
            Positioned(
              // Вплотную под строкой поиска: высота поиска (44h) + нижний
              // паддинг CatalogSearchBar (12h).
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

class _EmptyOrdersState extends StatelessWidget {
  const _EmptyOrdersState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12.h),
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

class _MockOrder {
  const _MockOrder({
    required this.id,
    required this.title,
    required this.address,
    required this.rentDate,
    required this.publishedAgo,
    required this.equipment,
    this.categories = const <String>[],
    this.price = '80 000 – 100 000 ₽',
  });
  final String id;
  final String title;
  final String address;
  final String rentDate;
  final String publishedAgo;
  final List<String> equipment;
  final List<String> categories;
  final String price;
}

/// Карта-заглушка + плашка снизу с одним заказом. Свайп вверх по плашке
/// переключает на следующий заказ в списке (циклически).
class _OrdersMapWithCard extends StatefulWidget {
  const _OrdersMapWithCard({required this.orders});

  final List<_MockOrder> orders;

  @override
  State<_OrdersMapWithCard> createState() => _OrdersMapWithCardState();
}

class _OrdersMapWithCardState extends State<_OrdersMapWithCard> {
  int _current = 0;
  // Направление последнего свайпа: 1 — вверх (следующий),
  // -1 — вниз (предыдущий). Используется, чтобы задать направление
  // слайд-анимации в AnimatedSwitcher.
  int _direction = 1;

  @override
  void didUpdateWidget(covariant _OrdersMapWithCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Если набор заказов поменялся (например, применили/сняли фильтр),
    // возвращаемся к первой карточке — иначе пользователь увидит
    // произвольный заказ из середины отфильтрованного списка.
    if (!_sameOrders(oldWidget.orders, widget.orders)) {
      _current = 0;
      _direction = 1;
    }
  }

  bool _sameOrders(List<_MockOrder> a, List<_MockOrder> b) {
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
      _current =
          (_current + delta) % widget.orders.length;
      if (_current < 0) _current += widget.orders.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orders.isEmpty) {
      return const OrdersMapScreen();
    }
    // Если список отфильтровался короче, держим индекс в пределах.
    final int idx = _current % widget.orders.length;
    final _MockOrder o = widget.orders[idx];
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
              // Свайп вверх → следующий, вниз → предыдущий.
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
                  multipleEquipment: o.equipment.length > 1,
                  price: o.price,
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
                // Входящая въезжает из направления свайпа, уходящая —
                // улетает в противоположную сторону. Плюс масштаб и fade.
                final double dir = _direction.toDouble();
                final Animation<Offset> slide = Tween<Offset>(
                  begin: isIncoming
                      ? Offset(0, 0.55 * dir)
                      : Offset.zero,
                  end: isIncoming
                      ? Offset.zero
                      : Offset(0, -0.9 * dir),
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
                          o.equipment.first,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 12.sp,
                            color: AppliedFilter.equipment
                                    .contains(o.equipment.first)
                                ? AppColors.primary
                                : AppColors.textTertiary,
                            height: 1.3,
                          ),
                        ),
                        Text(
                          o.publishedAgo,
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
                    _MapCardLine(label: 'Дата аренды:', value: o.rentDate),
                    SizedBox(height: 4.h),
                    _MapCardLine(label: 'Адрес:', value: o.address),
                    SizedBox(height: 10.h),
                    Text(
                      o.price,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
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

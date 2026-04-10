import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/catalog/order_detail_screen.dart';
import 'package:dispatcher_1/features/catalog/orders_map_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/widgets/order_card.dart';
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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_MockOrder> get _visibleOrders {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return _orders;
    return _orders.where((_MockOrder o) {
      if (o.title.toLowerCase().contains(q)) return true;
      if (o.address.toLowerCase().contains(q)) return true;
      for (final String e in o.equipment) {
        if (e.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  static const List<_MockOrder> _orders = <_MockOrder>[
    _MockOrder(
      id: '1',
      title: 'Нужен экскаватор для копки траншеи',
      address: 'Московская область, Москва, Улица1, д 144',
      rentDate: '15 июня · 09:00–18:00',
      publishedAgo: '2 часа назад',
      equipment: <String>['Экскаватор'],
    ),
    _MockOrder(
      id: '2',
      title: 'Земляные работы',
      address: 'Московская область, Москва, Улица1, д 144',
      rentDate: '15 июня · 09:00–18:00',
      publishedAgo: 'Сегодня в 11:30',
      equipment: <String>['Автокран', 'Экскаватор'],
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
    ),
    _MockOrder(
      id: '4',
      title: 'Нужен экскаватор для копки траншеи',
      address: 'Московская область, Москва, Улица1, д 144',
      rentDate: '15 июня · 09:00–18:00',
      publishedAgo: '2 часа назад',
      equipment: <String>['Экскаватор'],
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
        onTap: (int _) {
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
                  onFilterTap: _openFilter,
                  onChanged: (String v) => setState(() => _query = v),
                ),
              ),
              SizedBox(height: 12.h),
              CatalogSegmented(
                index: _tab,
                items: const <String>['Списком', 'На карте'],
                onChanged: (int v) => setState(() => _tab = v),
              ),
              Expanded(
                // IndexedStack вместо ternary — чтобы состояние обоих табов
                // (ввод в поиске, позиция скролла, карта) сохранялось при
                // переключении и не сбрасывалось при setState от ввода текста.
                child: IndexedStack(
                  index: _tab,
                  children: <Widget>[
                    MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: ListView.builder(
                      padding: EdgeInsets.only(bottom: 24.h),
                      itemCount: _visibleOrders.length,
                      itemBuilder: (BuildContext context, int i) {
                        final _MockOrder o = _visibleOrders[i];
                        return Column(
                          children: <Widget>[
                            OrderCard(
                              title: o.title,
                              address: o.address,
                              rentDate: o.rentDate,
                              publishedAgo: o.publishedAgo,
                              equipment: o.equipment,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => OrderDetailScreen(
                                    orderId: o.id,
                                    multipleEquipment:
                                        o.equipment.length > 1,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              height: 1 /
                                  MediaQuery.of(context).devicePixelRatio,
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
    this.price = '80 000 – 100 000 ₽',
  });
  final String id;
  final String title;
  final String address;
  final String rentDate;
  final String publishedAgo;
  final List<String> equipment;
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
                            color: AppColors.textTertiary,
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

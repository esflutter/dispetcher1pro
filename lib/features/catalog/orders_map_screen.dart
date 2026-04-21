import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/catalog/order_detail_screen.dart';
import 'package:dispatcher_1/features/catalog/order_feed_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/applied_filter_chips.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';

/// Плейсхолдер карты со списком заказов. Используется как контент таба
/// «На карте» внутри `OrderFeedScreen`. Реальная карта подключится позже.
class OrdersMapScreen extends StatefulWidget {
  const OrdersMapScreen({super.key, this.showSearchBar = false});

  /// Если true — рисует поверх собственный поиск+фильтр (когда экран
  /// открыт отдельным маршрутом, а не как таб).
  final bool showSearchBar;

  @override
  State<OrdersMapScreen> createState() => _OrdersMapScreenState();
}

class _OrdersMapScreenState extends State<OrdersMapScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Image.asset(
        'assets/images/map_placeholder.webp',
        fit: BoxFit.cover,
        alignment: Alignment.center,
      ),
    );
  }
}

/// Полноэкранный «Заказы на карте» — отдельный маршрут с собственным
/// тёмным AppBar и строкой поиска.
class OrdersMapFullScreen extends StatefulWidget {
  const OrdersMapFullScreen({super.key});

  @override
  State<OrdersMapFullScreen> createState() => _OrdersMapFullScreenState();
}

class _OrdersMapFullScreenState extends State<OrdersMapFullScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  bool _addressSelected = false;
  int _current = 0;
  int _direction = 1;

  // Снимок фильтра каталога на момент открытия карты. На карте фильтр
  // стартует пустым (пользователь задаёт его заново), но исходное
  // состояние ленты нужно вернуть при выходе, чтобы каталог не потерял
  // уже применённые настройки.
  late final Set<String> _savedCategories;
  late final Set<String> _savedEquipment;
  late final DateTime? _savedDateFrom;
  late final DateTime? _savedDateTo;
  late final bool _savedExactDate;
  late final TimeOfDay? _savedTimeFrom;
  late final TimeOfDay? _savedTimeTo;
  late final bool _savedWholeDay;
  late final int? _savedRadiusKm;
  late final String? _savedAddress;

  @override
  void initState() {
    super.initState();
    _savedCategories = Set<String>.from(AppliedFilter.categories);
    _savedEquipment = Set<String>.from(AppliedFilter.equipment);
    _savedDateFrom = AppliedFilter.dateFrom;
    _savedDateTo = AppliedFilter.dateTo;
    _savedExactDate = AppliedFilter.exactDate;
    _savedTimeFrom = AppliedFilter.timeFrom;
    _savedTimeTo = AppliedFilter.timeTo;
    _savedWholeDay = AppliedFilter.wholeDay;
    _savedRadiusKm = AppliedFilter.radiusKm;
    _savedAddress = AppliedFilter.address;

    AppliedFilter.categories.clear();
    AppliedFilter.equipment.clear();
    AppliedFilter.dateFrom = null;
    AppliedFilter.dateTo = null;
    AppliedFilter.exactDate = false;
    AppliedFilter.timeFrom = null;
    AppliedFilter.timeTo = null;
    AppliedFilter.wholeDay = false;
    AppliedFilter.radiusKm = null;
    AppliedFilter.address = null;

    AppliedFilter.revision.addListener(_onFilterChanged);
  }

  void _onFilterChanged() {
    if (mounted) setState(() => _current = 0);
  }

  List<_MapOrder> get _visibleOrders {
    if (AppliedFilter.equipment.isEmpty) return _orders;
    return _orders
        .where((_MapOrder o) => AppliedFilter.equipment.contains(o.equipment))
        .toList();
  }

  /// Источник данных — общий [CatalogOrderMock.all]. Карта показывает тот же
  /// набор заказов, что и лента; при открытии деталей данные совпадают.
  /// Модель [_MapOrder] хранит одно значение техники, поэтому берём первое
  /// из списка `equipment`.
  static List<_MapOrder> get _orders => CatalogOrderMock.all
      .map((CatalogOrderMock o) => _MapOrder(
            id: o.id,
            equipment: o.equipment.isNotEmpty ? o.equipment.first : '',
            title: o.title,
            rentDate: o.rentDate,
            address: o.address,
            publishedAgo: o.publishedAgo,
          ))
      .toList();

  void _shift(int delta) {
    final int count = _visibleOrders.length;
    if (count == 0) return;
    setState(() {
      _direction = delta;
      _current = (_current + delta) % count;
      if (_current < 0) _current += count;
    });
  }

  @override
  void dispose() {
    AppliedFilter.revision.removeListener(_onFilterChanged);
    AppliedFilter.categories
      ..clear()
      ..addAll(_savedCategories);
    AppliedFilter.equipment
      ..clear()
      ..addAll(_savedEquipment);
    AppliedFilter.dateFrom = _savedDateFrom;
    AppliedFilter.dateTo = _savedDateTo;
    AppliedFilter.exactDate = _savedExactDate;
    AppliedFilter.timeFrom = _savedTimeFrom;
    AppliedFilter.timeTo = _savedTimeTo;
    AppliedFilter.wholeDay = _savedWholeDay;
    AppliedFilter.radiusKm = _savedRadiusKm;
    AppliedFilter.address = _savedAddress;
    AppliedFilter.revision.value = AppliedFilter.revision.value + 1;
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double searchTop = MediaQuery.of(context).padding.top + 48.h;
    final bool active = hasActiveFilter();
    final List<_MapOrder> orders = _visibleOrders;
    final int idx = orders.isEmpty ? 0 : _current % orders.length;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: OrdersMapScreen()),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8.w,
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textPrimary, size: 20.r),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            top: searchTop,
            left: 0,
            right: 0,
            child: Column(
              children: <Widget>[
                CatalogSearchBar(
                  controller: _searchCtrl,
                  hintText: 'Поиск по адресу',
                  onFilterTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CatalogFilterScreen(),
                    ),
                  ),
                  onChanged: (String v) => setState(() {
                    _query = v;
                    _addressSelected = false;
                  }),
                  showFilterBadge: active,
                ),
                if (active)
                  AppliedFilterChips(
                    onChanged: () => setState(() {}),
                    // На карте поисковая строка сама даёт 8.h снизу —
                    // убираем верхний отступ чипов, чтобы суммарный
                    // визуальный зазор между ними тоже был 8.h.
                    topPadding: 0,
                  ),
              ],
            ),
          ),
          if (_query.trim().isNotEmpty && !_addressSelected)
            Positioned(
              // `CatalogSearchBar` имеет 8.h сверху + 44.h строка +
              // 8.h снизу. Под строкой оставляем минимальный зазор 2.h,
              // чтобы плашка не сливалась со строкой, но и не «висела».
              top: searchTop + 8.h + 44.h + 2.h,
              left: 16.w,
              right: 16.w,
              child: _AddressSuggestions(
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
          if (orders.isEmpty && active)
            Positioned(
              left: 16.w,
              right: 16.w,
              bottom: 32.h + MediaQuery.of(context).padding.bottom,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 16.w, vertical: 14.h),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12.r),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  'По текущим фильтрам заказов не найдено. '
                  'Попробуйте изменить параметры фильтра.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMRegular
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ),
          if (orders.isNotEmpty)
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
                onTap: () {
                  final _MapOrder o = orders[idx];
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OrderDetailScreen(
                        orderId: o.id,
                      ),
                    ),
                  );
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  reverseDuration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutQuint,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (Widget? current, List<Widget> previous) =>
                      Stack(
                    alignment: Alignment.bottomCenter,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (Widget child, Animation<double> anim) {
                    final bool isIn = child.key == ValueKey<int>(idx);
                    final double dir = _direction.toDouble();
                    final slide = Tween<Offset>(
                      begin: isIn ? Offset(0, 0.55 * dir) : Offset.zero,
                      end: isIn ? Offset.zero : Offset(0, -0.9 * dir),
                    ).animate(anim);
                    final scale = Tween<double>(
                      begin: isIn ? 0.88 : 1.0,
                      end: isIn ? 1.0 : 0.94,
                    ).animate(anim);
                    final fade = CurvedAnimation(
                      parent: anim,
                      curve: isIn
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
                  child: _buildOrderCard(orders[idx], idx),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(_MapOrder o, int idx) {
    final bool matched = AppliedFilter.equipment.contains(o.equipment);
    return Container(
      key: ValueKey<int>(idx),
      margin: EdgeInsets.fromLTRB(12.w, 0, 12.w,
          20.h + MediaQuery.of(context).padding.bottom),
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
              Text(o.equipment,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 12.sp,
                    color: matched
                        ? AppColors.primary
                        : AppColors.textTertiary,
                    height: 1.3,
                  )),
              Text(o.publishedAgo,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 12.sp,
                    color: AppColors.textTertiary,
                    height: 1.3,
                  )),
            ],
          ),
          SizedBox(height: 8.h),
          Text(o.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleS.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              )),
          SizedBox(height: 8.h),
          _mapLine('Дата аренды:', o.rentDate),
          SizedBox(height: 4.h),
          _mapLine('Адрес:', o.address),
        ],
      ),
    );
  }

  Widget _mapLine(String label, String value) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12.sp,
          color: AppColors.textPrimary,
          height: 1.4,
        ),
        children: <TextSpan>[
          TextSpan(text: '$label ', style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: value, style: TextStyle(fontWeight: FontWeight.w400, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _MapOrder {
  const _MapOrder({
    required this.id,
    required this.equipment,
    required this.title,
    required this.rentDate,
    required this.address,
    required this.publishedAgo,
  });
  final String id;
  final String equipment;
  final String title;
  final String rentDate;
  final String address;
  final String publishedAgo;
}

class _AddressSuggestions extends StatelessWidget {
  const _AddressSuggestions({required this.onSelect});

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
              padding:
                  EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
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

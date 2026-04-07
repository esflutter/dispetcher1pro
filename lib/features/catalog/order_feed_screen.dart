import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/catalog/order_detail_screen.dart';
import 'package:dispatcher_1/features/catalog/orders_map_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/order_card.dart';

/// Лента заказов категории — табы «Список / На карте».
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

  static const List<_MockOrder> _orders = <_MockOrder>[
    _MockOrder(
      id: '1',
      title: 'Копка котлована под фундамент',
      price: '15 000 ₽',
      address: 'Москва, ул. Ленина, 10',
      dateTime: 'Сегодня, 14:00',
      equipment: 'Экскаватор-погрузчик',
    ),
    _MockOrder(
      id: '2',
      title: 'Планировка участка',
      price: '8 500 ₽',
      address: 'МО, г. Химки, ул. Заводская',
      dateTime: 'Завтра, 09:00',
      equipment: 'Бульдозер',
    ),
    _MockOrder(
      id: '3',
      title: 'Вывоз грунта',
      price: '22 000 ₽',
      address: 'Москва, Каширское шоссе, 88',
      dateTime: '12 апреля, 08:00',
      equipment: 'Самосвал, экскаватор',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.categoryTitle,
          style: AppTextStyles.titleS.copyWith(color: Colors.white),
        ),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.tune, color: Colors.white, size: 24.r),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CatalogFilterScreen(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
            child: _SegmentedControl(
              index: _tab,
              items: const <String>['Списком', 'На карте'],
              onChanged: (int v) => setState(() => _tab = v),
            ),
          ),
          Expanded(
            child: _tab == 0
                ? ListView.separated(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenH,
                      vertical: 8.h,
                    ),
                    itemCount: _orders.length,
                    separatorBuilder: (_, _) => SizedBox(height: 8.h),
                    itemBuilder: (BuildContext context, int i) {
                      final _MockOrder o = _orders[i];
                      return OrderCard(
                        title: o.title,
                        price: o.price,
                        address: o.address,
                        dateTime: o.dateTime,
                        equipment: o.equipment,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => OrderDetailScreen(orderId: o.id),
                          ),
                        ),
                      );
                    },
                  )
                : const OrdersMapScreen(),
          ),
        ],
      ),
    );
  }
}

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.index,
    required this.items,
    required this.onChanged,
  });

  final int index;
  final List<String> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36.h,
      padding: EdgeInsets.all(4.r),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(100.r),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(7.r),
                    boxShadow: i == index
                        ? <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    items[i],
                    style: AppTextStyles.tabActive.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight:
                          i == index ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
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
    required this.price,
    required this.address,
    required this.dateTime,
    required this.equipment,
  });
  final String id;
  final String title;
  final String price;
  final String address;
  final String dateTime;
  final String equipment;
}

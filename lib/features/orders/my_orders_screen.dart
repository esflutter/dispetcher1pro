import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/features/orders/order_detail_screen.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/orders/widgets/order_list_card.dart';

/// Экран «Мои заказы» — табы Новые / Принятые / Не принятые.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen>
    with SingleTickerProviderStateMixin {
  static const List<_OrderMock> _newOrders = [
    _OrderMock(
      id: '1',
      title: 'Рытьё котлована',
      dateTime: '12 апр, 09:00 — 18:00',
      equipment: 'Экскаватор-погрузчик',
      address: 'г. Москва, ул. Ленина, 12',
      status: OrderCardStatus.waiting,
    ),
    _OrderMock(
      id: '2',
      title: 'Уборка снега',
      dateTime: '13 апр, 07:00 — 12:00',
      equipment: 'Трактор МТЗ',
      address: 'г. Москва, Тверская, 8',
      status: OrderCardStatus.waiting,
    ),
  ];

  static const List<_OrderMock> _acceptedOrders = [
    _OrderMock(
      id: '3',
      title: 'Перевозка груза',
      dateTime: '10 апр, 10:00 — 16:00',
      equipment: 'Самосвал 10т',
      address: 'г. Москва, Профсоюзная, 45',
      status: OrderCardStatus.accepted,
    ),
    _OrderMock(
      id: '4',
      title: 'Демонтаж бетона',
      dateTime: '08 апр, 09:00 — 14:00',
      equipment: 'Гидромолот',
      address: 'г. Москва, Арбат, 2',
      status: OrderCardStatus.completed,
    ),
  ];

  static const List<_OrderMock> _rejectedOrders = [
    _OrderMock(
      id: '5',
      title: 'Погрузка щебня',
      dateTime: '05 апр, 08:00 — 11:00',
      equipment: 'Погрузчик фронтальный',
      address: 'г. Москва, МКАД 32 км',
      status: OrderCardStatus.rejected,
    ),
  ];

  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
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
        titleSpacing: AppSpacing.screenH,
        toolbarHeight: 81.h,
        title: Text(
          'Мои заказы',
          style: AppTextStyles.h1.copyWith(color: Colors.white),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(48.h),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              labelStyle: AppTextStyles.tabActive,
              unselectedLabelStyle: AppTextStyles.tabInactive,
              labelColor: AppColors.textPrimary,
              unselectedLabelColor: AppColors.textTertiary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              tabs: const [
                Tab(text: 'Новые'),
                Tab(text: 'Принятые'),
                Tab(text: 'Не принятые'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildList(_newOrders),
          _buildList(_acceptedOrders),
          _buildList(_rejectedOrders),
        ],
      ),
    );
  }

  Widget _buildList(List<_OrderMock> items) {
    if (items.isEmpty) {
      return const _EmptyOrders();
    }
    return ListView.separated(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.md,
      ),
      itemCount: items.length,
      separatorBuilder: (_, _) => SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        final o = items[i];
        return OrderListCard(
          title: o.title,
          dateTime: o.dateTime,
          equipment: o.equipment,
          address: o.address,
          status: o.status,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MyOrderDetailScreen(
                  state: _stateForStatus(o.status),
                  title: o.title,
                  dateTime: o.dateTime,
                  equipment: o.equipment,
                  workType: 'Земляные работы',
                  address: o.address,
                  customerName: 'Иван Петров',
                ),
              ),
            );
          },
        );
      },
    );
  }

  MyOrderDetailState _stateForStatus(OrderCardStatus s) {
    switch (s) {
      case OrderCardStatus.waiting:
        return MyOrderDetailState.waiting;
      case OrderCardStatus.accepted:
        return MyOrderDetailState.accepted;
      case OrderCardStatus.rejected:
        return MyOrderDetailState.rejected;
      case OrderCardStatus.completed:
        return MyOrderDetailState.completed;
    }
  }
}

class _OrderMock {
  const _OrderMock({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.equipment,
    required this.address,
    required this.status,
  });

  final String id;
  final String title;
  final String dateTime;
  final String equipment;
  final String address;
  final OrderCardStatus status;
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            'Откликнитесь на заказ и получайте предложения от заказчиков',
            style: AppTextStyles.titleL,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            'Здесь появятся ваши отклики',
            style: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'В каталог',
            onPressed: () => context.go('/shell'),
          ),
        ],
      ),
    );
  }
}

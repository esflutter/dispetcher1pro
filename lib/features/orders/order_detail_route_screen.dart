import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/push/pending_deep_link.dart';
import '../../core/theme/app_colors.dart';
import '../shell/main_shell.dart';

/// Обёртка для маршрута `/orders/:id`. Сам экран деталей принимает кучу
/// полей (mэтч, заказчик, услуга, состояние FSM) — поднимать всё это
/// дублирующим запросом «загрузи заказ по id» было бы хрупко.
///
/// Поэтому маршрут:
///   1. Записывает `orderId` в `pendingOrderDeepLink`.
///   2. Уводит роутер на `/shell` и переключает таб «Мои заказы».
///   3. MyOrdersScreen в своём store найдёт мэтч с этим order_id и
///      сам откроет MyOrderDetailScreen — переиспользуя ту же логику,
///      что и обычный тап карточки.
class OrderDetailRouteScreen extends StatefulWidget {
  const OrderDetailRouteScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderDetailRouteScreen> createState() => _OrderDetailRouteScreenState();
}

class _OrderDetailRouteScreenState extends State<OrderDetailRouteScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      pendingOrderDeepLink.value = widget.orderId;
      MainShell.selectedTab.value = 1; // «Мои заказы»
      try {
        GoRouter.of(context).go('/shell');
      } catch (_) {
        // Если роутер не доступен по контексту (теоретически) — просто
        // оставляем юзера на спиннере; на следующем frame перерендер
        // подхватит правильное состояние.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

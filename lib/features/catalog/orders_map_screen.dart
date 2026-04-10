import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/location_permission.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
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
    // При каждом входе на карту запрашиваем геолокацию, если разрешение
    // ещё не выдано. Результат пока не используем — реальная карта будет
    // подключена позже, но системный диалог появится сразу.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ensureLocationPermission();
    });
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
class OrdersMapFullScreen extends StatelessWidget {
  const OrdersMapFullScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
            top: MediaQuery.of(context).padding.top + 48.h,
            left: 0,
            right: 0,
            child: CatalogSearchBar(
              onFilterTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CatalogFilterScreen(),
                ),
              ),
            ),
          ),
        ],
      ),

    );
  }
}

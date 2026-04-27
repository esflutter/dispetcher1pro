import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:latlong2/latlong.dart';

import 'package:dispatcher_1/core/catalog/catalog_service.dart';
import 'package:dispatcher_1/core/catalog/format.dart';
import 'package:dispatcher_1/core/catalog/models.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/mock_coords.dart';
import 'package:dispatcher_1/features/catalog/order_detail_screen.dart';
import 'package:dispatcher_1/features/catalog/orders_map_screen.dart';

/// Просмотр заказа на карте — карта во весь экран и нижняя карточка
/// заказа (по Figma «Просмотр заказа на карте»).
///
/// Грузит заказ из БД, чтобы поставить маркер по реальным
/// `orders.latitude`/`orders.longitude` и центрировать карту на нём.
/// Если координат нет (старый заказ создан до подключения DaData) —
/// fallback на детерминированный мок [mockMoscowCoordsForId].
class OrderOnMapScreen extends StatefulWidget {
  const OrderOnMapScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderOnMapScreen> createState() => _OrderOnMapScreenState();
}

class _OrderOnMapScreenState extends State<OrderOnMapScreen> {
  late final Future<OrderDetail?> _future;

  @override
  void initState() {
    super.initState();
    _future = CatalogService.instance.getOrderDetail(widget.orderId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<OrderDetail?>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<OrderDetail?> snap) {
          // Пока заказ не пришёл из БД — рисуем карту с fallback-координатами,
          // чтобы экран не моргал серым прямоугольником. Когда снапшот
          // придёт, ребилд подменит маркер и центр на реальные координаты.
          final OrderDetail? d = snap.data;
          final double? lat = d?.latitude;
          final double? lon = d?.longitude;
          final LatLng center = (lat != null && lon != null)
              ? LatLng(lat, lon)
              : mockMoscowCoordsForId(widget.orderId);

          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: OrdersMapScreen(
                  // Ключ привязывает state карты к выбранным координатам:
                  // после прихода заказа FlutterMap пересоздаётся и
                  // initialCenter перерисовывает карту на реальной точке.
                  // Без ключа initialCenter применяется только при первом
                  // mount-е, и пользователь остался бы на mock-координатах
                  // даже после успешной подгрузки.
                  key: ValueKey<String>(
                    'order-map-${widget.orderId}-${lat ?? 'mock'}-${lon ?? 'mock'}',
                  ),
                  markers: <OrderMarkerData>[
                    OrderMarkerData(
                      id: widget.orderId,
                      lat: lat,
                      lon: lon,
                    ),
                  ],
                  initialCenter: center,
                  initialZoom: 14,
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8.w,
                child: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      color: AppColors.textPrimary, size: 20.r),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
                  padding: EdgeInsets.all(16.w),
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
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            OrderDetailScreen(orderId: widget.orderId),
                      ),
                    ),
                    child: d == null
                        ? SizedBox(
                            height: 96.h,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      d.machineryTitles.isEmpty
                                          ? 'Заказ'
                                          : d.machineryTitles.join(', '),
                                      style: AppTextStyles.caption.copyWith(
                                          color: AppColors.textTertiary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    formatPublishedAgo(d.publishedAt),
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textTertiary),
                                  ),
                                ],
                              ),
                              SizedBox(height: 6.h),
                              Text(
                                d.title,
                                style: AppTextStyles.titleS
                                    .copyWith(fontWeight: FontWeight.w700),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 8.h),
                              _Line(
                                label: 'Дата аренды:',
                                value: formatRentDateFromDetail(d),
                              ),
                              SizedBox(height: 2.h),
                              _Line(label: 'Адрес:', value: d.address),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});
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

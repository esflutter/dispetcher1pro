import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';

/// Точка на карте с уникальным id (id заказа). Вынесено в отдельный
/// тип, а не `Marker` напрямую, чтобы при возможной миграции на
/// Mapbox/Yandex MapKit поменять только внутренности [OpenFreeMapView],
/// а не все вызывающие места.
class OpenFreeMapMarker {
  const OpenFreeMapMarker({required this.id, required this.point});
  final String id;
  final LatLng point;
}

/// Карта на основе OpenFreeMap (бесплатные векторные тайлы OSM).
///
/// Атрибуция «© OpenStreetMap © OpenMapTiles» обязательна по лицензии
/// и рисуется в правом нижнем углу.
///
/// Стиль кэшируется в State, а не в статике: при повторном открытии
/// экрана создаётся новый State и стиль перечитывается. Это отказ от
/// микро-оптимизации в обмен на корректность — иначе один сетевой сбой
/// «травил» бы кэш до перезапуска приложения, а попытка обнулять кэш
/// в `builder` провоцировала retry-loop при каждом setState родителя.
class OpenFreeMapView extends StatefulWidget {
  const OpenFreeMapView({
    super.key,
    this.markers = const <OpenFreeMapMarker>[],
    this.initialCenter,
    this.initialZoom = 11,
    this.onMarkerTap,
  });

  final List<OpenFreeMapMarker> markers;
  final LatLng? initialCenter;
  final double initialZoom;
  final ValueChanged<String>? onMarkerTap;

  @override
  State<OpenFreeMapView> createState() => _OpenFreeMapViewState();
}

class _OpenFreeMapViewState extends State<OpenFreeMapView> {
  late final Future<Style> _styleFuture;

  @override
  void initState() {
    super.initState();
    _styleFuture = StyleReader(
      uri: 'https://tiles.openfreemap.org/styles/positron',
    ).read();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Style>(
      future: _styleFuture,
      builder: (BuildContext context, AsyncSnapshot<Style> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            color: AppColors.surfaceVariant,
            alignment: Alignment.center,
            child: SizedBox(
              width: 24.r,
              height: 24.r,
              child: const CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2.5,
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Container(
            color: AppColors.surfaceVariant,
            alignment: Alignment.center,
            padding: EdgeInsets.all(24.w),
            child: Text(
              'Не удалось загрузить карту',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 14.sp,
                color: AppColors.textSecondary,
              ),
            ),
          );
        }
        final Style style = snap.data!;
        return Stack(
          children: <Widget>[
            FlutterMap(
              options: MapOptions(
                initialCenter: widget.initialCenter ??
                    style.center ??
                    const LatLng(55.7558, 37.6173),
                initialZoom: widget.initialZoom,
                maxZoom: 18,
                minZoom: 4,
              ),
              children: <Widget>[
                VectorTileLayer(
                  theme: style.theme,
                  sprites: style.sprites,
                  tileProviders: style.providers,
                ),
                if (widget.markers.isNotEmpty)
                  MarkerLayer(
                    markers: widget.markers
                        .map((OpenFreeMapMarker m) => Marker(
                              point: m.point,
                              width: 40.r,
                              height: 40.r,
                              alignment: Alignment.topCenter,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => widget.onMarkerTap?.call(m.id),
                                child: Icon(
                                  Icons.location_on,
                                  color: AppColors.primary,
                                  size: 36.r,
                                  shadows: const <Shadow>[
                                    Shadow(
                                      color: Color(0x66000000),
                                      blurRadius: 4,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
              ],
            ),
            Positioned(
              right: 4.w,
              bottom: 4.h,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(3.r),
                ),
                child: Text(
                  '© OpenStreetMap © OpenMapTiles',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 9.sp,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

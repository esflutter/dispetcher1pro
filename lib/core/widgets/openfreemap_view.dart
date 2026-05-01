import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';

/// Лимит дискового кэша тайлов OpenFreeMap. 200 МБ — это ~2–3 тысячи
/// уже посещённых тайлов; пакет `vector_map_tiles` сам выкидывает
/// самые старые при превышении (LRU). Хранятся в Application Cache
/// Directory — ОС может его очистить при нехватке места, что нас
/// устраивает (потеря карты не страшна).
const int _kTileCacheMaxSizeBytes = 200 * 1024 * 1024;

/// Сколько хранить тайл, прежде чем перепросить его у OpenFreeMap.
/// 30 дней — компромисс: тайлы OSM обновляются раз в неделю-две, но
/// для маркетплейса техники свежесть карты не критична. Зато заметно
/// меньше трафика при повторных открытиях.
const Duration _kTileCacheTtl = Duration(days: 30);

/// Папка кэша внутри system app cache. Изолированная директория, чтобы
/// случайно не зацепить чужие файлы при ручной чистке.
Future<Directory> _resolveTilesCacheFolder() async {
  final Directory base = await getApplicationCacheDirectory();
  final Directory dir =
      Directory('${base.path}/openfreemap_tiles');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

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
    this.selectedMarkerId,
    this.mapController,
    this.showZoomControls = false,
  });

  final List<OpenFreeMapMarker> markers;
  final LatLng? initialCenter;
  final double initialZoom;
  final ValueChanged<String>? onMarkerTap;

  /// Если передан, маркер с этим id рисуется крупнее и в более насыщенном
  /// цвете — для синхронизации с карточкой заказа в шторке снизу.
  final String? selectedMarkerId;

  /// Внешний контроллер карты — нужен, чтобы родитель мог программно
  /// перемещать камеру (по выбору адреса в поиске, по тапу маркера).
  /// Если не передан — создаётся внутренний.
  final MapController? mapController;

  /// Показывать кнопки `+`/`-` зума справа над атрибуцией.
  final bool showZoomControls;

  @override
  State<OpenFreeMapView> createState() => _OpenFreeMapViewState();
}

class _OpenFreeMapViewState extends State<OpenFreeMapView> {
  late final Future<Style> _styleFuture;
  late final MapController _internalController;

  MapController get _controller =>
      widget.mapController ?? _internalController;

  @override
  void initState() {
    super.initState();
    _internalController = MapController();
    _styleFuture = StyleReader(
      uri: 'https://tiles.openfreemap.org/styles/positron',
    ).read();
  }

  void _zoomBy(double delta) {
    // На случай если карта ещё не отрисовалась (camera недоступен) —
    // защищаемся от исключения, тихо игнорируем.
    try {
      final double current = _controller.camera.zoom;
      final double next = (current + delta).clamp(4.0, 18.0);
      _controller.move(_controller.camera.center, next);
    } catch (_) {/* карта ещё не готова */}
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
              mapController: _controller,
              options: MapOptions(
                // Дефолт — Москва. RU-приложение, чужие страны нам
                // показывать незачем (style.center у OpenFreeMap раньше
                // ронял карту в Дублин/Атлантику).
                initialCenter:
                    widget.initialCenter ?? const LatLng(55.7558, 37.6173),
                initialZoom: widget.initialZoom,
                maxZoom: 18,
                minZoom: 4,
              ),
              children: <Widget>[
                VectorTileLayer(
                  theme: style.theme,
                  sprites: style.sprites,
                  tileProviders: style.providers,
                  // Дисковый кэш: 200 МБ с авто-LRU очисткой старых
                  // тайлов. При повторном открытии экрана / приложения
                  // тайлы тянутся из локального диска, без обращения
                  // в OpenFreeMap (Цюрих) — это убирает «серые
                  // прогалины» при подгрузке.
                  fileCacheMaximumSizeInBytes: _kTileCacheMaxSizeBytes,
                  fileCacheTtl: _kTileCacheTtl,
                  cacheFolder: _resolveTilesCacheFolder,
                ),
                if (widget.markers.isNotEmpty)
                  MarkerLayer(
                    markers: widget.markers
                        .map((OpenFreeMapMarker m) {
                              final bool selected =
                                  widget.selectedMarkerId == m.id;
                              return Marker(
                                point: m.point,
                                width: selected ? 64.r : 48.r,
                                height: selected ? 64.r : 48.r,
                                alignment: Alignment.topCenter,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () =>
                                      widget.onMarkerTap?.call(m.id),
                                  // Контраст между активным и неактивным —
                                  // через цвет (оранжевый vs тёмно-серый)
                                  // и размер (60 vs 42), а также через
                                  // более выраженную тень у активного.
                                  child: Icon(
                                    Icons.location_on,
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.textSecondary
                                            .withValues(alpha: 0.85),
                                    size: selected ? 60.r : 42.r,
                                    shadows: selected
                                        ? const <Shadow>[
                                            Shadow(
                                              color: Color(0x66000000),
                                              blurRadius: 8,
                                              offset: Offset(0, 3),
                                            ),
                                          ]
                                        : const <Shadow>[
                                            Shadow(
                                              color: Color(0x33000000),
                                              blurRadius: 3,
                                              offset: Offset(0, 1),
                                            ),
                                          ],
                                  ),
                                ),
                              );
                            })
                        .toList(),
                  ),
              ],
            ),
            if (widget.showZoomControls)
              Positioned(
                right: 12.w,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _ZoomButton(
                        icon: Icons.add_rounded,
                        onTap: () => _zoomBy(1),
                        topRounded: true,
                      ),
                      Container(
                        width: 44.r,
                        height: 1,
                        color: AppColors.divider,
                      ),
                      _ZoomButton(
                        icon: Icons.remove_rounded,
                        onTap: () => _zoomBy(-1),
                        bottomRounded: true,
                      ),
                    ],
                  ),
                ),
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

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.onTap,
    this.topRounded = false,
    this.bottomRounded = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool topRounded;
  final bool bottomRounded;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.vertical(
      top: topRounded ? Radius.circular(10.r) : Radius.zero,
      bottom: bottomRounded ? Radius.circular(10.r) : Radius.zero,
    );
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: radius,
      elevation: 2,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: SizedBox(
          width: 44.r,
          height: 44.r,
          child: Icon(icon, size: 24.r, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

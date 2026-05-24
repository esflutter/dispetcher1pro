import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'package:dispatcher_1/core/location_permission.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';

/// Скрываем государственные границы (тонкие линии между странами и
/// регионами) — для приложения они визуальный шум, юзеры смотрят
/// на маркеры заказов. В positron слои-границы имеют id вида
/// `boundary_2/3/disputed` и в JSON стиле живут в `source-layer:
/// "boundary"`. Фильтруем И по id, И по `tileSource` — оба нужны:
/// у некоторых слоёв id может быть префиксован ThemeReader'ом, и
/// строковое совпадение по id не всегда срабатывает.
vtr.Theme _hideAdminBoundaries(vtr.Theme src) {
  return vtr.Theme(
    id: src.id,
    version: src.version,
    layers: src.layers.where((vtr.ThemeLayer l) {
      final String id = l.id.toLowerCase();
      final String? source = l.tileSource?.toLowerCase();
      if (source == 'boundary') return false;
      if (id.contains('boundary')) return false;
      if (id.contains('admin')) return false;
      return true;
    }).toList(growable: false),
  );
}

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

/// Плавный переход камеры к точке/зуму вместо моментального `move()`.
///
/// flutter_map не умеет анимировать камеру сам — стандартное
/// `MapController.move()` ставит камеру на новое значение в один кадр.
/// При свайпе между маркерами это выглядит как «прыжок», и пользователь
/// теряет ориентацию: какой маркер был, какой стал.
///
/// Помогает классический паттерн: `AnimationController` тикает 0..1
/// за 400 мс с `easeInOut`, на каждом тике линейно интерполируем
/// lat/lng/zoom между стартовой и целевой точкой и зовём `move()`.
/// Контроллер диспозим в `addStatusListener` по `completed`, чтобы не
/// течь.
extension AnimatedMapMove on MapController {
  void animatedMove(
    LatLng dest,
    double destZoom, {
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 400),
  }) {
    final LatLng startCenter;
    final double startZoom;
    try {
      startCenter = camera.center;
      startZoom = camera.zoom;
    } catch (_) {
      // Камера ещё не готова (карта не отрисована) — пропускаем
      // анимацию, иначе словим NoCameraException на первом кадре.
      return;
    }
    final AnimationController ctrl =
        AnimationController(duration: duration, vsync: vsync);
    final CurvedAnimation anim =
        CurvedAnimation(parent: ctrl, curve: Curves.easeInOut);
    ctrl.addListener(() {
      final double t = anim.value;
      move(
        LatLng(
          startCenter.latitude +
              (dest.latitude - startCenter.latitude) * t,
          startCenter.longitude +
              (dest.longitude - startCenter.longitude) * t,
        ),
        startZoom + (destZoom - startZoom) * t,
      );
    });
    anim.addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
        ctrl.dispose();
      }
    });
    ctrl.forward();
  }
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
    this.showMyLocation = false,
    this.onMyLocationTap,
  });

  final List<OpenFreeMapMarker> markers;
  final LatLng? initialCenter;
  final double initialZoom;
  final ValueChanged<String>? onMarkerTap;

  /// Колбэк после успешного тапа кнопки «моё местоположение» — нужен
  /// родителю, чтобы скрыть нижнюю карточку выбранного заказа: при
  /// центрировании на пользователя фокус смещается на него самого, и
  /// карточка с чужим заказом отвлекает.
  final VoidCallback? onMyLocationTap;

  /// Если передан, маркер с этим id рисуется крупнее и в более насыщенном
  /// цвете — для синхронизации с карточкой заказа в шторке снизу.
  final String? selectedMarkerId;

  /// Внешний контроллер карты — нужен, чтобы родитель мог программно
  /// перемещать камеру (по выбору адреса в поиске, по тапу маркера).
  /// Если не передан — создаётся внутренний.
  final MapController? mapController;

  /// Показывать кнопки `+`/`-` зума справа над атрибуцией.
  final bool showZoomControls;

  /// Показывать синюю точку «моё местоположение» (в стиле Google Maps)
  /// и кнопку под зумом, которая центрирует карту на ней. Включается
  /// только на тех экранах, где это уместно — каталог заказов на карте.
  /// Если у пользователя не выдано разрешение на геолокацию, точка
  /// просто не отрисовывается, кнопка остаётся — тап по ней
  /// инициирует запрос разрешения.
  final bool showMyLocation;

  @override
  State<OpenFreeMapView> createState() => _OpenFreeMapViewState();
}

class _OpenFreeMapViewState extends State<OpenFreeMapView>
    with TickerProviderStateMixin {
  late final Future<Style> _styleFuture;
  late final MapController _internalController;

  /// Текущее местоположение пользователя — обновляется стримом
  /// `Geolocator.getPositionStream`. `null`, пока не пришёл первый
  /// fix или если разрешение не выдано.
  LatLng? _myLocation;
  StreamSubscription<Position>? _positionSub;

  MapController get _controller =>
      widget.mapController ?? _internalController;

  @override
  void initState() {
    super.initState();
    _internalController = MapController();
    _styleFuture = StyleReader(
      uri: 'https://tiles.openfreemap.org/styles/positron',
    ).read();
    if (widget.showMyLocation) {
      _bootstrapMyLocation();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    // Диспозим только внутренний контроллер. Если он передан извне
    // (widget.mapController != null), родитель сам отвечает за dispose.
    if (widget.mapController == null) {
      _internalController.dispose();
    }
    super.dispose();
  }

  /// Если разрешение на геолокацию уже выдано — сразу подписываемся
  /// на стрим. Если нет — ничего не делаем; пользователь тапнет
  /// кнопку «моё местоположение» и тогда мы запросим permission.
  Future<void> _bootstrapMyLocation() async {
    final bool serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) return;
    final LocationPermission perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.whileInUse &&
        perm != LocationPermission.always) {
      return;
    }
    _startPositionStream();
  }

  void _startPositionStream() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        // 10 м точности достаточно для отображения «синей точки» и
        // не сажает батарею; обновления чаще раза в 2-3 сек не нужны.
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position p) {
      if (!mounted) return;
      setState(() => _myLocation = LatLng(p.latitude, p.longitude));
    }, onError: (_) {/* silent — нет сети, GPS недоступен */});
  }

  /// Тап по кнопке «моё местоположение». Если permission ещё нет —
  /// запрашиваем; при успехе стартуем стрим и центрируем карту на
  /// первом fix'е (или на текущем, если он уже есть).
  Future<void> _onMyLocationTap() async {
    final bool granted = await ensureLocationPermission();
    if (!granted || !mounted) return;
    if (_positionSub == null) _startPositionStream();
    // Сообщаем родителю до движения камеры — он спрячет карточку
    // выбранного заказа, чтобы анимация перелёта не дёргала её
    // слайдер. Если родитель не передал колбэк, тихо пропускаем.
    widget.onMyLocationTap?.call();
    // Если fix уже пришёл — центрируем сразу. Иначе подождём пару
    // секунд первый event из стрима.
    LatLng? target = _myLocation;
    target ??= await _waitForFix();
    if (target == null || !mounted) return;
    try {
      _controller.animatedMove(target, 15, vsync: this);
    } catch (_) {/* карта не готова */}
  }

  /// Ждём первый fix до 4 секунд. Используется при первом тапе кнопки,
  /// когда стрим только что запустился и `_myLocation` ещё пуст.
  Future<LatLng?> _waitForFix() async {
    final DateTime deadline =
        DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(deadline)) {
      if (_myLocation != null) return _myLocation;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return _myLocation;
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
                // Отключаем поворот карты двупальцевым twist-жестом.
                // Юзеры случайно крутили карту во время pinch-zoom'а,
                // маркеры оказывались под углом, пилюли «север сверху»
                // нет — выглядело как баг. Остальные жесты
                // (drag, pinchZoom, doubleTap, fling) сохранены.
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: <Widget>[
                VectorTileLayer(
                  theme: _hideAdminBoundaries(style.theme),
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
                    // Ключ зависит от id всех маркеров. Без него
                    // `flutter_map` переиспользует element и не обновляет
                    // отрисованный набор Marker'ов при смене widget.markers
                    // — на табе «На карте» это приводило к тому, что
                    // после применения фильтра маркеры на карте
                    // оставались прежними, хотя orders в state уже
                    // отфильтрованы (видно при переключении на «Списком»).
                    key: ValueKey<String>(
                      widget.markers
                          .map((OpenFreeMapMarker m) => m.id)
                          .join(','),
                    ),
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
                // Синяя точка «моё местоположение» в стиле Google Maps:
                // внутренний насыщенно-синий круг, белая обводка и
                // мягкая полупрозрачная тень-ореол. Рисуется ПОСЛЕ
                // маркеров заказов, чтобы оставаться сверху.
                if (widget.showMyLocation && _myLocation != null)
                  MarkerLayer(
                    markers: <Marker>[
                      Marker(
                        point: _myLocation!,
                        width: 28.r,
                        height: 28.r,
                        alignment: Alignment.center,
                        child: const _MyLocationDot(),
                      ),
                    ],
                  ),
              ],
            ),
            if (widget.showZoomControls || widget.showMyLocation)
              Positioned(
                right: 12.w,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (widget.showZoomControls) ...<Widget>[
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
                      if (widget.showMyLocation) ...<Widget>[
                        SizedBox(height: 8.h),
                        _ZoomButton(
                          icon: Icons.my_location_rounded,
                          onTap: _onMyLocationTap,
                          topRounded: true,
                          bottomRounded: true,
                        ),
                      ],
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

/// Синяя точка «моё местоположение» в стиле Google Maps:
///   - внешний светло-синий ореол (полупрозрачный),
///   - белая обводка,
///   - внутренний насыщенно-синий круг с тенью.
/// Размер маркера фиксирован в Marker.width/height (28.r) — внутри
/// ореол занимает всю площадь, точка по центру 14.r.
class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    const Color blue = Color(0xFF4285F4); // Google Maps location-blue
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: blue.withValues(alpha: 0.18),
          ),
        ),
        Container(
          width: 16.r,
          height: 16.r,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        Container(
          width: 12.r,
          height: 12.r,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: blue,
          ),
        ),
      ],
    );
  }
}

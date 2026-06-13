import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'package:dispatcher_1/core/config/env.dart';
import 'package:dispatcher_1/core/location_permission.dart';
import 'package:dispatcher_1/core/settings/settings_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';

/// Скрываем государственные границы (тонкие линии между странами и
/// регионами) — для приложения они визуальный шум, юзеры смотрят
/// на маркеры заказов. В Mapbox light-v11 слои-границы имеют id вида
/// `admin-0-boundary` / `admin-1-boundary` (source-layer "admin"); в
/// запасном positron — `boundary_2/3/disputed` (source-layer
/// "boundary"). Фильтруем И по id, И по `tileSource` — оба нужны:
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

/// Лимит дискового кэша тайлов карты. 200 МБ — это ~2–3 тысячи
/// уже посещённых тайлов; пакет `vector_map_tiles` сам выкидывает
/// самые старые при превышении (LRU). Хранятся в Application Cache
/// Directory — ОС может его очистить при нехватке места, что нас
/// устраивает (потеря карты не страшна).
const int _kTileCacheMaxSizeBytes = 200 * 1024 * 1024;

/// Сколько хранить тайл, прежде чем перепросить его у тайл-сервера.
/// 30 дней — компромисс: тайлы обновляются раз в неделю-две, но
/// для маркетплейса техники свежесть карты не критична. Зато заметно
/// меньше трафика при повторных открытиях.
const Duration _kTileCacheTtl = Duration(days: 30);

/// Фактический источник тайлов. Выбирается в РАНТАЙМЕ (см. _resolveStyle):
/// Mapbox при токене сборки и включённой настройке, иначе — OpenFreeMap.
enum _TileProvider { mapbox, openFreeMap }

/// Папка кэша внутри system app cache. У каждого источника СВОЯ папка
/// (mapbox_tiles / openfreemap_tiles): схемы тайлов разные, смешивать
/// кэш нельзя, а при переключении источника старый кэш не мешает.
Future<Directory> _resolveTilesCacheFolder(_TileProvider provider) async {
  final Directory base = await getApplicationCacheDirectory();
  final Directory dir = Directory(
      '${base.path}/${provider == _TileProvider.mapbox ? 'mapbox_tiles' : 'openfreemap_tiles'}');
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
/// Активная анимация камеры для каждого [MapController]. Храним, чтобы:
///   1) новая анимация отменяла предыдущую (нет накопления контроллеров);
///   2) экран мог отменить её в `dispose()` — иначе `AnimationController`
///      с vsync уже мёртвого State продолжает жить, течёт и роняет ассерт
///      «Ticker disposed with an active Ticker» (видно при смене фильтра/
///      реалтайм-обновлении ленты во время 400-мс анимации свайпа).
final Map<MapController, AnimationController> _activeMapAnimations =
    <MapController, AnimationController>{};

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
    // Отменяем предыдущую анимацию этого контроллера, если ещё идёт.
    _activeMapAnimations.remove(this)?.dispose();
    final AnimationController ctrl =
        AnimationController(duration: duration, vsync: vsync);
    _activeMapAnimations[this] = ctrl;
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
        _activeMapAnimations.remove(this);
        ctrl.dispose();
      }
    });
    ctrl.forward();
  }

  /// Отменить активную анимацию камеры и освободить её контроллер.
  /// ОБЯЗАТЕЛЬНО звать в `dispose()` экрана ПЕРЕД `dispose()` самого
  /// [MapController] — иначе тикер анимации переживает State.
  void cancelAnimatedMove() {
    _activeMapAnimations.remove(this)?.dispose();
  }
}

/// Карта каталога. Основной источник — векторные тайлы Mapbox (стиль
/// light-v11, токен приходит при сборке через --dart-define=MAPBOX_TOKEN);
/// без токена — запасной бесплатный OpenFreeMap, чтобы dev-сборка
/// работала без ключей. Историческое имя класса/файла (OpenFreeMapView)
/// сохранено — внешний контракт не менялся, см. комментарий к
/// [OpenFreeMapMarker].
///
/// Атрибуция источника обязательна по лицензии и рисуется в правом
/// нижнем углу («© Mapbox © OpenStreetMap» / «© OpenStreetMap
/// © OpenMapTiles» соответственно).
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
  // Не final: при ошибке загрузки кнопка «Повторить» пересоздаёт future.
  late Future<Style> _styleFuture;
  // Запасной контроллер создаём ТОЛЬКО когда внешний не передан — иначе он
  // зря выделялся при каждом построении карты с внешним контроллером и не
  // освобождался (dispose трогал его лишь при отсутствии внешнего).
  MapController? _internalController;

  /// Текущее местоположение пользователя — обновляется стримом
  /// `Geolocator.getPositionStream`. `null`, пока не пришёл первый
  /// fix или если разрешение не выдано.
  LatLng? _myLocation;
  StreamSubscription<Position>? _positionSub;

  // Тема стиля без админ-границ: фильтруем 100+ слоёв ОДИН раз и кэшируем.
  // Иначе _hideAdminBoundaries гонялся в build на каждый GPS-апдейт синей
  // точки (поток геолокации дёргает setState каждые пару секунд при движении).
  vtr.Theme? _filteredTheme;

  /// Тема с РУССКИМИ подписями (если удалось собрать) — приоритетнее
  /// style.theme. null = русификация не удалась, рисуем как есть.
  vtr.Theme? _ruTheme;

  /// URL описания стиля (для повторного скачивания при русификации).
  String? _styleJsonUrl;

  /// Фактически выбранный источник тайлов. Выставляется в _resolveStyle ДО
  /// завершения _styleFuture, поэтому к моменту build (FutureBuilder done)
  /// значение всегда актуально — от него зависят кэш-папка и атрибуция.
  _TileProvider _provider = _TileProvider.openFreeMap;

  MapController get _controller =>
      widget.mapController ?? _internalController!;

  // -----------------------------------------------------------------
  // Каждый заказ — отдельный пин, без кластеризации. Круги-кластеры
  // с числом пробовали: при pinch-zoom перегруппировка давала
  // мельтешение (пин ↔ круг), а плотность заказов спецтехники низкая —
  // это не Airbnb с десятью объектами в одном доме. Простые пины
  // стабильны: их позиции не зависят от зума вообще.
  // -----------------------------------------------------------------

  List<Marker> _plainMarkers() {
    OpenFreeMapMarker? selected;
    final List<Marker> out = <Marker>[];
    for (final OpenFreeMapMarker m in widget.markers) {
      if (m.id == widget.selectedMarkerId) {
        selected = m;
        continue;
      }
      out.add(_singleMarker(m, selected: false));
    }
    // Выбранный — последним, чтобы рисовался поверх остальных.
    if (selected != null) out.add(_singleMarker(selected, selected: true));
    return out;
  }

  Marker _singleMarker(OpenFreeMapMarker m, {required bool selected}) {
    return Marker(
      point: m.point,
      width: selected ? 64.r : 48.r,
      height: selected ? 64.r : 48.r,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onMarkerTap?.call(m.id),
        // Контраст между активным и неактивным — через цвет (оранжевый vs
        // тёмно-серый) и размер (60 vs 42), плюс выраженная тень у активного.
        child: Icon(
          Icons.location_on,
          color: selected
              ? AppColors.primary
              : AppColors.textSecondary.withValues(alpha: 0.85),
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
  }

  @override
  void initState() {
    super.initState();
    if (widget.mapController == null) {
      _internalController = MapController();
    }
    _styleFuture = _resolveStyle();
    if (widget.showMyLocation) {
      _bootstrapMyLocation();
    }
  }

  /// Выбор источника карт и загрузка стиля. Порядок:
  ///   1. Mapbox (стиль light-v11, прямой аналог positron). Токен берётся
  ///      С СЕРВЕРА (настройка map.mapbox_token — в APK его нет, а при
  ///      злоупотреблении токен ротируется в админке без пересборки);
  ///      запасной канал — токен из сборки (--dart-define=MAPBOX_TOKEN).
  ///      Админ-настройка map.provider='openfreemap' — аварийный рубильник:
  ///      выключает Mapbox у всех пользователей без пересборки.
  ///   2. При ЛЮБОЙ ошибке загрузки Mapbox-стиля (исчерпана квота, токен
  ///      отозван, сервис недоступен) — тихий фолбэк на OpenFreeMap вместо
  ///      «Не удалось загрузить карту».
  /// Пакет сам разворачивает mapbox:// в style/tiles/sprites API-адреса.
  Future<Style> _resolveStyle() async {
    String token = '';
    bool providerOff = false;
    try {
      token = await SettingsService.instance.mapboxMapToken();
      providerOff =
          await SettingsService.instance.mapProvider() == 'openfreemap';
    } catch (_) {/* настройки недоступны — работаем по данным сборки */}
    if (token.isEmpty) token = Env.mapboxToken;
    if (token.isNotEmpty && !providerOff) {
      try {
        final Style style = await StyleReader(
          uri: 'mapbox://styles/mapbox/light-v11?access_token=$token',
          apiKey: token,
        ).read();
        _provider = _TileProvider.mapbox;
        _styleJsonUrl =
            'https://api.mapbox.com/styles/v1/mapbox/light-v11?access_token=$token';
        await _tryLoadRussianTheme();
        return style;
      } catch (_) {/* Mapbox недоступен — падаем на запасной источник */}
    }
    _provider = _TileProvider.openFreeMap;
    final Style style = await StyleReader(
      uri: 'https://tiles.openfreemap.org/styles/positron',
    ).read();
    _styleJsonUrl = 'https://tiles.openfreemap.org/styles/positron';
    await _tryLoadRussianTheme();
    return style;
  }

  /// Русские подписи на карте. Стили из коробки подписывают города
  /// по-английски (Mapbox: поле name_en) или латиницей (positron:
  /// name:latin) — для РФ-приложения это выглядело чужим. Скачиваем
  /// описание стиля ещё раз, заменяем поля имён на русские (name_ru с
  /// фолбэком на местное название) и собираем тему заново. Любая ошибка —
  /// тихо остаёмся на исходной теме: карта важнее языка подписей.
  Future<void> _tryLoadRussianTheme() async {
    final String? url = _styleJsonUrl;
    if (url == null) return;
    try {
      final http.Response resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      String body = utf8.decode(resp.bodyBytes);
      // Mapbox: ["get","name_en"] → ["get","name_ru"] (coalesce с "name"
      // в стиле уже есть — без русского имени останется местное).
      body = body.replaceAll('"name_en"', '"name_ru"');
      // positron: шаблоны "{name:latin}…" → "{name}" (местное название;
      // в России это русский). Заодно выражения ["get","name:latin"].
      body = body.replaceAll('{name:latin}', '{name}');
      body = body.replaceAll('"name:latin"', '"name"');
      final Map<String, dynamic> json =
          jsonDecode(body) as Map<String, dynamic>;
      _ruTheme = vtr.ThemeReader().read(json);
    } catch (_) {/* не вышло — остаёмся на теме из StyleReader */}
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    // Отменяем активную анимацию камеры («лети к моей точке») до dispose.
    _controller.cancelAnimatedMove();
    // Внутренний контроллер создаётся только при отсутствии внешнего —
    // здесь диспозим его, если он есть. Внешний диспозит родитель.
    _internalController?.dispose();
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
        // Для «синей точки» хватает средней точности (~50-100 м) и шага
        // 15 м: точка визуально та же, а GPS-чип работает заметно мягче —
        // экран карты перестаёт ощутимо греть телефон и есть батарею.
        accuracy: LocationAccuracy.medium,
        distanceFilter: 15,
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
      // Плавный подлёт вместо мгновенного move(): резкая смена зума
      // воспринималась как «дёрганье». Повторные тапы не копятся —
      // animatedMove сам отменяет предыдущую анимацию.
      _controller.animatedMove(
        _controller.camera.center,
        next,
        vsync: this,
        duration: const Duration(milliseconds: 250),
      );
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
          // Раньше это был тупик до перезахода на экран: открыл карту без
          // сети — и всё. Кнопка перезапускает загрузку стиля на месте.
          return Container(
            color: AppColors.surfaceVariant,
            alignment: Alignment.center,
            padding: EdgeInsets.all(24.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Не удалось загрузить карту',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 12.h),
                GestureDetector(
                  onTap: () => setState(() {
                    _filteredTheme = null;
                    _ruTheme = null;
                    _styleJsonUrl = null;
                    _styleFuture = _resolveStyle();
                  }),
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Text(
                      'Повторить',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final Style style = snap.data!;
        // Стиль приходит из _styleFuture один раз и по слоям не меняется —
        // фильтруем его единожды (??=), а не на каждую перерисовку карты.
        _filteredTheme ??= _hideAdminBoundaries(_ruTheme ?? style.theme);
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
                // Не даём центру карты улететь свайпами в океан: RU-сервис,
                // заказы только в России. Ограничиваем ЦЕНТР (containCenter,
                // не contain): мягко, без конфликтов с минимальным зумом, а
                // у краёв рамки соседние страны остаются видны. Бонус —
                // меньше бесполезных тайлов из квоты Mapbox.
                cameraConstraint: CameraConstraint.containCenter(
                  bounds: LatLngBounds(
                    const LatLng(40.0, 18.0),   // юго-запад (Кавказ/Калининград)
                    const LatLng(82.5, 180.0),  // северо-восток (Арктика/Чукотка)
                  ),
                ),
              ),
              children: <Widget>[
                VectorTileLayer(
                  theme: _filteredTheme!,
                  sprites: style.sprites,
                  tileProviders: style.providers,
                  // Дисковый кэш: 200 МБ с авто-LRU очисткой старых
                  // тайлов. При повторном открытии экрана / приложения
                  // тайлы тянутся из локального диска, без обращения
                  // к тайл-серверу — это убирает «серые прогалины»
                  // при подгрузке.
                  fileCacheMaximumSizeInBytes: _kTileCacheMaxSizeBytes,
                  fileCacheTtl: _kTileCacheTtl,
                  cacheFolder: () => _resolveTilesCacheFolder(_provider),
                ),
                if (widget.markers.isNotEmpty)
                  MarkerLayer(
                    // Ключ по набору id: без него flutter_map переиспользовал
                    // element при смене фильтра, и маркеры «застревали».
                    // От камеры слой больше не зависит — при зуме ничего
                    // не пересобирается.
                    key: ValueKey<String>(
                      widget.markers
                          .map((OpenFreeMapMarker m) => m.id)
                          .join(','),
                    ),
                    markers: _plainMarkers(),
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
                  // Атрибуция обязательна по лицензии источника тайлов.
                  _provider == _TileProvider.mapbox
                      ? '© Mapbox © OpenStreetMap'
                      : '© OpenStreetMap © OpenMapTiles',
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

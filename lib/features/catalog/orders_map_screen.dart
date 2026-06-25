import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:dispatcher_1/core/catalog/catalog_service.dart';
import 'package:dispatcher_1/core/catalog/format.dart';
import 'package:dispatcher_1/core/catalog/models.dart';
import 'package:dispatcher_1/core/dadata/dadata_service.dart';
import 'package:dispatcher_1/core/executor_card/executor_card_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/mock_coords.dart';
import 'package:dispatcher_1/core/widgets/openfreemap_view.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/catalog/order_detail_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/applied_filter_chips.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';

/// Один маркер на карте: id заказа + опциональные координаты из БД.
/// Если координат нет (старые заказы созданные до подключения DaData),
/// используется детерминированный мок-разлёт вокруг центра Москвы.
class OrderMarkerData {
  const OrderMarkerData({required this.id, this.lat, this.lon});
  final String id;
  final double? lat;
  final double? lon;
}

/// Карта со списком заказов в виде маркеров. Берёт реальные координаты
/// из `orders.latitude`/`orders.longitude` (заполнены при создании заказа
/// через DaData Suggest API). Если координат нет — fallback на детермини-
/// рованный мок (`mockMoscowCoordsForId`), чтобы старые заказы тоже что-то
/// показывали и UI не выглядел сломанно.
class OrdersMapScreen extends StatelessWidget {
  const OrdersMapScreen({
    super.key,
    this.markers = const <OrderMarkerData>[],
    this.initialCenter,
    this.initialZoom = 11,
    this.onMarkerTap,
    this.selectedMarkerId,
    this.mapController,
    this.showZoomControls = false,
    this.showMyLocation = false,
    this.onMyLocationTap,
  });

  final List<OrderMarkerData> markers;
  final LatLng? initialCenter;
  final double initialZoom;
  final ValueChanged<String>? onMarkerTap;
  final String? selectedMarkerId;
  final MapController? mapController;
  final bool showZoomControls;
  final bool showMyLocation;
  final VoidCallback? onMyLocationTap;

  @override
  Widget build(BuildContext context) {
    final List<OpenFreeMapMarker> mapMarkers = markers
        .map((OrderMarkerData m) => OpenFreeMapMarker(
              id: m.id,
              point: (m.lat != null && m.lon != null)
                  ? LatLng(m.lat!, m.lon!)
                  : mockMoscowCoordsForId(m.id),
            ))
        .toList();
    return OpenFreeMapView(
      markers: mapMarkers,
      initialCenter: initialCenter,
      initialZoom: initialZoom,
      onMarkerTap: onMarkerTap,
      selectedMarkerId: selectedMarkerId,
      mapController: mapController,
      showZoomControls: showZoomControls,
      showMyLocation: showMyLocation,
      onMyLocationTap: onMyLocationTap,
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

class _OrdersMapFullScreenState extends State<OrdersMapFullScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  final MapController _mapController = MapController();
  String _query = '';
  bool _addressSelected = false;
  int _current = 0;
  int _direction = 1;

  /// Видимость нижней карточки выбранного заказа. По умолчанию `false` —
  /// при первом открытии экрана фокус на пользователе/карте; карточка
  /// появляется только когда юзер ткнул в маркер. Тап по кнопке «моё
  /// местоположение» снова прячет карточку.
  bool _cardVisible = false;

  /// Последний центр и зум карты, на котором юзер вышел с экрана.
  /// Статика — живёт в рамках одной сессии приложения. При повторном
  /// открытии экрана используется как fallback, если геолокация
  /// недоступна (см. [_resolveInitialCenter]).
  static LatLng? _lastViewedCenter;
  static double? _lastViewedZoom;

  /// Центр карты при первом рендере. Решается асинхронно в initState:
  /// сначала пробуем геолокацию пользователя, потом — координаты
  /// последнего опубликованного заказа, иначе оставляем null
  /// (карта подставит дефолтную Москву).
  LatLng? _initialCenter;
  double _initialZoom = 11;
  bool _initialCenterReady = false;

  /// Все опубликованные заказы из БД на момент открытия карты. Фильтр
  /// `[AppliedFilter.equipment]` применяется на клиенте в [_visibleOrders],
  /// поэтому повторный запрос при смене фильтра не нужен.
  late Future<List<_MapOrder>> _ordersFuture;

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
  late final double? _savedAddressLat;
  late final double? _savedAddressLng;

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
    _savedAddressLat = AppliedFilter.addressLat;
    _savedAddressLng = AppliedFilter.addressLng;

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
    AppliedFilter.addressLat = null;
    AppliedFilter.addressLng = null;

    AppliedFilter.revision.addListener(_onFilterChanged);
    _ordersFuture = _fetchOrders();
    // Откладываем разрешение центра карты до конца текущего фрейма,
    // чтобы splash-кадр (CircularProgressIndicator) успел отрисоваться,
    // и пользователь не видел замороженного экрана при медленном
    // ответе геолокации.
    // ignore: discarded_futures
    _resolveInitialCenter();
  }

  /// Грубый bbox РФ — нужен, чтобы отсеять «бутафорские» координаты
  /// эмулятора (Mountain View, 37 N / -122 W) и реальную локацию,
  /// если пользователь сейчас за пределами страны (отпуск, Турция и т.д.).
  /// В этих случаях правильнее показать ленту заказов в РФ, а не пустой
  /// океан или чужой город.
  static bool _looksLikeRussia(double lat, double lon) {
    return lat >= 41 && lat <= 82 && lon >= 19 && lon <= 180;
  }

  /// Дефолтный zoom для первой отрисовки карты — городской квартал
  /// видно домами, чтобы юзеру не приходилось сразу же приближать.
  static const double _kDefaultZoom = 14;

  /// Определяем точку для первого рендера карты — «по-умному», чтобы
  /// исполнителю сразу были видны заказы, а не пустой город:
  ///   1. GPS пользователя — но ТОЛЬКО если рядом (≤150 км) есть заказы.
  ///      Иначе (например, исполнитель в Москве, а заказы в Новосибирске)
  ///      открылась бы пустая карта. zoom 13.
  ///   2. Последний просмотренный вид (та же сессия приложения).
  ///   3. Город с наибольшим числом заказов (сейчас Новосибирск; при выходе
  ///      в другие города центр сам сместится туда, где заказов больше). zoom 11.
  ///   4. Если заказов нет вовсе — GPS пользователя, иначе адрес из карточки.
  ///   5. Центр РФ — самый последний fallback.
  Future<void> _resolveInitialCenter() async {
    double zoom = _kDefaultZoom;

    List<_MapOrder> orders = const <_MapOrder>[];
    try {
      orders = await _ordersFuture;
    } catch (_) {/* карта переживёт пустой список */}
    final LatLng? ordersCenter = _densestOrdersCenter(orders);
    final LatLng? gps = await _tryGps();

    LatLng? center;
    // 1. GPS — только когда рядом действительно есть заказы.
    if (gps != null && _ordersNear(gps, orders)) {
      center = gps;
      zoom = 13;
    }
    // 2. Продолжаем с последнего вида в этой сессии.
    if (center == null && _lastViewedCenter != null) {
      center = _lastViewedCenter;
      zoom = _lastViewedZoom ?? _kDefaultZoom;
    }
    // 3. Главный умный дефолт: город, где больше всего заказов.
    if (center == null && ordersCenter != null) {
      center = ordersCenter;
      zoom = 11;
    }
    // 4. Заказов нет совсем — хотя бы GPS пользователя…
    if (center == null && gps != null) {
      center = gps;
      zoom = 13;
    }
    // …или «домашний» город из карточки исполнителя.
    if (center == null) {
      try {
        final MyExecutorCard? card =
            await ExecutorCardService.instance.loadMine();
        final double? lat = card?.locationLat;
        final double? lng = card?.locationLng;
        if (lat != null && lng != null && _looksLikeRussia(lat, lng)) {
          center = LatLng(lat, lng);
        }
      } catch (_) {/* ignore */}
    }
    // 5. Совсем ничего (нет заказов, GPS и города в карточке) — центр
    // Новосибирска, города запуска. Не Москва: запуск с НСО.
    center ??= const LatLng(55.0084, 82.9357);
    if (!mounted) return;
    setState(() {
      _initialCenter = center;
      _initialZoom = zoom;
      _initialCenterReady = true;
    });
  }

  /// GPS пользователя для центрирования. Сначала last-known (мгновенно и
  /// обычно достаточно точно), затем свежая позиция с щадящим таймаутом —
  /// раньше короткий 4-сек timeLimit часто не успевал на холодный фикс, и
  /// карта падала в дефолт (Москву) даже при включённом GPS. Диалог
  /// разрешения тут НЕ показываем. null — если нет разрешения/служб/фикса
  /// или позиция вне РФ.
  Future<LatLng?> _tryGps() async {
    try {
      final LocationPermission permission = await Geolocator.checkPermission();
      final bool granted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!granted) return null;
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (_looksLikeRussia(pos.latitude, pos.longitude)) {
        return LatLng(pos.latitude, pos.longitude);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[OrdersMap] geolocation failed: $e');
    }
    return null;
  }

  /// Есть ли заказ с координатами в радиусе ~150 км от точки.
  static bool _ordersNear(LatLng p, List<_MapOrder> orders) {
    const Distance d = Distance();
    for (final _MapOrder o in orders) {
      final double? lat = o.latitude;
      final double? lng = o.longitude;
      if (lat == null || lng == null) continue;
      if (d.as(LengthUnit.Kilometer, p, LatLng(lat, lng)) <= 150) {
        return true;
      }
    }
    return false;
  }

  /// Центр самого «густого» скопления заказов — город, где их больше всего.
  /// Группируем по ячейкам ~0.5° (≈ размер города), берём самую населённую,
  /// возвращаем центроид её заказов. Заказы без координат игнорируем (чтобы
  /// они не утягивали центр в дефолтную Москву).
  static LatLng? _densestOrdersCenter(List<_MapOrder> orders) {
    final Map<String, List<LatLng>> cells = <String, List<LatLng>>{};
    for (final _MapOrder o in orders) {
      final double? lat = o.latitude;
      final double? lng = o.longitude;
      if (lat == null || lng == null) continue;
      if (!_looksLikeRussia(lat, lng)) continue;
      final String key = '${(lat * 2).round()}:${(lng * 2).round()}';
      (cells[key] ??= <LatLng>[]).add(LatLng(lat, lng));
    }
    if (cells.isEmpty) return null;
    List<LatLng>? best;
    for (final List<LatLng> list in cells.values) {
      if (best == null || list.length > best.length) best = list;
    }
    double lat = 0, lng = 0;
    for (final LatLng p in best!) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / best.length, lng / best.length);
  }

  /// Тап по маркеру — синхронизируем нижнюю карточку.
  void _onMarkerTap(String id, List<_MapOrder> orders) {
    if (orders.isEmpty) return;
    final int idx = orders.indexWhere((_MapOrder o) => o.id == id);
    if (idx < 0) return;
    setState(() {
      _direction = idx > _current ? 1 : -1;
      _current = idx;
      // Любой тап по маркеру → показать карточку. Если она уже была
      // показана, обновится только индекс выбранного заказа (через
      // `_current`).
      _cardVisible = true;
    });
    _centerOnOrder(orders[idx]);
  }

  /// Двигает камеру к маркеру заказа без изменения zoom. Если у заказа
  /// нет координат в БД (старые записи) — не трогаем камеру: маркер
  /// в этом случае рендерится по детерминированному моку, перенос
  /// туда был бы дезориентирующим.
  void _centerOnOrder(_MapOrder o) {
    if (o.latitude == null || o.longitude == null) return;
    try {
      final double currentZoom = _mapController.camera.zoom;
      _mapController.animatedMove(
        LatLng(o.latitude!, o.longitude!),
        currentZoom,
        vsync: this,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[OrdersMap] _centerOnOrder failed: $e');
    }
  }

  /// Обработчик выбора подсказки в строке поиска. Если у адреса есть
  /// координаты — двигаем камеру и зум. Без координат — просто
  /// заполняем строку (редкий кейс DaData без geo).
  void _onAddressSelected(DadataAddress addr) {
    _searchCtrl.text = addr.value;
    setState(() {
      _query = addr.value;
      _addressSelected = true;
    });
    FocusScope.of(context).unfocus();
    if (addr.lat != null && addr.lon != null) {
      try {
        _mapController.animatedMove(
          LatLng(addr.lat!, addr.lon!),
          14,
          vsync: this,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[OrdersMap] mapController.move failed: $e');
      }
    }
  }

  Future<List<_MapOrder>> _fetchOrders() async {
    final bool radiusActive = AppliedFilter.radiusKm != null &&
        AppliedFilter.addressLat != null &&
        AppliedFilter.addressLng != null;
    final List<OrderListItem> orders =
        await CatalogService.instance.listPublishedOrders(
      machineryTitles: AppliedFilter.equipment,
      categoryTitles: AppliedFilter.categories,
      dateFrom: AppliedFilter.dateFrom,
      // «Точная дата» = строго один день (верхняя граница = тот же день), как в
      // списке. Раньше тут было null — карта снимала верхнюю границу и
      // показывала все заказы начиная с выбранного дня, не совпадая со списком.
      dateTo: AppliedFilter.exactDate
          ? AppliedFilter.dateFrom
          : AppliedFilter.dateTo,
      addressContains: radiusActive ? null : AppliedFilter.address,
      wholeDay: AppliedFilter.wholeDay ? true : null,
      originLat: radiusActive ? AppliedFilter.addressLat : null,
      originLng: radiusActive ? AppliedFilter.addressLng : null,
      radiusKm: radiusActive ? AppliedFilter.radiusKm : null,
    );
    return orders
        .map((OrderListItem o) => _MapOrder(
              id: o.id,
              equipment:
                  o.machineryTitles.isNotEmpty ? o.machineryTitles.first : '',
              title: o.title,
              rentDate: formatRentDate(o),
              address: o.address,
              publishedAgo: formatPublishedAgo(o.publishedAt),
              latitude: o.latitude,
              longitude: o.longitude,
            ))
        .toList();
  }

  void _onFilterChanged() {
    if (!mounted) return;
    setState(() {
      _current = 0;
      _ordersFuture = _fetchOrders();
    });
  }

  /// Без аргументов: вызов из build, оставлен для совместимости с
  /// существующими местами использования. Теперь, когда `_fetchOrders`
  /// сам учитывает фильтры, дополнительная клиентская фильтрация по
  /// equipment не нужна — но оставляем как защиту, если на карте
  /// активен старый список (до прихода нового future).
  List<_MapOrder> _filterOrders(List<_MapOrder> all) {
    if (AppliedFilter.equipment.isEmpty) return all;
    return all
        .where((_MapOrder o) => AppliedFilter.equipment.contains(o.equipment))
        .toList();
  }

  void _shift(int delta, List<_MapOrder> orders) {
    if (orders.isEmpty) return;
    setState(() {
      _direction = delta;
      _current = (_current + delta) % orders.length;
      if (_current < 0) _current += orders.length;
    });
    _centerOnOrder(orders[_current]);
  }

  @override
  void dispose() {
    // Сохраняем текущий центр и зум — при следующем заходе на карту
    // (в этой же сессии) восстановим их, если у юзера нет геолокации.
    // try/catch: если карта так и не отрисовалась (быстрый dispose
    // на splash-кадре), MapController.camera кидает исключение.
    try {
      _lastViewedCenter = _mapController.camera.center;
      _lastViewedZoom = _mapController.camera.zoom;
    } catch (_) {/* карта не успела отрендериться */}
    // Отменяем активную анимацию камеры до dispose контроллера, иначе её
    // тикер переживёт State (утечка + ассерт в debug).
    _mapController.cancelAnimatedMove();
    // MapController внутри ChangeNotifier — без явного dispose ссылка
    // на его внутренние подписки живёт до конца процесса. На устройствах
    // со слабой памятью многократные заходы на карту копят объекты.
    _mapController.dispose();

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
    AppliedFilter.addressLat = _savedAddressLat;
    AppliedFilter.addressLng = _savedAddressLng;
    AppliedFilter.revision.value = AppliedFilter.revision.value + 1;
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double searchTop = MediaQuery.of(context).padding.top + 48.h;
    final bool active = hasActiveFilter();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<List<_MapOrder>>(
        future: _ordersFuture,
        builder: (BuildContext context,
            AsyncSnapshot<List<_MapOrder>> snap) {
          final List<_MapOrder> all = snap.data ?? const <_MapOrder>[];
          final List<_MapOrder> orders = _filterOrders(all);
          final int idx = orders.isEmpty ? 0 : _current % orders.length;
          // Пока определяем дефолтный центр (геолокация / последний
          // заказ), показываем тот же спиннер, что и сама карта при
          // загрузке тайлов — иначе будет вспышка дефолтной Москвы и
          // мгновенный прыжок камеры, что выглядит сломанно.
          if (!_initialCenterReady) {
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
          // Если карточка скрыта — не выделяем ни один маркер
          // оранжевым; тогда юзер видит «нейтральное» состояние карты,
          // как при первом открытии (фокус на синей точке его
          // местоположения).
          final String? selectedId = (orders.isEmpty || !_cardVisible)
              ? null
              : orders[idx].id;
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: OrdersMapScreen(
                  markers: orders
                      .map((_MapOrder o) => OrderMarkerData(
                            id: o.id,
                            lat: o.latitude,
                            lon: o.longitude,
                          ))
                      .toList(),
                  initialCenter: _initialCenter,
                  initialZoom: _initialZoom,
                  mapController: _mapController,
                  showZoomControls: true,
                  showMyLocation: true,
                  selectedMarkerId: selectedId,
                  onMarkerTap: (String id) => _onMarkerTap(id, orders),
                  onMyLocationTap: () =>
                      setState(() => _cardVisible = false),
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
                      // Правый отступ 8.w симметрично с кнопкой «Назад»
                      // (left: 8.w в Stack ниже) — иначе бар визуально
                      // съезжает влево на тёмной шапке.
                      padding: EdgeInsets.fromLTRB(16.w, 8.h, 8.w, 8.h),
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
                    query: _query,
                    onSelect: _onAddressSelected,
                  ),
                ),
              if (orders.isEmpty &&
                  active &&
                  snap.connectionState == ConnectionState.done)
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
              if (orders.isNotEmpty && _cardVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragEnd: (DragEndDetails d) {
                      final double v = d.primaryVelocity ?? 0;
                      if (v < -150) {
                        _shift(1, orders);
                      } else if (v > 150) {
                        _shift(-1, orders);
                      }
                    },
                    onTap: () {
                      final _MapOrder o = orders[idx];
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OrderDetailScreen(
                            orderId: o.id,
                            initialTitle: o.title,
                          ),
                        ),
                      );
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      reverseDuration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutQuint,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder:
                          (Widget? current, List<Widget> previous) => Stack(
                        alignment: Alignment.bottomCenter,
                        children: [...previous, ?current],
                      ),
                      transitionBuilder:
                          (Widget child, Animation<double> anim) {
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
                              ? const Interval(0.15, 1.0,
                                  curve: Curves.easeOut)
                              : const Interval(0.0, 0.7,
                                  curve: Curves.easeIn),
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
          );
        },
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
              Flexible(
                child: Text(o.equipment,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 12.sp,
                      color: matched
                          ? AppColors.primary
                          : AppColors.textTertiary,
                      height: 1.3,
                    )),
              ),
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
    this.latitude,
    this.longitude,
  });
  final String id;
  final String equipment;
  final String title;
  final String rentDate;
  final String address;
  final String publishedAgo;
  final double? latitude;
  final double? longitude;
}

/// Дроп-даун подсказок DaData под строкой поиска на карте. Сам подписан
/// на изменения `query` — родителю достаточно перерисовать виджет с
/// новым `query`, debounce и сетевые запросы здесь свои.
class _AddressSuggestions extends StatefulWidget {
  const _AddressSuggestions({
    required this.query,
    required this.onSelect,
  });

  final String query;

  /// Передаём весь объект DadataAddress (а не строку) — родителю
  /// нужны координаты `lat`/`lon`, чтобы переместить камеру карты
  /// на выбранную точку.
  final ValueChanged<DadataAddress> onSelect;

  @override
  State<_AddressSuggestions> createState() => _AddressSuggestionsState();
}

class _AddressSuggestionsState extends State<_AddressSuggestions> {
  Timer? _debounce;
  List<DadataAddress> _suggestions = const <DadataAddress>[];

  @override
  void initState() {
    super.initState();
    _scheduleFetch(widget.query);
  }

  @override
  void didUpdateWidget(covariant _AddressSuggestions old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _scheduleFetch(widget.query);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleFetch(String q) {
    _debounce?.cancel();
    final String trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() => _suggestions = const <DadataAddress>[]);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetch(trimmed));
  }

  Future<void> _fetch(String query) async {
    final List<DadataAddress> res =
        await DadataService.instance.suggest(query);
    if (!mounted) return;
    if (widget.query.trim() != query) return;
    setState(() => _suggestions = res);
  }

  @override
  Widget build(BuildContext context) {
    if (_suggestions.isEmpty) return const SizedBox.shrink();
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12.r),
      color: AppColors.surface,
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.symmetric(vertical: 8.h),
        itemCount: _suggestions.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          thickness: 0.5,
          indent: 16.w,
          endIndent: 16.w,
          color: AppColors.divider,
        ),
        itemBuilder: (BuildContext context, int i) {
          final DadataAddress a = _suggestions[i];
          return InkWell(
            onTap: () => widget.onSelect(a),
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
                      a.value,
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

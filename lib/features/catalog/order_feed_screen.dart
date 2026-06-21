import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:latlong2/latlong.dart';

import 'package:dispatcher_1/core/ai/ai_navigation.dart';
import 'package:dispatcher_1/core/catalog/catalog_service.dart';
import 'package:dispatcher_1/core/catalog/format.dart';
import 'package:dispatcher_1/core/catalog/models.dart';
import 'package:dispatcher_1/core/realtime/realtime_service.dart';
import 'package:dispatcher_1/core/dadata/dadata_service.dart';
import 'package:dispatcher_1/core/location_permission.dart';
import 'package:dispatcher_1/core/utils/mock_coords.dart';
import 'package:dispatcher_1/core/widgets/openfreemap_view.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/catalog/order_detail_screen.dart';
import 'package:dispatcher_1/features/catalog/orders_map_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/applied_filter_chips.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/widgets/order_card.dart';
import 'package:dispatcher_1/features/shell/main_shell.dart';
import 'package:dispatcher_1/features/shell/widgets/main_bottom_nav_bar.dart';

/// Лента заказов категории. Источник — `public.orders` через
/// [CatalogService.listPublishedOrders]. Фильтры (техника/категории)
/// по-прежнему живут в глобальном [AppliedFilter]; строка поиска —
/// локальная, с небольшим debounce перед запросом.
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
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  bool _addressSelected = false;
  Timer? _debounceTimer;
  late Future<List<OrderListItem>> _ordersFuture;

  /// Последнее значение `AppliedFilter.revision`, под которое мы уже
  /// пересчитали `_ordersFuture`. Сравниваем в `build` (под
  /// `ValueListenableBuilder`), чтобы реактивно реагировать на смену
  /// фильтра — но без вызова `_fetchOrders` на каждый build (например,
  /// при смене `_tab`).
  int _appliedFilterRev = 0;

  /// MapController живёт на уровне feed screen, а не внутри
  /// `_OrdersMapWithCard`. Так при пересоздании виджета карты (через
  /// `ValueKey` от orders) controller сохраняется, и при выборе
  /// адреса в поиске мы всегда можем переместить камеру независимо
  /// от того, на каком фильтре мы сейчас.
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _appliedFilterRev = AppliedFilter.revision.value;
    _ordersFuture = _fetchOrders();
    // Realtime: при изменении любой записи в `orders`/`order_matches`
    // глобальный RealtimeService бампит ordersFeedBeacon. Лента
    // пере-фетчит, чтобы новый/изменённый/снятый заказ появлялся /
    // исчезал «живьём», без pull-to-refresh.
    RealtimeService.ordersFeedBeacon.addListener(_onFeedChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    RealtimeService.ordersFeedBeacon.removeListener(_onFeedChanged);
    // Отменяем активную анимацию камеры до dispose контроллера, иначе её
    // тикер переживёт State (утечка + ассерт в debug при смене фильтра во
    // время анимации свайпа карточек).
    _mapController.cancelAnimatedMove();
    // MapController — ChangeNotifier; без явного dispose накапливает
    // ссылки между заходами в ленту.
    _mapController.dispose();
    super.dispose();
  }

  void _onFeedChanged() {
    if (!mounted) return;
    setState(() => _ordersFuture = _fetchOrders());
  }

  Future<List<OrderListItem>> _fetchOrders() {
    // Радиус-фильтр работает только при наличии координат адреса (выбран
    // из подсказок DaData). Если пользователь ввёл адрес вручную — фильтр
    // деградирует до текстового `addressContains`.
    final bool radiusActive = AppliedFilter.radiusKm != null &&
        AppliedFilter.addressLat != null &&
        AppliedFilter.addressLng != null;
    return CatalogService.instance.listPublishedOrders(
      machineryTitles: AppliedFilter.equipment,
      categoryTitles: AppliedFilter.categories,
      search: _query.trim().isEmpty ? null : _query,
      dateFrom: AppliedFilter.dateFrom,
      // «Точная дата» = окно из одного дня [dateFrom, dateFrom], чтобы
      // показывались заказы, активные ИМЕННО в этот день (включая многодневные,
      // накрывающие его), а не «начиная с этого дня».
      dateTo: AppliedFilter.exactDate
          ? AppliedFilter.dateFrom
          : AppliedFilter.dateTo,
      addressContains: radiusActive ? null : AppliedFilter.address,
      timeFrom: _hhmm(AppliedFilter.timeFrom),
      timeTo: _hhmm(AppliedFilter.timeTo),
      wholeDay: AppliedFilter.wholeDay ? true : null,
      originLat: radiusActive ? AppliedFilter.addressLat : null,
      originLng: radiusActive ? AppliedFilter.addressLng : null,
      radiusKm: radiusActive ? AppliedFilter.radiusKm : null,
    );
  }

  /// `TimeOfDay(h:9, m:30)` → `'09:30'`. Возвращает null, если нет
  /// значения, чтобы не ставить пустое условие в SELECT.
  String? _hhmm(TimeOfDay? t) {
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  // _onFilterChanged удалён: подписка на AppliedFilter.revision
  // переехала в build через ValueListenableBuilder + _maybeRefreshForFilterRevision.

  /// Сверяет в `build` текущее `AppliedFilter.revision` с последним
  /// применённым; если разошлись — пересоздаёт `_ordersFuture`. Раньше
  /// это делалось через `addListener` + `setState`, но листенер на табе
  /// «На карте» по какой-то причине не приводил к перерисовке (chips
  /// «активный фильтр» тоже не появлялись, пока юзер не переключал
  /// _tab). Реактивный путь через `ValueListenableBuilder` гарантирует
  /// rebuild на изменении `revision`, отсюда чипы и карта обновляются
  /// синхронно.
  void _maybeRefreshForFilterRevision(int rev) {
    if (rev == _appliedFilterRev) return;
    _appliedFilterRev = rev;
    _ordersFuture = _fetchOrders();
  }

  void _onSearchChanged(String v) {
    setState(() {
      _query = v;
      _addressSelected = false;
    });
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _ordersFuture = _fetchOrders());
    });
  }

  bool get _hasActiveFilter => hasActiveFilter();

  Future<void> _openFilter() async {
    // Ждём возврата с экрана фильтра и явно перезапускаем загрузку.
    // Подписка на `AppliedFilter.revision` обычно дергает _onFilterChanged
    // синхронно при «Применить», но на табе «На карте» наблюдалась
    // ситуация, когда маркеры не успевали обновиться к новому
    // отфильтрованному набору (как будто IndexedStack кешировал
    // ребёнка-карту). Явный setState после возврата гарантирует,
    // что _ordersFuture точно стартанёт заново и карта пересобрала
    // маркеры с новыми orders.
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const CatalogFilterScreen(),
      ),
    );
    if (!mounted) return;
    setState(() => _ordersFuture = _fetchOrders());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 48.h,
        leading: Padding(
          padding: EdgeInsets.only(top: 2.h),
          child: IconButton(
            icon: Image.asset(
              'assets/icons/ui/back_arrow.webp',
              width: 24.r,
              height: 24.r,
              fit: BoxFit.contain,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Padding(
          padding: EdgeInsets.only(top: 2.h),
          child: Text(
            'Лента заказов',
            style: AppTextStyles.titleS.copyWith(color: Colors.white),
          ),
        ),
      ),
      bottomNavigationBar: MainBottomNavBar(
        items: kMainNavItems,
        currentIndex: 0,
        onTap: (int i) {
          MainShell.selectedTab.value = i;
          Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
        },
      ),
      floatingActionButton: _tab == 0
          ? Padding(
              padding: EdgeInsets.only(bottom: 24.h),
              child: AiAssistantFab(
                onTap: () => openAssistantChat(context),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: ValueListenableBuilder<int>(
        // Реактивная подписка на изменения фильтра. Раньше тут был
        // addListener в initState — он по неясной причине не приводил
        // к перерисовке, когда юзер находился на табе «На карте»:
        // chips «активный фильтр» и красный значок не появлялись,
        // а маркеры на карте оставались прежними до ручного
        // переключения на «Списком». ValueListenableBuilder
        // гарантирует rebuild при каждом revision++.
        valueListenable: AppliedFilter.revision,
        builder: (BuildContext _, int rev, Widget? _) {
          _maybeRefreshForFilterRevision(rev);
          return Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                color: AppColors.navBarDark,
                child: CatalogSearchBar(
                  controller: _searchCtrl,
                  hintText: _tab == 1 ? 'Поиск по адресу' : 'Поиск',
                  onFilterTap: _openFilter,
                  onChanged: _onSearchChanged,
                  showFilterBadge: _hasActiveFilter,
                ),
              ),
              SizedBox(height: 12.h),
              CatalogSegmented(
                index: _tab,
                items: const <String>['Списком', 'На карте'],
                onChanged: (int v) {
                  setState(() => _tab = v);
                  if (v == 1) ensureLocationPermission();
                },
              ),
              if (_hasActiveFilter)
                AppliedFilterChips(onChanged: () => setState(() {}))
              else
                SizedBox(height: 16.h),
              Expanded(
                child: FutureBuilder<List<OrderListItem>>(
                  future: _ordersFuture,
                  builder: (BuildContext context,
                      AsyncSnapshot<List<OrderListItem>> snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return _FeedError(
                        onRetry: () => setState(() {
                          _ordersFuture = _fetchOrders();
                        }),
                      );
                    }
                    final List<OrderListItem> orders =
                        snap.data ?? const <OrderListItem>[];
                    return IndexedStack(
                      index: _tab,
                      children: <Widget>[
                        RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: () async {
                            final Future<List<OrderListItem>> next =
                                _fetchOrders();
                            setState(() => _ordersFuture = next);
                            await next;
                          },
                          child: orders.isEmpty
                              ? LayoutBuilder(
                                  // SingleChildScrollView + ConstrainedBox
                                  // даёт pull-to-refresh поверх пустого
                                  // состояния И вертикальное центрирование
                                  // содержимого. Раньше тут был ListView с
                                  // одним ребёнком, который прижимал
                                  // «Заказы не найдены» к самому верху.
                                  builder: (BuildContext _,
                                      BoxConstraints constraints) {
                                    return SingleChildScrollView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: constraints.maxHeight,
                                        ),
                                        child: const Center(
                                          child: _EmptyOrdersState(),
                                        ),
                                      ),
                                    );
                                  },
                                )
                              : _OrderList(orders: orders),
                        ),
                        _OrdersMapWithCard(
                          // Ключ от набора id: при смене фильтра состав
                          // orders меняется → ключ меняется → виджет
                          // карты пересоздаётся целиком (включая
                          // FlutterMap и MarkerLayer). Это нужно потому,
                          // что пока юзер на табе «На карте»,
                          // flutter_map кеширует уже отрисованный
                          // layer и не реагирует на новый widget.markers,
                          // а лёгкие приёмы (ValueKey на MarkerLayer +
                          // `_mapController.move(...)` на ту же
                          // позицию) проблему не закрывали — фильтр
                          // применялся только после ручного
                          // переключения на «Списком». Пересоздание
                          // сбрасывает зум/центр карты — это плата за
                          // гарантированный refresh.
                          key: ValueKey<String>(
                            orders
                                .map((OrderListItem o) => o.id)
                                .join(','),
                          ),
                          orders: orders,
                          externalController: _mapController,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          if (_tab == 1 && _query.trim().isNotEmpty && !_addressSelected)
            Positioned(
              top: 44.h + 3.h,
              left: 16.w,
              right: 16.w,
              child: _AddressSuggestions(
                query: _query,
                onSelect: (DadataAddress a) {
                  _searchCtrl.text = a.value;
                  setState(() {
                    _query = a.value;
                    _addressSelected = true;
                    _ordersFuture = _fetchOrders();
                  });
                  FocusScope.of(context).unfocus();
                  // Перемещаем карту к выбранному адресу, если у DaData
                  // есть координаты. Зум 13 — компромисс: видна
                  // улица + соседние кварталы. Раньше координаты
                  // выбрасывались, и юзер вводил «Санкт-Петербург»,
                  // но камера упорно стояла в Москве.
                  if (a.hasCoords) {
                    try {
                      _mapController.move(LatLng(a.lat!, a.lon!), 13);
                    } catch (_) {/* карта ещё не отрисовалась */}
                  }
                },
              ),
            ),
        ],
      );
        },
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({required this.orders});
  final List<OrderListItem> orders;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
        itemCount: orders.length,
        separatorBuilder: (_, _) => SizedBox(height: 16.h),
        itemBuilder: (BuildContext context, int i) {
          final OrderListItem o = orders[i];
          return Container(
            decoration: BoxDecoration(
              color: AppColors.fieldFill,
              borderRadius: BorderRadius.circular(14.r),
            ),
            clipBehavior: Clip.antiAlias,
            child: OrderCard(
              title: o.title,
              address: o.address,
              rentDate: formatRentDate(o),
              publishedAgo: formatPublishedAgo(o.publishedAt),
              equipment: o.machineryTitles,
              highlightEquipment: AppliedFilter.equipment,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OrderDetailScreen(
                    orderId: o.id,
                    initialTitle: o.title,
                    multipleEquipment: o.machineryTitles.length > 1,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyOrdersState extends StatelessWidget {
  const _EmptyOrdersState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Image.asset(
              'assets/icons/profile/no_orders.webp',
              width: 80.r,
              height: 80.r,
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            'Заказы не найдены',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 20.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 6.h),
          Text(
            'Попробуйте изменить фильтры',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16.sp,
              fontWeight: FontWeight.w400,
              height: 1.3,
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Не удалось загрузить ленту',
              style: AppTextStyles.bodyMRegular
                  .copyWith(color: AppColors.textPrimary),
            ),
            SizedBox(height: 12.h),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

/// Карта-заглушка + плашка снизу с одним заказом. Свайп вверх по плашке
/// переключает на следующий заказ в списке (циклически).
class _OrdersMapWithCard extends StatefulWidget {
  const _OrdersMapWithCard({
    super.key,
    required this.orders,
    this.externalController,
  });

  final List<OrderListItem> orders;

  /// MapController, переданный сверху (с уровня feed screen). Если
  /// задан — используем его и не создаём внутренний; так controller
  /// переживает пересоздание виджета карты по `ValueKey(orders)`,
  /// и `feed`-экран может двигать камеру (по выбору адреса в поиске),
  /// не теряя ссылку при смене фильтра.
  final MapController? externalController;

  @override
  State<_OrdersMapWithCard> createState() => _OrdersMapWithCardState();
}

class _OrdersMapWithCardState extends State<_OrdersMapWithCard>
    with TickerProviderStateMixin {
  late final MapController _mapController =
      widget.externalController ?? MapController();
  int _current = 0;
  int _direction = 1;

  /// Видимость нижней карточки заказа. По умолчанию `false` —
  /// при первом открытии экрана юзер видит чистую карту с синей
  /// точкой своего местоположения; карточка появляется только когда
  /// он тапает в маркер. Тап по кнопке «моё местоположение» снова
  /// её прячет.
  bool _cardVisible = false;

  @override
  void dispose() {
    // Анимация камеры (animatedMove) хранится глобально по контроллеру и
    // переживает пересоздание ЭТОГО виджета по ValueKey(orders). Если в
    // момент realtime-обновления ленты (состав заказов сменился) шёл
    // свайп/центрирование — у нового State оказался бы активный тикер от
    // мёртвого: «Ticker disposed with an active Ticker» в debug и утечка
    // контроллера в release. Отменяем анимацию при уничтожении.
    _mapController.cancelAnimatedMove();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _OrdersMapWithCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameOrders(oldWidget.orders, widget.orders)) {
      _current = 0;
      _direction = 1;
      // Принудительный «пинок» камеры на ту же позицию: flutter_map
      // на активном табе кеширует слой маркеров и не перерисовывает
      // его при изменении `widget.markers`. При смене фильтра было
      // видно, что список заказов уже отфильтрован, а маркеры на
      // карте остались старыми; они появлялись только при
      // переключении табов (Списком→Карта). `move()` на текущий
      // центр и зум форсирует репаинт без визуального скачка.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(
            _mapController.camera.center,
            _mapController.camera.zoom,
          );
        } catch (_) {/* карта не отрисовалась */}
      });
    }
  }

  bool _sameOrders(List<OrderListItem> a, List<OrderListItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _shift(int delta) {
    if (widget.orders.isEmpty) return;
    setState(() {
      _direction = delta;
      _current = (_current + delta) % widget.orders.length;
      if (_current < 0) _current += widget.orders.length;
    });
    _centerOnOrder(widget.orders[_current]);
  }

  /// Тап по маркеру — выбираем соответствующий заказ в карточке
  /// и одновременно центрируем камеру (тот же UX, что на полноэкранной
  /// карте `OrdersMapFullScreen`).
  void _onMarkerTap(String id) {
    final int idx =
        widget.orders.indexWhere((OrderListItem o) => o.id == id);
    if (idx < 0) return;
    setState(() {
      _direction = idx > _current ? 1 : -1;
      _current = idx;
      _cardVisible = true;
    });
    _centerOnOrder(widget.orders[idx]);
  }

  /// Двигает камеру к маркеру заказа без изменения текущего zoom.
  /// Если у заказа нет координат в БД — используем тот же fallback
  /// `mockMoscowCoordsForId`, что использует [OrdersMapScreen] при
  /// рендере маркеров: иначе камера не двигается, и юзер думает,
  /// что свайп сломан.
  void _centerOnOrder(OrderListItem o) {
    final LatLng target = (o.latitude != null && o.longitude != null)
        ? LatLng(o.latitude!, o.longitude!)
        : mockMoscowCoordsForId(o.id);
    try {
      final double currentZoom = _mapController.camera.zoom;
      _mapController.animatedMove(target, currentZoom, vsync: this);
    } catch (_) {/* карта не успела отрендериться */}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orders.isEmpty) {
      return OrdersMapScreen(
        mapController: _mapController,
        showZoomControls: true,
        showMyLocation: true,
      );
    }
    final int idx = _current % widget.orders.length;
    final OrderListItem o = widget.orders[idx];
    final List<OrderMarkerData> markers = widget.orders
        .map((OrderListItem o) => OrderMarkerData(
              id: o.id,
              lat: o.latitude,
              lon: o.longitude,
            ))
        .toList();
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: OrdersMapScreen(
            markers: markers,
            mapController: _mapController,
            showZoomControls: true,
            showMyLocation: true,
            // Когда карточка скрыта — ни один маркер не подсвечивается
            // оранжевым: пользователь видит «нейтральную» карту.
            selectedMarkerId: _cardVisible ? o.id : null,
            onMarkerTap: _onMarkerTap,
            onMyLocationTap: () =>
                setState(() => _cardVisible = false),
          ),
        ),
        if (_cardVisible) Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (DragEndDetails d) {
              final double v = d.primaryVelocity ?? 0;
              if (v < -150) {
                _shift(1);
              } else if (v > 150) {
                _shift(-1);
              }
            },
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OrderDetailScreen(
                  orderId: o.id,
                  initialTitle: o.title,
                  multipleEquipment: o.machineryTitles.length > 1,
                ),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              reverseDuration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutQuint,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder:
                  (Widget? current, List<Widget> previous) => Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  ...previous,
                  ?current,
                ],
              ),
              transitionBuilder: (Widget child, Animation<double> anim) {
                final bool isIncoming = child.key == ValueKey<int>(idx);
                final double dir = _direction.toDouble();
                final Animation<Offset> slide = Tween<Offset>(
                  begin: isIncoming ? Offset(0, 0.55 * dir) : Offset.zero,
                  end: isIncoming ? Offset.zero : Offset(0, -0.9 * dir),
                ).animate(anim);
                final Animation<double> scale = Tween<double>(
                  begin: isIncoming ? 0.88 : 1.0,
                  end: isIncoming ? 1.0 : 0.94,
                ).animate(anim);
                final Animation<double> fade = CurvedAnimation(
                  parent: anim,
                  curve: isIncoming
                      ? const Interval(0.15, 1.0, curve: Curves.easeOut)
                      : const Interval(0.0, 0.7, curve: Curves.easeIn),
                );
                return SlideTransition(
                  position: slide,
                  child: ScaleTransition(
                    scale: scale,
                    child: FadeTransition(opacity: fade, child: child),
                  ),
                );
              },
              child: Container(
                key: ValueKey<int>(idx),
                // double.infinity нужен из-за того, что AnimatedSwitcher
                // оборачивает свой child в Stack с alignment=bottomCenter,
                // который ослабляет width-constraint. Без явной ширины
                // Container ужимался под самый широкий Text внутри
                // (раньше Row spaceBetween держал максимум, после её
                // удаления карточка съёжилась).
                width: double.infinity,
                margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 20.h),
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
                    // Все виды спецтехники заказа — тот же стиль, что
                    // в MyOrderCard и других списках (серый, 12sp, через
                    // тройной пробел). Если техники много и она не
                    // помещается в одну строку с датой публикации,
                    // Expanded заворачивает её на следующие строки;
                    // дата при этом остаётся справа сверху, между
                    // техникой и датой — отступ 12.w, чтобы строки не
                    // упирались друг в друга.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            o.machineryTitles.join('   '),
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 12.sp,
                              color: AppColors.textTertiary,
                              height: 1.3,
                            ),
                            softWrap: true,
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Text(
                          formatPublishedAgo(o.publishedAt),
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 12.sp,
                            color: AppColors.textTertiary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      o.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleS.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    _MapCardLine(
                        label: 'Дата аренды:', value: formatRentDate(o)),
                    SizedBox(height: 4.h),
                    _MapCardLine(label: 'Адрес:', value: o.address),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapCardLine extends StatelessWidget {
  const _MapCardLine({required this.label, required this.value});
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

/// Дроп-даун подсказок DaData под строкой поиска во вкладке «На карте».
/// Сам подписан на изменения `query` — родителю достаточно перерисовать
/// виджет с новым `query`, debounce и сетевые запросы здесь свои.
class _AddressSuggestions extends StatefulWidget {
  const _AddressSuggestions({
    required this.query,
    required this.onSelect,
  });

  final String query;

  /// Возвращает выбранный `DadataAddress` целиком — родителю нужны
  /// и строка, и координаты (для перемещения карты к выбранному
  /// адресу). Раньше отдавали только `String value` и теряли lat/lon,
  /// поэтому при выборе «г Санкт-Петербург, ...» камера оставалась
  /// в Москве.
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
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _fetch(trimmed));
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

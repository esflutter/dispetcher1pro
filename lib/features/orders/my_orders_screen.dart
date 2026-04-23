import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/utils/phone_dial.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'package:dispatcher_1/features/orders/order_detail_screen.dart';
import 'package:dispatcher_1/features/orders/widgets/my_order_card.dart';
import 'package:dispatcher_1/features/orders/widgets/order_status_pill.dart';
import 'package:dispatcher_1/features/profile/account_block.dart';

/// Статические данные «Мои заказы» — живут поверх жизненного цикла
/// экрана, чтобы изменения из других мест (например, отклик в каталоге)
/// попадали во вкладку «Новые» сразу при следующем открытии экрана.
class MyOrdersStore {
  MyOrdersStore._();

  static final DateTime _now = DateTime.now();
  static DateTime _minsAgo(int m) => _now.subtract(Duration(minutes: m));
  static DateTime _hoursAgo(int h) => _now.subtract(Duration(hours: h));
  static DateTime _daysAgo(int d) => _now.subtract(Duration(days: d));

  static final List<_OrderMock> _newOrders = <_OrderMock>[
    _OrderMock(
      id: 'n0',
      status: MyOrderStatus.offerSent,
      title: 'Расчистка строительной площадки',
      equipment: const <String>['Бульдозер', 'Экскаватор'],
      rentDate: '18 июня · 08:00–17:00',
      address: 'Московская область, Москва, Улица1, д 144',
      publishedAgo: '1 час назад',
      statusUpdatedAt: _hoursAgo(1),
      customerId: '1',
      customerName: 'Александр Иванов',
      customerPhone: '+7 999 123-45-67',
    ),
    _OrderMock(
      id: 'n1',
      status: MyOrderStatus.pendingConfirmation,
      title: 'Нужен экскаватор для копки траншеи',
      equipment: const <String>['Экскаватор'],
      rentDate: '15 июня · 09:00–18:00',
      address: 'Московская область, Москва, Улица1, д 144',
      publishedAgo: '2 часа назад',
      statusUpdatedAt: _hoursAgo(2),
      customerId: '2',
      customerName: 'Пётр Иванов',
      customerPhone: '+7 999 234-56-78',
    ),
    _OrderMock(
      id: 'n2',
      status: MyOrderStatus.pendingConfirmation,
      title: 'Земляные работы',
      equipment: const <String>['Автокран', 'Экскаватор'],
      rentDate: '15 июня · 09:00–18:00',
      address: 'Московская область, Москва, Улица1, д 144',
      publishedAgo: 'Сегодня в 11:30',
      statusUpdatedAt: _hoursAgo(3),
      customerId: '3',
      customerName: 'Сергей Петров',
      customerPhone: '+7 999 345-67-89',
    ),
    _OrderMock(
      id: 'n3',
      status: MyOrderStatus.pendingConfirmation,
      title: 'Разработка котлована под фундамент',
      equipment: const <String>[
        'Экскаватор',
        'Автокран',
        'Эвакуатор',
        'Манипулятор',
        'Автовышка',
      ],
      rentDate: '15 июня · 09:00–18:00',
      address: 'Московская область, Москва, Улица1, д 144',
      publishedAgo: 'Сегодня в 11:30',
      statusUpdatedAt: _hoursAgo(4),
      customerId: '4',
      customerName: 'Михаил Смирнов',
      customerPhone: '+7 999 456-78-90',
    ),
  ];

  static final List<_OrderMock> _accepted = <_OrderMock>[
    _OrderMock(
      id: 'a1',
      status: MyOrderStatus.accepted,
      title: 'Нужен экскаватор для копки траншеи',
      equipment: const <String>['Экскаватор'],
      rentDate: '15 июня · 09:00–18:00',
      address: 'Московская область, Москва, Улица1, д 144',
      publishedAgo: '2 часа назад',
      statusUpdatedAt: _minsAgo(45),
      customerId: '1',
      customerName: 'Александр Иванов',
      customerPhone: '+7 999 123-45-67',
      customerEmail: 'alex.ivanov@example.ru',
      customerRating: 4.5,
      customerReviews: 15,
    ),
    _OrderMock(
      id: 'a2',
      status: MyOrderStatus.accepted,
      title: 'Разработка котлована под фундамент',
      equipment: const <String>[
        'Экскаватор',
        'Автокран',
        'Эвакуатор',
        'Манипулятор',
        'Автовышка',
      ],
      rentDate: '15 июня · 09:00–18:00',
      address: 'Московская область, Москва, Улица1, д 144',
      publishedAgo: 'Сегодня в 11:30',
      statusUpdatedAt: _hoursAgo(2),
      customerId: '2',
      customerName: 'Пётр Иванов',
      customerPhone: '+7 999 123-45-67',
      customerEmail: 'petrov.ivanov@example.ru',
      customerRating: 4.8,
      customerReviews: 27,
    ),
    _OrderMock(
      id: 'a3',
      status: MyOrderStatus.completed,
      title: 'Нужен экскаватор для копки траншеи',
      equipment: const <String>['Экскаватор'],
      rentDate: '15 июня · 09:00–18:00',
      address: 'Московская область, Москва, Улица1, д 144',
      publishedAgo: 'Вчера в 14:30',
      statusUpdatedAt: _daysAgo(1),
      customerId: '1',
      customerName: 'Александр Иванов',
      customerPhone: '+7 999 123-45-67',
      customerRating: 4.5,
      customerReviews: 15,
    ),
  ];

  static final List<_OrderMock> _rejected = <_OrderMock>[
    _OrderMock(
      id: 'r1',
      status: MyOrderStatus.rejectedOther,
      title: 'Земляные работы',
      equipment: const <String>['Автокран', 'Экскаватор'],
      rentDate: '15 июня · 09:00–18:00',
      address: 'Московская область, Москва, Улица1, д 144',
      publishedAgo: '2 часа назад',
      statusUpdatedAt: _hoursAgo(2),
      customerId: '3',
      customerName: 'Сергей Петров',
    ),
    _OrderMock(
      id: 'r2',
      status: MyOrderStatus.rejectedDeclined,
      title: 'Разработка котлована под фундамент',
      equipment: const <String>[
        'Экскаватор',
        'Автокран',
        'Эвакуатор',
        'Манипулятор',
        'Автовышка',
      ],
      rentDate: '15 июня · 09:00–18:00',
      address: 'Московская область, Москва, Улица1, д 144',
      publishedAgo: 'Вчера в 14:30',
      statusUpdatedAt: _daysAgo(1),
      customerId: '4',
      customerName: 'Михаил Смирнов',
    ),
    _OrderMock(
      id: 'r3',
      status: MyOrderStatus.rejectedRemoved,
      title: 'Разработка котлована под фундамент',
      equipment: const <String>[
        'Экскаватор',
        'Автокран',
        'Эвакуатор',
        'Манипулятор',
        'Автовышка',
      ],
      rentDate: '15 июня · 09:00–18:00',
      address: 'Московская область, Москва, Улица1, д 144',
      publishedAgo: '3 дня назад',
      statusUpdatedAt: _daysAgo(3),
      customerId: '5',
      customerName: 'Виктор Новиков',
    ),
  ];

  /// Ключи, уведомляющие подписчиков о добавлении новых записей — через
  /// инкремент `revision.value` родитель `MyOrdersScreen` делает
  /// `setState`, чтобы свежий отклик появился, даже если экран уже открыт.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Добавляет отклик в «Новые» со статусом `offerSent` — вызывается из
  /// каталога после успешной кнопки «Откликнуться». Идемпотентно: если
  /// заказ с таким `id` уже в списке — не дублируем.
  static void addResponded({
    required String id,
    required String title,
    required List<String> equipment,
    required String rentDate,
    required String address,
    required String publishedAgo,
    required String customerId,
    required String customerName,
    required double customerRating,
    required int customerReviews,
  }) {
    if (_newOrders.any((o) => o.id == id)) return;
    _newOrders.insert(
      0,
      _OrderMock(
        id: id,
        status: MyOrderStatus.offerSent,
        title: title,
        equipment: equipment,
        rentDate: rentDate,
        address: address,
        publishedAgo: publishedAgo,
        statusUpdatedAt: DateTime.now(),
        customerId: customerId,
        customerName: customerName,
        customerRating: customerRating,
        customerReviews: customerReviews,
      ),
    );
    revision.value++;
  }

  /// Полная очистка всех трёх списков — для logout/удаления аккаунта,
  /// чтобы у следующего пользователя на этом устройстве не оставались
  /// отклики/принятые/отклонённые прошлого.
  static void clear() {
    _newOrders.clear();
    _accepted.clear();
    _rejected.clear();
    revision.value++;
  }

}

/// Экран «Мои заказы» — две вкладки «Принятые / Не принятые».
/// Когда обоих списков пусто — показываем заглушку «Здесь появятся ваши отклики».
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key, this.onGoToCatalog, this.isBlocked = false});

  /// Колбэк переключения нижнего таба на «Каталог».
  /// Передаётся из MainShell, потому что мы уже находимся внутри /shell —
  /// обычным go_router'ом сюда не перейти.
  final VoidCallback? onGoToCatalog;
  final bool isBlocked;

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // Все три списка живут в `MyOrdersStore` — это позволяет каталогу
  // добавлять заказ в «Новые» сразу после «Откликнуться», а экран
  // обновится через `MyOrdersStore.revision` либо при повторной
  // отрисовке (после возврата на вкладку).
  List<_OrderMock> get _newOrders => MyOrdersStore._newOrders;
  List<_OrderMock> get _accepted => MyOrdersStore._accepted;
  List<_OrderMock> get _rejected => MyOrdersStore._rejected;

  bool get _isEmpty =>
      _newOrders.isEmpty && _accepted.isEmpty && _rejected.isEmpty;

  bool get _blocked => AccountBlock.isBlocked || widget.isBlocked;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    AccountBlock.notifier.addListener(_refresh);
    MyOrdersStore.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    AccountBlock.notifier.removeListener(_refresh);
    MyOrdersStore.revision.removeListener(_refresh);
    _tab.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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
        titleSpacing: 16.w,
        toolbarHeight: 64.h,
        title: Text(
          'Мои заказы',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 28.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.2,
          ),
        ),
      ),
      body: _isEmpty
          ? _EmptyOrders(onGoToCatalog: widget.onGoToCatalog)
          : _buildWithTabs(),
    );
  }

  Widget _buildWithTabs() {
    return Column(
      children: <Widget>[
        Container(
          color: AppColors.background,
          // Сверху 17.h — на 40% больше предыдущих 12. Снизу 5.h:
          // вместе с собственным 12.h первой карточки даёт те же 17.h
          // под пилюлей, чтобы отступы сверху и снизу были одинаковыми.
          padding: EdgeInsets.fromLTRB(16.w, 17.h, 16.w, 5.h),
          child: _OrdersSegmented(
            controller: _tab,
            items: const <String>['Новые', 'Принятые', 'Не принятые'],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: <Widget>[
              _buildList(_newOrders),
              _buildList(_accepted),
              _buildList(_rejected),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<_OrderMock> items) {
    if (items.isEmpty) {
      return _EmptyOrders(onGoToCatalog: widget.onGoToCatalog);
    }
    final List<_OrderMock> sorted = List<_OrderMock>.from(items)
      ..sort((a, b) => b.statusUpdatedAt.compareTo(a.statusUpdatedAt));
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: sorted.length,
        itemBuilder: (BuildContext context, int i) {
          final _OrderMock o = sorted[i];
          final bool isLast = i == sorted.length - 1;
          return Column(
            children: <Widget>[
              MyOrderCard(
                status: o.status,
                title: o.title,
                equipment: o.equipment,
                rentDate: o.rentDate,
                address: o.address,
                publishedAgo: o.timeAgo,
                customerName: o.customerName,
                customerPhone: o.customerPhone,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MyOrderDetailScreen(
                      title: o.title,
                      equipment: o.equipment,
                      rentDate: o.rentDate,
                      address: o.address,
                      publishedAgo: o.timeAgo,
                      orderNumber: o.displayNumber,
                      customerId: o.customerId,
                      customerName: o.customerName ?? CropResult.namePlaceholder,
                      customerPhone: o.customerPhone ?? '+7 999 123-45-67',
                      customerEmail: o.customerEmail,
                      customerRating: o.customerRating,
                      customerReviews: o.customerReviews,
                      state: _detailStateForCard(o.status),
                      rejectedStatus: o.status,
                      onDecline: () =>
                          _moveToRejected(o, MyOrderStatus.rejectedDeclined),
                      onRefuse: () =>
                          _moveToRejected(o, MyOrderStatus.rejectedDeclined),
                      onWithdraw: () =>
                          _moveToRejected(o, MyOrderStatus.rejectedDeclined),
                      onConfirm: () => _moveToAccepted(o),
                      isBlocked: _blocked,
                    ),
                  ),
                ),
                onContact: () =>
                    dialPhone(context, o.customerPhone ?? ''),
              ),
              if (!isLast)
                Container(
                  height: 1 / MediaQuery.of(context).devicePixelRatio,
                  color: AppColors.primary,
                ),
            ],
          );
        },
      ),
    );
  }

  /// Перемещает заказ из «Новые/Принятые» в «Не принятые» с заданным
  /// красным статусом. Используется при отклонении и при отказе.
  void _moveToRejected(_OrderMock o, MyOrderStatus newStatus) {
    setState(() {
      _newOrders.remove(o);
      _accepted.remove(o);
      _rejected.insert(0, o.copyWith(status: newStatus));
    });
  }

  /// Перемещает заказ из «Новые» в «Принятые» со статусом
  /// `accepted` («Свяжитесь с заказчиком»). Используется при
  /// подтверждении заказа исполнителем.
  void _moveToAccepted(_OrderMock o) {
    setState(() {
      _newOrders.remove(o);
      _accepted.insert(0, o.copyWith(status: MyOrderStatus.accepted));
    });
  }

  MyOrderDetailState _detailStateForCard(MyOrderStatus s) {
    switch (s) {
      case MyOrderStatus.offerSent:
        return MyOrderDetailState.offerSent;
      case MyOrderStatus.pendingConfirmation:
        return MyOrderDetailState.waitingConfirm;
      case MyOrderStatus.accepted:
        return MyOrderDetailState.confirmed;
      case MyOrderStatus.completed:
        return MyOrderDetailState.completed;
      case MyOrderStatus.rejectedOther:
      case MyOrderStatus.rejectedDeclined:
      case MyOrderStatus.rejectedRemoved:
        return MyOrderDetailState.rejected;
    }
  }
}

String _pluralMin(int n) {
  if (n % 10 == 1 && n % 100 != 11) { return 'минуту'; }
  if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) { return 'минуты'; }
  return 'минут';
}

String _pluralH(int n) {
  if (n % 10 == 1 && n % 100 != 11) { return 'час'; }
  if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) { return 'часа'; }
  return 'часов';
}

String _pluralD(int n) {
  if (n % 10 == 1 && n % 100 != 11) { return 'день'; }
  if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) { return 'дня'; }
  return 'дней';
}

class _OrderMock {
  _OrderMock({
    required this.id,
    required this.status,
    required this.title,
    required this.equipment,
    required this.rentDate,
    required this.address,
    required this.publishedAgo,
    DateTime? statusUpdatedAt,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.customerRating = 4.6,
    this.customerReviews = 10,
  }) : statusUpdatedAt = statusUpdatedAt ?? DateTime.now();

  final String id;
  final MyOrderStatus status;
  final String title;
  final List<String> equipment;
  final String rentDate;
  final String address;
  final String publishedAgo;
  final DateTime statusUpdatedAt;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final double customerRating;
  final int customerReviews;

  String get displayNumber {
    final String pfx = id.isNotEmpty ? id[0] : 'n';
    final String digits = id.replaceAll(RegExp(r'\D'), '');
    final int base = pfx == 'a' ? 81220000 : pfx == 'r' ? 81210000 : 81230000;
    final int n = base + (int.tryParse(digits) ?? 0);
    return '№$n';
  }

  String get timeAgo {
    final DateTime now = DateTime.now();
    final Duration diff = now.difference(statusUpdatedAt);
    if (diff.inSeconds < 60) return 'Только что';
    if (diff.inMinutes < 60) {
      final int m = diff.inMinutes;
      return '$m ${_pluralMin(m)} назад';
    }
    if (diff.inHours < 24) {
      final int h = diff.inHours;
      return '$h ${_pluralH(h)} назад';
    }
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime upDay = DateTime(
        statusUpdatedAt.year, statusUpdatedAt.month, statusUpdatedAt.day);
    if (upDay == today.subtract(const Duration(days: 1))) {
      final String hh = statusUpdatedAt.hour.toString().padLeft(2, '0');
      final String mm = statusUpdatedAt.minute.toString().padLeft(2, '0');
      return 'Вчера в $hh:$mm';
    }
    final int d = today.difference(upDay).inDays;
    return '$d ${_pluralD(d)} назад';
  }

  _OrderMock copyWith({MyOrderStatus? status}) {
    return _OrderMock(
      id: id,
      status: status ?? this.status,
      title: title,
      equipment: equipment,
      rentDate: rentDate,
      address: address,
      publishedAgo: publishedAgo,
      statusUpdatedAt: (status != null && status != this.status)
          ? DateTime.now()
          : statusUpdatedAt,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      customerRating: customerRating,
      customerReviews: customerReviews,
    );
  }

  // Сравниваем заказы по id — это нужно, чтобы List.remove корректно
  // находил «тот же» заказ после copyWith (после смены статуса заказ
  // лежит в списке как новая копия с тем же id).
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is _OrderMock && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// Pill-сегмент «Новые / Принятые / Не принятые». Оранжевая обводка,
/// активный сегмент заливается оранжевым, неактивные — белые, разделены
/// тонкими оранжевыми вертикальными линиями.
class _OrdersSegmented extends StatelessWidget {
  const _OrdersSegmented({
    required this.controller,
    required this.items,
  });

  final TabController controller;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        final int index = controller.index;
        final double radius = 22.r;
        return Container(
          height: 40.h,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.primary, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Row(
              // stretch, чтобы GestureDetector каждого сегмента заполнял
              // всю высоту пилюли — иначе кликабельная область становится
              // по высоте текста и края сегмента «не прокликиваются».
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < items.length; i++) ...<Widget>[
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => controller.animateTo(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        alignment: Alignment.center,
                        color: i == index
                            ? AppColors.primary
                            : AppColors.surface,
                        child: Text(
                          items[i],
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w400,
                            height: 1.3,
                            color: i == index
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Разделитель между сегментами — рисуем только если оба
                  // соседа неактивные (иначе оранжевая заливка активного
                  // и так сливается с бордером).
                  if (i < items.length - 1 &&
                      i != index &&
                      i + 1 != index)
                    Container(
                      width: 1,
                      color: AppColors.primary,
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders({this.onGoToCatalog});

  final VoidCallback? onGoToCatalog;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 16 в логических пикселях, без .w — чтобы боковой отступ кнопки
      // совпадал с системным отступом FAB ии-ассистента
      // (FloatingActionButtonLocation.endFloat = 16 dp).
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Здесь появятся ваши отклики',
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
            'Откликнитесь на заказ и получайте\nпредложения от заказчиков',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16.sp,
              fontWeight: FontWeight.w400,
              height: 1.3,
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 26.h),
          PrimaryButton(
            label: 'В каталог',
            onPressed: onGoToCatalog,
          ),
        ],
      ),
    );
  }
}

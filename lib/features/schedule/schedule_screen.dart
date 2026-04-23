import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/executor_card/executor_card_screen.dart';
import 'package:dispatcher_1/features/orders/widgets/order_status_pill.dart';
import 'package:dispatcher_1/features/orders/order_detail_screen.dart';
import 'package:dispatcher_1/features/schedule/day_settings_screen.dart';
import 'package:dispatcher_1/features/schedule/widgets/schedule_alerts.dart';

/// Состояние конкретного дня графика.
enum DayState { noOrders, hasOrders, dayOff }

/// Пользовательские параметры для конкретного дня из экрана
/// «Параметры дня» (карандаш вверху справа «Мой график»). Хранятся
/// в state родительского экрана, чтобы при повторном открытии дня
/// настройки не сбрасывались. Все поля необязательные — если
/// пользователь ничего не выставил, сохраняется дефолт.
class DaySettings {
  const DaySettings({
    this.accepting = true,
    this.timeFrom,
    this.timeTo,
    this.allDay = false,
    this.radiusIndex = -1,
    this.location,
    this.machinery = const <String>{},
    this.categories = const <String>{},
    this.clearDayOff = false,
  });

  /// Варианты радиуса — общие для «Параметров дня» и карточки
  /// исполнителя. Индекс внутри [radiusIndex] ссылается на этот список.
  static const List<String> radiusOptions = <String>[
    'В радиусе 10 км',
    'В радиусе 20 км',
    'В радиусе 50 км',
  ];

  /// Дефолтные параметры дня, построенные из текущей карточки
  /// исполнителя. Используется, когда пользователь не выставил
  /// индивидуальные настройки для конкретного дня.
  factory DaySettings.fromExecutorCard({bool accepting = true}) {
    final String? cardRadius = ExecutorCardData.radius;
    final int idx = cardRadius == null ? -1 : radiusOptions.indexOf(cardRadius);
    return DaySettings(
      accepting: accepting,
      location: ExecutorCardData.location,
      radiusIndex: idx,
      machinery: Set<String>.from(ExecutorCardData.machinery),
      categories: Set<String>.from(ExecutorCardData.categories),
    );
  }

  /// Принимает ли исполнитель новые заказы в этот день.
  final bool accepting;
  final TimeOfDay? timeFrom;
  final TimeOfDay? timeTo;
  final bool allDay;
  final int radiusIndex;
  final String? location;
  final Set<String> machinery;
  final Set<String> categories;
  final bool clearDayOff;

  DaySettings copyWith({bool? accepting}) => DaySettings(
        accepting: accepting ?? this.accepting,
        timeFrom: timeFrom,
        timeTo: timeTo,
        allDay: allDay,
        radiusIndex: radiusIndex,
        location: location,
        machinery: machinery,
        categories: categories,
      );
}

class _ScheduledOrder {
  const _ScheduledOrder({
    required this.status,
    required this.machinery,
    required this.title,
    required this.rentDate,
    required this.address,
    this.customerId = '1',
    this.customerName = 'Александр Иванов',
    this.customerPhone = '+7 999 123-45-67',
    this.customerEmail,
  });
  final MyOrderStatus status;
  final List<String> machinery;
  final String title;
  final String rentDate;
  final String address;
  final String customerId;
  final String customerName;
  final String customerPhone;

  /// Почта заказчика. Показывается на странице деталей только если
  /// задана — иначе блок «Электронная почта» не отображается.
  final String? customerEmail;

  _ScheduledOrder copyWith({MyOrderStatus? status}) => _ScheduledOrder(
        status: status ?? this.status,
        machinery: machinery,
        title: title,
        rentDate: rentDate,
        address: address,
        customerId: customerId,
        customerName: customerName,
        customerPhone: customerPhone,
        customerEmail: customerEmail,
      );
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late DateTime _selectedDate;
  late DateTime _weekStart;
  late PageController _pageCtrl;

  /// Начальная неделя (для расчёта индекса страницы).
  late DateTime _originWeek;

  /// Явно отмеченные пользователем выходные дни (через оранжевую
  /// кнопку «Отметить нерабочим» внизу). Этот статус означает «я вообще
  /// не работаю в этот день» — отличается от «закрыл приём заказов».
  final Map<DateTime, DayState> _dayStates = {};

  /// Сохранённые параметры дня: включён ли приём заказов, выбранное
  /// время, местоположение/радиус, спецтехника и категории. Заполняется
  /// из «Параметры дня» (карандаш вверху) и из зелёного тумблера
  /// «Приём заказов». При повторном открытии настроек эти значения
  /// подставляются в форму.
  final Map<DateTime, DaySettings> _daySettings = <DateTime, DaySettings>{};

  bool _acceptingOrders = true;

  /// Заказы по дню недели (1=пн..7=вс). Повторяется каждую неделю.
  /// Инстансное поле (не `static const`), чтобы при подтверждении/отказе
  /// в деталях заказа мы могли мутировать статус/удалять элементы и
  /// `setState` отрисовывал актуальный список.
  final Map<int, List<_ScheduledOrder>> _ordersByWeekday = <int, List<_ScheduledOrder>>{
    1: <_ScheduledOrder>[ // понедельник — 3 заказа
      _ScheduledOrder(
        status: MyOrderStatus.pendingConfirmation,
        machinery: ['Автокран', 'Экскаватор'],
        title: 'Земляные работы',
        rentDate: '09:00–12:00',
        address: 'Московская область, Москва, Улица1, д.144',
        customerId: '1',
        customerName: 'Александр Иванов',
      ),
      _ScheduledOrder(
        status: MyOrderStatus.accepted,
        machinery: ['Погрузчик'],
        title: 'Погрузка строительного мусора',
        rentDate: '13:00–16:00',
        address: 'Московская область, Москва, Проспект Мира, д.12',
        customerId: '2',
        customerName: 'Пётр Иванов',
        customerPhone: '+7 999 234-56-78',
        customerEmail: 'petrov.ivanov@example.ru',
      ),
      _ScheduledOrder(
        status: MyOrderStatus.pendingConfirmation,
        machinery: ['Манипулятор'],
        title: 'Доставка бетонных плит',
        rentDate: '17:00–19:00',
        address: 'Московская область, Химки, ул. Ленина, д.5',
        customerId: '3',
        customerName: 'Сергей Петров',
      ),
    ],
    2: <_ScheduledOrder>[ // вторник — 1 заказ
      _ScheduledOrder(
        status: MyOrderStatus.accepted,
        machinery: ['Экскаватор', 'Самосвал'],
        title: 'Копка траншеи под фундамент',
        rentDate: '08:00–17:00',
        address: 'Московская область, Подольск, ул. Кирова, д.88',
        customerId: '4',
        customerName: 'Михаил Смирнов',
        customerPhone: '+7 999 345-67-89',
        customerEmail: 'smirnov@example.ru',
      ),
    ],
    3: <_ScheduledOrder>[], // среда — 0 заказов
    4: <_ScheduledOrder>[ // четверг — 2 заказа
      _ScheduledOrder(
        status: MyOrderStatus.pendingConfirmation,
        machinery: ['Автокран', 'Экскаватор'],
        title: 'Земляные работы',
        rentDate: '09:00–14:00',
        address: 'Московская область, Москва, Улица1, д.144',
        customerId: '5',
        customerName: 'Виктор Новиков',
      ),
      _ScheduledOrder(
        status: MyOrderStatus.accepted,
        machinery: ['Экскаватор', 'Автокран', 'Эвакуатор', 'Манипулятор', 'Автовышка'],
        title: 'Разработка котлована под фундамент',
        rentDate: '15:00–18:00',
        address: 'Московская область, Москва, Улица1, д.144',
        customerId: '6',
        customerName: 'Дмитрий Соколов',
        customerPhone: '+7 999 456-78-90',
      ),
    ],
    5: <_ScheduledOrder>[ // пятница — 1 заказ
      _ScheduledOrder(
        status: MyOrderStatus.pendingConfirmation,
        machinery: ['Автовышка'],
        title: 'Монтаж рекламного баннера',
        rentDate: '10:00–13:00',
        address: 'Москва, ул. Тверская, д.22',
        customerId: '7',
        customerName: 'Андрей Волков',
      ),
    ],
    // 6 суббота, 7 воскресенье — 0 заказов
  };

  static const _monthNames = [
    '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];

  /// Стартовая страница — сегодняшняя неделя. Листать назад нельзя,
  /// вперёд — ровно на год (52 недели).
  static const int _initialPage = 0;

  /// Максимальная страница (включительно): текущая неделя + 52.
  static const int _maxPage = 52;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _weekStart = _mondayOf(_selectedDate);
    _originWeek = _weekStart;
    _pageCtrl = PageController(initialPage: _initialPage);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  DateTime _weekFromPage(int page) =>
      _originWeek.add(Duration(days: (page - _initialPage) * 7));

  List<DateTime> _weekDaysFor(DateTime monday) =>
      List.generate(7, (i) => monday.add(Duration(days: i)));

  void _onPageChanged(int page) {
    final newWeek = _weekFromPage(page);
    setState(() {
      _weekStart = newWeek;
      _selectedDate = newWeek;
      _acceptingOrders = _acceptingFor(_selectedDate);
    });
  }

  /// Принимает ли исполнитель новые заказы в указанный день.
  /// `false`, если день помечен выходным **или** пользователь временно
  /// закрыл приём заказов зелёным тумблером.
  bool _acceptingFor(DateTime d) {
    if (_stateFor(d) == DayState.dayOff) return false;
    return _daySettings[_dateKey(d)]?.accepting ?? true;
  }

  /// Настройки дня: если пользователь уже редактировал этот день — его
  /// сохранённые значения; иначе — дефолт из карточки исполнителя.
  DaySettings _settingsFor(DateTime d) =>
      _daySettings[_dateKey(d)] ?? DaySettings.fromExecutorCard();

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _updateAccepting(DateTime key, bool value) {
    final DaySettings current =
        _daySettings[key] ?? DaySettings.fromExecutorCard();
    _daySettings[key] = current.copyWith(accepting: value);
  }

  DateTime _mondayOf(DateTime d) =>
      d.subtract(Duration(days: d.weekday - 1));

  String get _headerLabel {
    final days = _weekDaysFor(_weekStart);
    final first = days.first;
    final last = days.last;
    if (first.month == last.month) {
      return '${_monthNames[first.month]}, ${first.year}';
    }
    if (first.year == last.year) {
      return '${_monthNames[first.month]}–${_monthNames[last.month]}, ${first.year}';
    }
    return '${_monthNames[first.month]}, ${first.year} – ${_monthNames[last.month]}, ${last.year}';
  }

  DateTime _dateKey(DateTime d) => DateTime(d.year, d.month, d.day);

  DayState _stateFor(DateTime d) {
    final key = _dateKey(d);
    if (_dayStates.containsKey(key)) return _dayStates[key]!;
    final orders = _ordersByWeekday[d.weekday] ?? [];
    return orders.isNotEmpty ? DayState.hasOrders : DayState.noOrders;
  }

  int get _currentPage {
    final double p = _pageCtrl.hasClients ? (_pageCtrl.page ?? _initialPage.toDouble()) : _initialPage.toDouble();
    return p.round();
  }

  void _prevWeek() {
    if (_currentPage <= _initialPage) return;
    _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _nextWeek() {
    if (_currentPage >= _maxPage) return;
    _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _openDaySettings() async {
    final key = _dateKey(_selectedDate);
    final DaySettings initial = _settingsFor(_selectedDate);
    final DaySettings? updated = await Navigator.of(context).push<DaySettings>(
      MaterialPageRoute<DaySettings>(
        builder: (_) => DaySettingsScreen(
          dayLabel: '${_selectedDate.day} ${_monthNames[_selectedDate.month]}, ${_selectedDate.year}',
          initialState: _stateFor(_selectedDate),
          initial: initial,
        ),
      ),
    );
    if (updated == null) return;
    setState(() {
      if (updated.clearDayOff) _dayStates.remove(key);
      _daySettings[key] = updated;
      _acceptingOrders = updated.accepting;
    });
  }

  /// Переключает «выходной» для текущего дня. Если день помечается
  /// нерабочим и на нём уже есть активные заказы — сначала показываем
  /// алерт-предупреждение; по подтверждению все заказы отменяются
  /// (удаляются из графика) и день уходит в `dayOff`.
  Future<void> _toggleDayOff(DayState state) async {
    final DateTime key = _dateKey(_selectedDate);

    if (state == DayState.dayOff) {
      setState(() {
        _dayStates.remove(key);
        _acceptingOrders = _acceptingFor(_selectedDate);
      });
      return;
    }

    final List<_ScheduledOrder> orders =
        _ordersByWeekday[_selectedDate.weekday] ?? <_ScheduledOrder>[];
    if (orders.isNotEmpty) {
      final bool? ok = await ScheduleAlerts.showMarkDayOffWithActiveOrders(
        context,
        ordersCount: orders.length,
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      orders.clear();
      _dayStates[key] = DayState.dayOff;
      _acceptingOrders = false;
    });
  }

  Future<void> _toggleAcceptance(bool value) async {
    if (!value) {
      final bool? ok = await _showCloseDialog();
      if (ok != true) return;
    }
    final key = _dateKey(_selectedDate);
    setState(() {
      _acceptingOrders = value;
      // Зелёный тумблер только открывает/закрывает приём новых
      // заказов. День остаётся рабочим — существующие заказы видны.
      // Пометка «выходной» ставится оранжевой кнопкой ниже.
      _updateAccepting(key, value);
    });
  }

  Future<bool?> _showCloseDialog() {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: 16.w),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.fromLTRB(16.r, 14.r, 16.r, 22.r),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(false),
                  child: Icon(Icons.close_rounded,
                      size: 22.r, color: AppColors.textTertiary),
                ),
              ),
              SizedBox(height: 16.h),
              Text('Закрыть приём заказов?',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700)),
              SizedBox(height: 8.h),
              Text('Новые заказы на этот день поступать не будут',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
              SizedBox(height: 18.h),
              PrimaryButton(
                label: 'Закрыть',
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
              SizedBox(height: 12.h),
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(false),
                child: Center(
                  child: Text('Вернуться',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textPrimary)),
                ),
              ),
              SizedBox(height: 8.h),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DayState state = _stateFor(_selectedDate);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: DarkSubAppBar(
        title: 'Мой график',
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 8.w),
            child: IconButton(
              icon: Image.asset('assets/icons/profile/pen.webp',
                  width: 24.r, height: 24.r),
              onPressed: _openDaySettings,
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 88.h),
        child: AiAssistantFab(onTap: () => context.push('/assistant/chat')),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 16.h),
            // Заголовок месяца
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _headerLabel,
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: _currentPage <= _initialPage ? 0.35 : 1.0,
                    child: GestureDetector(
                      onTap: _prevWeek,
                      child: Padding(
                        padding: EdgeInsets.all(4.r),
                        child: Image.asset('assets/icons/profile/arrow_left_calendar.webp',
                            width: 24.r, height: 24.r),
                      ),
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Opacity(
                    opacity: _currentPage >= _maxPage ? 0.35 : 1.0,
                    child: GestureDetector(
                      onTap: _nextWeek,
                      child: Padding(
                        padding: EdgeInsets.all(4.r),
                        child: Image.asset('assets/icons/profile/arrow_right_calendar.webp',
                            width: 24.r, height: 24.r),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            // Дни недели
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                children: ['п', 'в', 'с', 'ч', 'п', 'с', 'в']
                    .map((w) => Expanded(
                          child: Center(
                            child: Text(w,
                                style: AppTextStyles.subBody
                                    .copyWith(color: AppColors.textTertiary, fontWeight: FontWeight.w400)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            SizedBox(height: 6.h),
            // Одна неделя — свайпаемая
            SizedBox(
              height: 44.h,
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: _onPageChanged,
                itemCount: _maxPage + 1,
                itemBuilder: (_, page) {
                  final monday = _weekFromPage(page);
                  final days = _weekDaysFor(monday);
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: Row(
                      children: days.map((day) {
                        final bool selected = _dateKey(day) == _dateKey(_selectedDate);
                        final DayState s = _stateFor(day);
                        // Дни раньше сегодняшнего неактивны — эту часть
                        // недели показываем для календарного контекста,
                        // но переключаться на них нельзя (графика в
                        // прошлое не ведём).
                        final bool isPast =
                            _dateKey(day).isBefore(_dateKey(DateTime.now()));
                        Color? bg;
                        Color textColor =
                            isPast ? AppColors.textTertiary : AppColors.textPrimary;
                        if (selected) {
                          bg = AppColors.primary;
                          textColor = Colors.white;
                        } else if (s == DayState.dayOff) {
                          bg = const Color(0xFFEB4E3D);
                          textColor = Colors.white;
                        }
                        return Expanded(
                          child: GestureDetector(
                            onTap: isPast
                                ? null
                                : () => setState(() {
                                      _selectedDate = day;
                                      _acceptingOrders = _acceptingFor(day);
                                    }),
                            behavior: HitTestBehavior.opaque,
                            child: Center(
                              child: Container(
                                width: 36.r,
                                height: 36.r,
                                decoration: BoxDecoration(
                                  color: bg,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text('${day.day}',
                                    style: AppTextStyles.bodyL.copyWith(color: textColor)),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 12.h),
            if (state != DayState.dayOff) ...[
              if (_acceptingOrders)
                _DaySettingsStrip(settings: _settingsFor(_selectedDate), fmtTime: _fmtTime),
              Divider(height: 1, thickness: 0.5, color: Colors.grey.shade300),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Приём заказов',
                          style: AppTextStyles.button),
                    ),
                    ScheduleToggle(
                      value: _acceptingOrders,
                      onChanged: _toggleAcceptance,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 0.5, color: Colors.grey.shade300),
            ],
            // Контент дня
            Expanded(child: _buildDayBody(state)),
            // Кнопка с тенью
            Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    offset: const Offset(0, -1),
                    blurRadius: 8,
                  ),
                ],
              ),
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
              child: PrimaryButton(
                label: state == DayState.dayOff
                    ? 'Отметить рабочим'
                    : 'Отметить нерабочим',
                onPressed: () => _toggleDayOff(state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayBody(DayState state) {
    if (state == DayState.dayOff) {
      return Padding(
        padding: EdgeInsets.only(bottom: 40.h),
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w),
            child: Text(
              'Вы отметили этот день выходным — заказы на него не принимаются',
              style: AppTextStyles.body.copyWith(color: AppColors.textPrimary, height: 1.3),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final orders = _ordersByWeekday[_selectedDate.weekday] ?? [];
    if (orders.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: 40.h),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/icons/profile/no_orders.webp',
                  width: 80.r, height: 80.r),
                SizedBox(height: 12.h),
                Text('Нет заказов',
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.textPrimary)),
              ],
            ),
          ),
        );
    }

    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      itemCount: orders.length,
      separatorBuilder: (_, _) => Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Divider(height: 1, thickness: 1, color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      itemBuilder: (_, i) => _OrderCard(
        order: orders[i],
        date: _selectedDate,
        onConfirm: () => _confirmOrder(orders[i]),
        onRemove: () => _removeOrder(orders[i]),
      ),
    );
  }

  /// Подтверждение заказа — статус меняется с `pendingConfirmation`
  /// на `accepted`. Исполнитель ответил «Подтвердить» в деталях заказа.
  void _confirmOrder(_ScheduledOrder order) {
    final List<_ScheduledOrder>? list = _ordersByWeekday[_selectedDate.weekday];
    if (list == null) return;
    final int idx = list.indexOf(order);
    if (idx < 0) return;
    setState(() {
      list[idx] = order.copyWith(status: MyOrderStatus.accepted);
    });
  }

  /// Удаление заказа из дня — вызывается при «Отклонить» /
  /// «Отказаться» / «Отозвать отклик» в деталях заказа. Заказ больше
  /// не на исполнителе, поэтому из графика его убираем.
  void _removeOrder(_ScheduledOrder order) {
    final List<_ScheduledOrder>? list = _ordersByWeekday[_selectedDate.weekday];
    if (list == null) return;
    setState(() => list.remove(order));
  }
}

class ScheduleToggle extends StatelessWidget {
  const ScheduleToggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final double w = 52.r;
    final double h = 32.r;
    final double thumb = 28.r;
    final double pad = 2.r;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(h / 2),
          color: value ? AppColors.toggleOn : AppColors.toggleOff,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: thumb,
            height: thumb,
            margin: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.date,
    required this.onConfirm,
    required this.onRemove,
  });
  final _ScheduledOrder order;
  final DateTime date;

  static const List<String> _monthsGen = [
    '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  String get _fullDate => '${date.day} ${_monthsGen[date.month]} · ${order.rentDate}';

  /// Подтверждение заказа («Подтвердить» в деталях) — статус в графике
  /// должен смениться на `accepted` («Свяжитесь с заказчиком»).
  final VoidCallback onConfirm;

  /// Удаление заказа из графика — когда исполнитель «Отклонил» /
  /// «Отказался» / «Отозвал отклик».
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final TextStyle tagStyle = TextStyle(
      fontFamily: 'Roboto',
      fontSize: 12.sp,
      fontWeight: FontWeight.w400,
      color: AppColors.textTertiary,
      height: 1.78,
    );
    final detailState = order.status == MyOrderStatus.pendingConfirmation
        ? MyOrderDetailState.waitingConfirm
        : MyOrderDetailState.confirmed;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MyOrderDetailScreen(
            title: order.title,
            equipment: order.machinery,
            rentDate: _fullDate,
            address: order.address,
            state: detailState,
            customerId: order.customerId,
            customerName: order.customerName,
            customerPhone: order.customerPhone,
            customerEmail: order.customerEmail,
            onConfirm: onConfirm,
            onDecline: onRemove,
            onRefuse: onRemove,
            onWithdraw: onRemove,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrderStatusPill(status: order.status),
        SizedBox(height: 6.h),
        Text(
          order.machinery.join('   '),
          style: tagStyle,
        ),
        SizedBox(height: 8.h),
        Text(
          order.title,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 17.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 8.h),
        _LabelLine(label: 'Дата аренды:', value: _fullDate),
        SizedBox(height: 5.h),
        _LabelLine(label: 'Адрес:', value: order.address, underlined: true),
        ],
      ),
    );
  }
}

/// Блок под тогглом «Приём заказов» — чипы техники, время работы, радиус.
/// Берёт данные из сохранённых параметров дня ([DaySettings]).
class _DaySettingsStrip extends StatelessWidget {
  const _DaySettingsStrip({
    required this.settings,
    required this.fmtTime,
  });

  final DaySettings settings;
  final String Function(TimeOfDay) fmtTime;

  @override
  Widget build(BuildContext context) {
    final bool hasMachinery = settings.machinery.isNotEmpty;
    final bool hasTime =
        settings.allDay || (settings.timeFrom != null && settings.timeTo != null);
    final bool hasRadius = settings.radiusIndex >= 0 &&
        settings.radiusIndex < DaySettings.radiusOptions.length;

    if (!hasMachinery && !hasTime && !hasRadius) return const SizedBox.shrink();

    final String radiusLabel = hasRadius
        ? 'Заказы ${DaySettings.radiusOptions[settings.radiusIndex][0].toLowerCase()}'
            '${DaySettings.radiusOptions[settings.radiusIndex].substring(1)}'
        : '';

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 4.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (hasMachinery) ...<Widget>[
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: settings.machinery
                  .map((String m) => Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.primary, width: 1),
                          borderRadius: BorderRadius.circular(100.r),
                        ),
                        child: Text(
                          m,
                          style: AppTextStyles.chip.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ))
                  .toList(),
            ),
            SizedBox(height: 10.h),
          ],
          if (hasTime) ...<Widget>[
            Text(
              settings.allDay
                  ? 'Весь день'
                  : 'С ${fmtTime(settings.timeFrom!)} до ${fmtTime(settings.timeTo!)}',
              style: AppTextStyles.body.copyWith(fontSize: 14.sp),
            ),
            SizedBox(height: 10.h),
          ],
          if (hasRadius)
            Text(
              radiusLabel,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textTertiary),
            ),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }
}

class _LabelLine extends StatelessWidget {
  const _LabelLine({
    required this.label,
    required this.value,
    this.underlined = false,
  });
  final String label;
  final String value;
  final bool underlined;

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 13.sp,
          color: AppColors.textPrimary,
          height: 1.4,
        ),
        children: <TextSpan>[
          TextSpan(
            text: '$label ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
              decoration: underlined ? TextDecoration.underline : TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

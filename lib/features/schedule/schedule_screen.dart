import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/features/schedule/day_settings_screen.dart';
import 'package:dispatcher_1/features/schedule/widgets/day_chip.dart';

/// Состояние конкретного дня графика.
enum DayState { noOrders, hasOrders, dayOff }

/// Модель дня графика для главного экрана.
class ScheduleDay {
  const ScheduleDay({
    required this.date,
    required this.weekday,
    required this.state,
  });

  final String date; // например «07»
  final String weekday; // «пн», «вт», ...
  final DayState state;
}

/// Заказ в выбранном дне графика (mock).
class _ScheduledOrder {
  const _ScheduledOrder({
    required this.time,
    required this.title,
    required this.address,
  });

  final String time;
  final String title;
  final String address;
}

/// Главный экран «Мой график» — горизонтальный список из 7 дней.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  // По умолчанию все дни рабочие, без заказов.
  late List<ScheduleDay> _days;
  int _selectedIndex = 0;

  static const List<String> _weekdays = [
    'пн',
    'вт',
    'ср',
    'чт',
    'пт',
    'сб',
    'вс',
  ];

  // Mock-заказы для второго дня (демонстрация состояния «с заказами»).
  static const List<_ScheduledOrder> _mockOrders = [
    _ScheduledOrder(
      time: '09:00 — 13:00',
      title: 'Рытьё котлована',
      address: 'г. Москва, ул. Ленина, 12',
    ),
    _ScheduledOrder(
      time: '14:00 — 18:00',
      title: 'Перевозка груза',
      address: 'г. Москва, Профсоюзная, 45',
    ),
  ];

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _days = List<ScheduleDay>.generate(7, (i) {
      final DateTime d = now.add(Duration(days: i));
      return ScheduleDay(
        date: d.day.toString().padLeft(2, '0'),
        weekday: _weekdays[(d.weekday - 1) % 7],
        // Демонстрационные состояния: 1-й день — с заказами, 4-й — выходной.
        state: i == 1
            ? DayState.hasOrders
            : (i == 4 ? DayState.dayOff : DayState.noOrders),
      );
    });
  }

  Future<void> _openDaySettings() async {
    final ScheduleDay day = _days[_selectedIndex];
    final DayState? updated = await Navigator.of(context).push<DayState>(
      MaterialPageRoute<DayState>(
        builder: (_) => DaySettingsScreen(
          dayLabel: '${day.date} ${day.weekday}',
          initialState: day.state,
        ),
      ),
    );
    if (updated != null) {
      setState(() {
        _days[_selectedIndex] = ScheduleDay(
          date: day.date,
          weekday: day.weekday,
          state: updated,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ScheduleDay current = _days[_selectedIndex];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Мой график',
          style: AppTextStyles.titleS.copyWith(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_outlined, color: Colors.white, size: 24.r),
            onPressed: _openDaySettings,
            tooltip: 'Параметры дня',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 80.h,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: _days.length,
              separatorBuilder: (_, _) => SizedBox(width: AppSpacing.sm),
              itemBuilder: (_, i) {
                final ScheduleDay d = _days[i];
                return DayChip(
                  day: d.date,
                  weekday: d.weekday,
                  selected: i == _selectedIndex,
                  dayOff: d.state == DayState.dayOff,
                  onTap: () => setState(() => _selectedIndex = i),
                );
              },
            ),
          ),
          SizedBox(height: AppSpacing.lg),
          Expanded(child: _buildDayBody(current)),
        ],
      ),
    );
  }

  Widget _buildDayBody(ScheduleDay day) {
    switch (day.state) {
      case DayState.hasOrders:
        return ListView.separated(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          itemCount: _mockOrders.length,
          separatorBuilder: (_, _) => SizedBox(height: AppSpacing.sm),
          itemBuilder: (_, i) => _OrderTile(order: _mockOrders[i]),
        );
      case DayState.dayOff:
        return _EmptyState(
          icon: Icons.beach_access_outlined,
          title: 'Выходной',
          subtitle:
              'Вы отметили этот день\nвыходным — заказы на него не принимаются',
        );
      case DayState.noOrders:
        return _EmptyState(
          icon: Icons.event_available_outlined,
          title: 'Нет заказов',
          subtitle: 'Новые заказы на этот день появятся здесь',
        );
    }
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final _ScheduledOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(order.time, style: AppTextStyles.captionBold.copyWith(
            color: AppColors.primary,
          )),
          SizedBox(height: AppSpacing.xxs),
          Text(order.title, style: AppTextStyles.titleS),
          SizedBox(height: AppSpacing.xxs),
          Text(
            order.address,
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96.w,
              height: 96.w,
              decoration: const BoxDecoration(
                color: AppColors.primaryTint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44.sp, color: AppColors.primary),
            ),
            SizedBox(height: AppSpacing.lg),
            Text(title, style: AppTextStyles.h3, textAlign: TextAlign.center),
            SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';

import 'widgets/service_card.dart';

/// Статические данные моковых услуг (для доступа из других экранов).
class ServiceData {
  ServiceData._();

  static const int maxServices = 30;

  static final List<ServiceMock> services = [];

  /// Полный сброс списка услуг — для logout. У следующего пользователя
  /// на этом устройстве не должно быть услуг предыдущего.
  static void clear() {
    services.clear();
  }

  static const List<ServiceMock> presets = [
    ServiceMock(
      id: '1',
      title: 'Экскаватор для земляных работ',
      categories: ['Земляные работы', 'Погрузочно-разгрузочные работы'],
      machinery: ['Экскаватор'],
      pricePerHour: '1 000',
      pricePerDay: '14 000',
      minOrder: '4',
      description:
          'Экскаватор для земляных работ. Копка траншей, разработка котлованов, выравнивание участка. '
          'Работаю аккуратно, соблюдаю сроки. Возможен выезд в ближайшие районы.',
    ),
    ServiceMock(
      id: '2',
      title: 'Самосвал для вывоза грунта',
      categories: ['Земляные работы', 'Перевозка материалов'],
      machinery: ['Самосвал'],
      pricePerHour: '3 000',
      pricePerDay: '7 000',
      minOrder: '2',
      description:
          'Вывоз грунта, мусора и сыпучих материалов. '
          'Работаю быстро, без задержек. Возможен выезд в ближайшие районы.',
    ),
    ServiceMock(
      id: '3',
      title: 'Работы на высоте',
      categories: ['Высотные работы', 'Строительные работы'],
      machinery: ['Автовышка', 'Автокран'],
      pricePerHour: '5 000',
      pricePerDay: '15 000',
      minOrder: '3',
      description:
          'Работы на высоте: монтаж, обслуживание, обрезка деревьев. '
          'Техника исправна, работаю аккуратно.',
    ),
  ];
}

class ServiceMock {
  const ServiceMock({
    required this.id,
    required this.title,
    required this.categories,
    required this.machinery,
    required this.pricePerHour,
    required this.pricePerDay,
    required this.minOrder,
    required this.description,
    this.photos = const [],
    this.address,
    this.radiusIndex = -1,
  });
  final String id;
  final String title;
  final List<String> categories;
  final List<String> machinery;
  final String pricePerHour;
  final String pricePerDay;
  final String minOrder;
  final String description;
  final List<String> photos;
  final String? address;
  final int radiusIndex;
}

/// Экран «Мои услуги» — список услуг исполнителя или пустое состояние.
class MyServicesScreen extends StatefulWidget {
  const MyServicesScreen({super.key});

  @override
  State<MyServicesScreen> createState() => _MyServicesScreenState();
}

class _MyServicesScreenState extends State<MyServicesScreen> {
  bool get _isEmpty => ServiceData.services.isEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Мои услуги'),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 88.h),
        child: AiAssistantFab(onTap: () => context.push('/assistant/chat')),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isEmpty
                  ? const _EmptyState()
                  : _ServicesList(
                      items: ServiceData.services,
                      onRefresh: () => setState(() {}),
                    ),
            ),
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
                label: 'Создать услугу',
                onPressed: () async {
                  if (ServiceData.services.length >= ServiceData.maxServices) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Достигнут лимит ${ServiceData.maxServices} услуг. '
                          'Удалите ненужные, чтобы добавить новые.',
                        ),
                      ),
                    );
                    return;
                  }
                  await context.push('/services/create');
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServicesList extends StatelessWidget {
  const _ServicesList({required this.items, required this.onRefresh});
  final List<ServiceMock> items;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
      itemCount: items.length,
      separatorBuilder: (_, _) => SizedBox(height: 8.h),
      itemBuilder: (context, index) {
        final item = items[index];
        // Каждая карточка — контейнер с мягкой оранжевой заливкой
        // (`AppColors.fieldFill`). Визуально делит список на «плитки»
        // — так же, как в приложении заказчика (`_ServiceTile` в
        // `catalog/order_detail_screen.dart`).
        return Container(
          decoration: BoxDecoration(
            color: AppColors.fieldFill,
            borderRadius: BorderRadius.circular(14.r),
          ),
          clipBehavior: Clip.antiAlias,
          child: ServiceCard(
            title: item.title,
            machinery: item.machinery,
            description: item.description,
            pricePerHour: item.pricePerHour,
            pricePerDay: item.pricePerDay,
            onTap: () async {
              await context.push('/services/${item.id}');
              onRefresh();
            },
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Здесь появятся ваши услуги',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8.h),
            Text(
              'Создайте услугу\nи начните получать заказы',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16.sp,
                fontWeight: FontWeight.w400,
                height: 1.3,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

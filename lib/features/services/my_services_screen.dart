import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/ai/ai_navigation.dart';
import 'package:dispatcher_1/core/my_services/models.dart';
import 'package:dispatcher_1/core/my_services/my_services_service.dart';
import 'package:dispatcher_1/core/settings/settings_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';

import 'widgets/service_card.dart';
import 'widgets/service_paywall.dart';

/// Тонкий кэш-адаптер над [MyServicesService] для кода, который ещё
/// не переписан напрямую на сервис (карточка исполнителя, детали заказа
/// в "Моих заказах", логика цен в мэтче). После переноса этих экранов
/// на БД адаптер можно удалить.
class ServiceData {
  ServiceData._();

  static const int maxServices = 30;

  /// Закэшированный список услуг из БД (обновляется [refresh]).
  /// Сохраняет сигнатуру старого [ServiceMock], чтобы не ломать
  /// вызовы из экранов, которые пока на моках.
  static final List<ServiceMock> services = <ServiceMock>[];

  /// Слушатель — для `ListenableBuilder`-ов, которые хотят перерисоваться
  /// после refresh.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Маячок «пришло решение по документам услуги» (пуш с route `/services`).
  /// Отдельный от [revision]: тот инкрементится самим [refresh], а этот — только
  /// из обработчика пушей, чтобы открытый экран «Мои услуги» перечитал список
  /// без перезахода и без риска зациклиться на собственном refresh.
  static final ValueNotifier<int> changeBeacon = ValueNotifier<int>(0);

  /// Полная перезагрузка из БД. Вызывается при открытии "Моих услуг",
  /// после create/update/archive, а также из мест, где старый код
  /// ждёт актуальный snapshot перед чтением (например, вычисление
  /// `ExecutorCardData.machinery`).
  static Future<void> refresh() async {
    final List<MyServiceSummary> rows =
        await MyServicesService.instance.listMine();
    services
      ..clear()
      ..addAll(rows.map(_toMock));
    revision.value = revision.value + 1;
  }

  /// Сброс кэша при logout/deleteAccount. В БД данные остаются
  /// (они собственность executor_id = auth.uid() прошлой сессии).
  static void clear() {
    services.clear();
    revision.value = revision.value + 1;
  }

  static ServiceMock _toMock(MyServiceSummary s) => ServiceMock(
        id: s.id,
        title: s.title,
        categories: s.categoryTitles,
        machinery: s.machineryTitles,
        pricePerHour: _formatPrice(s.pricePerHour),
        pricePerDay: _formatPrice(s.pricePerDay),
        minOrder: s.minHours?.toString() ?? '',
        description: s.description ?? '',
        isPaid: s.isPaid,
        verificationStatus: s.verificationStatus,
      );

  static String _formatPrice(double? v) {
    if (v == null) return '';
    final int i = v.round();
    final String s = i.toString();
    // Простой пробельный разделитель тысяч: "14000" → "14 000".
    final StringBuffer b = StringBuffer();
    final int n = s.length;
    for (int k = 0; k < n; k++) {
      if (k > 0 && (n - k) % 3 == 0) b.write(' ');
      b.write(s[k]);
    }
    return b.toString();
  }

  /// Пресеты с примерами техники/категорий для экрана «График». Цены
  /// в них больше не используются — на экране деталей мэтча цена
  /// берётся напрямую из `order_matches.agreed_*` (снапшот в момент
  /// мэтча). Поля `pricePerHour`/`pricePerDay` оставлены, чтобы не
  /// плодить параллельный тип ради одной ситуации.
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
      machinery: ['Автовышка'],
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
    this.isPaid = true,
    this.verificationStatus = 'approved',
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

  /// `false` для услуг, у которых ещё не прошла оплата `service_slot`.
  /// Такие услуги не показываются в каталоге (`is_paid=true` фильтр) и
  /// не съедают лимит [ServiceData.maxServices], но юзер видит их в
  /// «Моих услугах» с подписью «не оплачена».
  final bool isPaid;

  /// Статус проверки документов услуги ('none'|'pending'|'approved'|
  /// 'rejected'). Влияет на карточку только в режиме «документы при
  /// каждой публикации» (серверный флаг perServiceDocs).
  final String verificationStatus;
}

/// Экран «Мои услуги» — список услуг исполнителя или пустое состояние.
class MyServicesScreen extends StatefulWidget {
  const MyServicesScreen({super.key});

  @override
  State<MyServicesScreen> createState() => _MyServicesScreenState();
}

class _MyServicesScreenState extends State<MyServicesScreen> {
  late Future<void> _initial;

  /// Режим «документы при каждой публикации» (серверный флаг). Пока
  /// выключен — карточки выглядят и ведут себя как раньше.
  bool _docsMode = false;

  @override
  void initState() {
    super.initState();
    _initial = ServiceData.refresh();
    // ignore: discarded_futures
    SettingsService.instance.perServiceDocs().then((bool v) {
      if (mounted && v) setState(() => _docsMode = true);
    });
    // Пуш «решение по документам услуги» бьёт по этому маячку — перечитываем
    // список, чтобы статус услуги («на проверке» → «одобрено»/«отклонено»)
    // обновился на открытом экране без перезахода.
    ServiceData.changeBeacon.addListener(_onDocsBeacon);
  }

  @override
  void dispose() {
    ServiceData.changeBeacon.removeListener(_onDocsBeacon);
    super.dispose();
  }

  void _onDocsBeacon() {
    // ignore: discarded_futures
    ServiceData.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _reload() async {
    await ServiceData.refresh();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Мои услуги'),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 88.h),
        child: AiAssistantFab(onTap: () => openAssistantChat(context)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _initial,
          builder: (BuildContext context, AsyncSnapshot<void> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ServicesError(onRetry: () => setState(() {
                    _initial = ServiceData.refresh();
                  }));
            }
            return Column(
              children: <Widget>[
                Expanded(
                  child: ServiceData.services.isEmpty
                      ? const _EmptyState()
                      : _ServicesList(
                          items: ServiceData.services,
                          onRefresh: _reload,
                          docsMode: _docsMode,
                        ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    boxShadow: <BoxShadow>[
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
                      // Лимит считаем только по оплаченным услугам:
                      // неоплаченные занимают строку в БД, но не активны
                      // в каталоге и не должны съедать слот.
                      final int paidCount = ServiceData.services
                          .where((ServiceMock s) => s.isPaid)
                          .length;
                      if (paidCount >= ServiceData.maxServices) {
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
                      // Сначала юзер заполняет форму, потом — оплата
                      // конкретной услуги через `/subscription/payment`
                      // с `kind=service_slot, serviceId=<id>`. Раньше тут
                      // был ServicePaywall с моком — заглушка не списывала
                      // деньги, услуга сразу шла в is_paid=true.
                      await context.push('/services/create');
                      if (mounted) await _reload();
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ServicesError extends StatelessWidget {
  const _ServicesError({required this.onRetry});
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
              'Не удалось загрузить услуги',
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

class _ServicesList extends StatelessWidget {
  const _ServicesList({
    required this.items,
    required this.onRefresh,
    this.docsMode = false,
  });
  final List<ServiceMock> items;
  final VoidCallback onRefresh;

  /// Режим «документы при каждой публикации»: оплаченная услуга без
  /// одобренных документов не активна в каталоге — карточка ведёт на
  /// экран подачи документов и помечается бейджем статуса.
  final bool docsMode;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
      itemCount: items.length,
      separatorBuilder: (_, _) => SizedBox(height: 8.h),
      itemBuilder: (context, index) {
        final item = items[index];
        // Нужен ли услуге шаг с документами (только в режиме docsMode,
        // только после оплаты — до оплаты приоритетнее бейдж «Не оплачена»).
        final bool needsDocs = docsMode &&
            item.isPaid &&
            (item.verificationStatus == 'none' ||
                item.verificationStatus == 'rejected');
        final bool onReview =
            docsMode && item.isPaid && item.verificationStatus == 'pending';
        // Каждая карточка — контейнер с мягкой оранжевой заливкой
        // (`AppColors.fieldFill`). Визуально делит список на «плитки»
        // — так же, как в приложении заказчика (`_ServiceTile` в
        // `catalog/order_detail_screen.dart`).
        final Widget card = Container(
          decoration: BoxDecoration(
            color: AppColors.fieldFill,
            borderRadius: BorderRadius.circular(14.r),
          ),
          clipBehavior: Clip.antiAlias,
          child: ServiceCard(
            title: item.title,
            machinery: item.machinery,
            pricePerHour: item.pricePerHour,
            pricePerDay: item.pricePerDay,
            minOrder: item.minOrder,
            onTap: () async {
              if (!item.isPaid) {
                // Неоплаченная услуга — paywall «Оплатите размещение
                // услуги» с фоном-картинкой и шторкой выбора способа
                // оплаты. Раньше уводили сразу на голую шторку
                // `/subscription/payment` без paywall'а — фон был
                // чёрным, выглядело сломанным.
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => ServicePaywall(serviceId: item.id),
                  ),
                );
                onRefresh();
                return;
              }
              if (needsDocs) {
                // Оплачена, но без документов (или их отклонили) —
                // сразу на экран подачи, там же видна причина отказа.
                await context.push('/services/${item.id}/docs');
                onRefresh();
                return;
              }
              await context.push('/services/${item.id}');
              onRefresh();
            },
          ),
        );

        // Бейдж поверх карточки (в правом верхнем углу).
        Widget badged({
          required String label,
          required Color color,
          bool dimmed = false,
        }) {
          return Stack(
            children: <Widget>[
              dimmed ? Opacity(opacity: 0.55, child: card) : card,
              Positioned(
                top: 8.h,
                right: 8.w,
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                  ),
                  child: Text(
                    label,
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        if (!item.isPaid) {
          // Бренд-цвет вместо красного: «Не оплачена» — это CTA
          // «оплатите», а не ошибка/опасность.
          return badged(
              label: 'Не оплачена', color: AppColors.primary, dimmed: true);
        }
        if (needsDocs) {
          return item.verificationStatus == 'rejected'
              ? badged(
                  label: 'Документы отклонены',
                  color: AppColors.error,
                  dimmed: true)
              : badged(
                  label: 'Приложите документы',
                  color: AppColors.primary,
                  dimmed: true);
        }
        if (onReview) {
          return badged(
              label: 'Документы на проверке', color: AppColors.textTertiary);
        }
        return card;
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
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

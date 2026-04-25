import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/catalog/catalog_service.dart';
import 'package:dispatcher_1/core/catalog/format.dart';
import 'package:dispatcher_1/core/catalog/models.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/clickable_address.dart';
import 'package:dispatcher_1/core/widgets/customer_header.dart';
import 'package:dispatcher_1/core/widgets/labeled_section.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/customer_card_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/widgets/respond_bottom_sheet.dart';
import 'package:dispatcher_1/features/profile/reviews_screen.dart';

/// Карточка заказа (детали). Данные — из `public.orders` через
/// [CatalogService.getOrderDetail]. Состояние "уже откликнулся" —
/// тоже из БД (наличие не-терминального `order_matches` для этого
/// executor_id+order_id).
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.multipleEquipment = false,
    this.fromCustomerCard = false,
  });

  final String orderId;
  final bool multipleEquipment;

  /// Экран открыт тапом по заказу из карточки заказчика. В таком случае
  /// блок заказчика в шапке ведёт не на новый push `CustomerCardScreen`,
  /// а на pop обратно — чтобы избежать бесконечной цепочки «заказ →
  /// заказчик → заказ → заказчик → ...» в стеке навигации.
  final bool fromCustomerCard;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Future<_OrderScreenData> _future;

  // Локальный флаг: только что сделали отклик в этой сессии экрана.
  // Доп. к тому, что приехало из БД в начальной загрузке.
  bool _justResponded = false;
  bool _responding = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_OrderScreenData> _load() async {
    final CatalogService svc = CatalogService.instance;
    final List<dynamic> results = await Future.wait<dynamic>(<Future<dynamic>>[
      svc.getOrderDetail(widget.orderId),
      svc.hasActiveMatchForOrder(widget.orderId),
    ]);
    final OrderDetail? order = results[0] as OrderDetail?;
    final bool hasMatch = results[1] as bool;
    return _OrderScreenData(order: order, alreadyResponded: hasMatch);
  }

  Future<void> _onRespondTap(OrderDetail order) async {
    if (_responding) return;
    setState(() => _responding = true);
    try {
      final CatalogService svc = CatalogService.instance;
      final Map<String, String> myServices =
          await svc.listMyActiveServicesByMachinery();
      // Пересечение техники заказа с моими услугами.
      final List<String> availableEquipment = order.machineryTitles
          .where((String t) => myServices.containsKey(t))
          .toList();
      if (availableEquipment.isEmpty) {
        if (!mounted) return;
        setState(() => _responding = false);
        await showDialog<void>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.35),
          builder: (_) => _NoMatchingMachineryDialog(),
        );
        return;
      }

      String pickedMachinery;
      if (availableEquipment.length == 1) {
        pickedMachinery = availableEquipment.first;
      } else {
        if (!mounted) return;
        // Sheet поддерживает мультивыбор, но в БД один отклик = одна услуга.
        // Берём первую выбранную технику.
        final List<String>? picked =
            await showModalBottomSheet<List<String>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => PickEquipmentSheet(options: availableEquipment),
        );
        if (picked == null || picked.isEmpty || !mounted) {
          setState(() => _responding = false);
          return;
        }
        pickedMachinery = picked.first;
      }

      final String? serviceId = myServices[pickedMachinery];
      if (serviceId == null) {
        if (!mounted) return;
        setState(() => _responding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось найти услугу для выбранной техники.')),
        );
        return;
      }

      await svc.respondToOrder(orderId: widget.orderId, serviceId: serviceId);
      if (!mounted) return;
      setState(() {
        _justResponded = true;
        _responding = false;
      });
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) => RespondModalDialog(verified: true),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _responding = false);
      // Уникальный индекс на (order_id, executor_id) при не-completed
      // статусах — повторный отклик = дубликат.
      if (e.code == '23505') {
        setState(() => _justResponded = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вы уже отправляли отклик на этот заказ.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отправить отклик: ${e.message}')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _responding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отправить отклик.')),
      );
    }
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
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
            icon: Padding(
              padding: EdgeInsets.only(left: 8.w),
              child: Image.asset(
                'assets/icons/ui/back_arrow.webp',
                width: 24.r,
                height: 24.r,
                fit: BoxFit.contain,
              ),
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Padding(
          padding: EdgeInsets.only(top: 2.h),
          child: FutureBuilder<_OrderScreenData>(
            future: _future,
            builder: (BuildContext context,
                AsyncSnapshot<_OrderScreenData> snap) {
              final String title = snap.data?.order?.title ?? 'Заказ';
              return Text(
                title,
                style: AppTextStyles.titleS.copyWith(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              );
            },
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 88.h),
        child: AiAssistantFab(
          onTap: () => context.push('/assistant/chat'),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: FutureBuilder<_OrderScreenData>(
        future: _future,
        builder: (BuildContext context,
            AsyncSnapshot<_OrderScreenData> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _DetailError(
              onRetry: () => setState(() {
                _future = _load();
              }),
            );
          }
          final _OrderScreenData? data = snap.data;
          final OrderDetail? order = data?.order;
          if (data == null || order == null) {
            return _OrderNotFound();
          }
          final bool alreadyResponded =
              data.alreadyResponded || _justResponded;
          return _OrderDetailBody(
            order: order,
            alreadyResponded: alreadyResponded,
            responding: _responding,
            fromCustomerCard: widget.fromCustomerCard,
            onRespond: () => _onRespondTap(order),
          );
        },
      ),
    );
  }
}

class _OrderScreenData {
  const _OrderScreenData({required this.order, required this.alreadyResponded});
  final OrderDetail? order;
  final bool alreadyResponded;
}

class _OrderDetailBody extends StatelessWidget {
  const _OrderDetailBody({
    required this.order,
    required this.alreadyResponded,
    required this.responding,
    required this.fromCustomerCard,
    required this.onRespond,
  });

  final OrderDetail order;
  final bool alreadyResponded;
  final bool responding;
  final bool fromCustomerCard;
  final VoidCallback onRespond;

  @override
  Widget build(BuildContext context) {
    final String rentDate = formatRentDate(_asListItem(order));
    final String publishedAgo = formatPublishedAgo(order.publishedAt);
    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CustomerHeader(
                  name: order.customer.name,
                  avatarUrl: order.customer.avatarUrl,
                  rating: order.customer.ratingAsCustomer,
                  reviews: order.customer.reviewCountAsCustomer,
                  onTap: fromCustomerCard
                      ? () => Navigator.of(context).maybePop()
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CustomerCardScreen(
                                customerId: order.customer.id,
                              ),
                            ),
                          ),
                  onReviewsTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReviewsScreen(
                        subject: ReviewSubject.customer,
                        initialRating: order.customer.ratingAsCustomer,
                        initialCount: order.customer.reviewCountAsCustomer,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 10.h),
                Text('№${order.displayNumber.toString().padLeft(6, '0')}',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textTertiary)),
                SizedBox(height: 4.h),
                Text(order.title,
                    style: AppTextStyles.titleL.copyWith(height: 1.2)),
                SizedBox(height: 7.h),
                Text(publishedAgo,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textTertiary)),
                SizedBox(height: 11.h),
                LabeledSection(
                  title: 'Дата и время аренды',
                  child: Text(rentDate,
                      style: AppTextStyles.subBody
                          .copyWith(fontWeight: FontWeight.w400)),
                ),
                LabeledSection(
                  title: 'Адрес',
                  child: ClickableAddress(
                    order.address,
                    baseStyle: AppTextStyles.subBody
                        .copyWith(fontWeight: FontWeight.w400),
                  ),
                ),
                LabeledSection(
                  title: 'Требуемая спецтехника',
                  child: Wrap(
                    spacing: 8.w,
                    runSpacing: 8.h,
                    children: order.machineryTitles
                        .map((String e) => _OutlinedChip(label: e))
                        .toList(),
                  ),
                ),
                if (order.categoryTitles.isNotEmpty)
                  LabeledSection(
                    title: 'Категория работ',
                    child: Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: order.categoryTitles
                          .map((String c) => _OutlinedChip(label: c))
                          .toList(),
                    ),
                  ),
                if (order.works.isNotEmpty)
                  LabeledSection(
                    title: 'Характер работ',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: order.works
                          .map((WorkItem w) => Text(
                                _formatWorkItem(w),
                                style: AppTextStyles.subBody
                                    .copyWith(fontWeight: FontWeight.w400),
                              ))
                          .toList(),
                    ),
                  ),
                if (order.description != null &&
                    order.description!.trim().isNotEmpty)
                  LabeledSection(
                    title: 'Комментарий',
                    child: Text(order.description!,
                        style: AppTextStyles.subBody
                            .copyWith(fontWeight: FontWeight.w400)),
                  ),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(
              16.w,
              12.h,
              16.w,
              16.h + MediaQuery.of(context).padding.bottom),
          child: PrimaryButton(
            label: alreadyResponded
                ? 'Вы уже откликнулись'
                : (responding ? 'Отправка...' : 'Откликнуться'),
            enabled: !alreadyResponded && !responding,
            onPressed: (alreadyResponded || responding) ? null : onRespond,
          ),
        ),
      ],
    );
  }

  /// Переиспользование `formatRentDate` из `format.dart`, которая принимает
  /// OrderListItem. Собираем лёгкий адаптер на полях OrderDetail.
  OrderListItem _asListItem(OrderDetail o) => OrderListItem(
        id: o.id,
        displayNumber: o.displayNumber,
        title: o.title,
        address: o.address,
        dateFrom: o.dateFrom,
        dateTo: o.dateTo,
        timeFrom: o.timeFrom,
        timeTo: o.timeTo,
        exactDate: o.exactDate,
        wholeDay: o.wholeDay,
        machineryTitles: o.machineryTitles,
        publishedAt: o.publishedAt,
        customer: o.customer,
      );

  String _formatWorkItem(WorkItem w) {
    if (w.volume == null) return w.name;
    final String volumeText = _fmtVolume(w.volume!);
    final String unit = _unitToUi(w.unit);
    return unit.isEmpty
        ? '${w.name} — $volumeText'
        : '${w.name} — $volumeText $unit';
  }

  String _fmtVolume(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toString();
  }

  String _unitToUi(String? code) {
    switch (code) {
      case 'm':
        return 'м';
      case 'm2':
        return 'м²';
      case 'm3':
        return 'м³';
      default:
        return '';
    }
  }
}

class _OrderNotFound extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Text(
          'Заказ не найден или снят с публикации',
          style: AppTextStyles.bodyMRegular
              .copyWith(color: AppColors.textTertiary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.onRetry});
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
              'Не удалось загрузить заказ',
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

class _OutlinedChip extends StatelessWidget {
  const _OutlinedChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.primary, width: 1),
        borderRadius: BorderRadius.circular(100.r),
      ),
      child: Text(label,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 13.sp,
            fontWeight: FontWeight.w400,
            height: 1.3,
            color: AppColors.textPrimary,
          )),
    );
  }
}

/// Шторка выбора спецтехники. Возвращает `List<String>` с отмеченными
/// позициями через `Navigator.pop`. Используется при отклике из каталога
/// и при подтверждении заказа из «Мои заказы».
class PickEquipmentSheet extends StatefulWidget {
  const PickEquipmentSheet({
    super.key,
    required this.options,
    this.ctaLabel = 'Откликнуться',
  });
  final List<String> options;
  final String ctaLabel;

  @override
  State<PickEquipmentSheet> createState() => _PickEquipmentSheetState();
}

class _PickEquipmentSheetState extends State<PickEquipmentSheet> {
  final Set<String> _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16.w,
        12.h,
        16.w,
        16.h + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(height: 16.h),
          Text(
            'Выберите технику, на которой\nвы готовы выполнить работу',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          SizedBox(height: 16.h),
          for (final String e in widget.options)
            _CheckRow(
              label: e,
              checked: _picked.contains(e),
              onTap: () {
                setState(() {
                  if (!_picked.add(e)) _picked.remove(e);
                });
              },
            ),
          SizedBox(height: 16.h),
          PrimaryButton(
            label: widget.ctaLabel,
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.of(context).pop(_picked.toList()),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.checked,
    required this.onTap,
  });
  final String label;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        child: Row(
          children: <Widget>[
            Container(
              width: 22.r,
              height: 22.r,
              decoration: BoxDecoration(
                color: checked ? AppColors.primary : AppColors.surface,
                border: Border.all(
                  color: checked ? AppColors.primary : AppColors.border,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(4.r),
              ),
              child: checked
                  ? Icon(Icons.check, size: 16.r, color: Colors.white)
                  : null,
            ),
            SizedBox(width: 16.w),
            Text(label, style: AppTextStyles.body),
          ],
        ),
      ),
    );
  }
}

/// Диалог «Нет подходящей техники» — показывается когда исполнитель
/// пытается откликнуться на заказ, но ни один из требуемых видов
/// спецтехники не заведён у него в услугах. Кнопка ведёт в «Мои услуги».
class _NoMatchingMachineryDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
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
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Icon(Icons.close_rounded,
                    size: 22.r, color: AppColors.textTertiary),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Отклик не отправлен',
              textAlign: TextAlign.center,
              style:
                  AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8.h),
            Text(
              'У вас нет услуги с нужным видом спецтехники. '
              'Добавьте её в «Мои услуги», чтобы откликнуться.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMRegular
                  .copyWith(color: AppColors.textSecondary),
            ),
            SizedBox(height: 18.h),
            PrimaryButton(
              label: 'Перейти к моим услугам',
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/services');
              },
            ),
            SizedBox(height: 20.h),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Center(
                child: Text(
                  'Вернуться',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }
}

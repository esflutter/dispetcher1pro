import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/catalog/catalog_service.dart';
import 'package:dispatcher_1/core/catalog/format.dart';
import 'package:dispatcher_1/core/catalog/models.dart';
import 'package:dispatcher_1/core/my_orders/my_orders_service.dart'
    show AlreadyRespondedException, MatchAlreadyTakenException;
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/clickable_address.dart';
import 'package:dispatcher_1/core/widgets/customer_header.dart';
import 'package:dispatcher_1/core/widgets/labeled_section.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/customer_card_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/widgets/respond_bottom_sheet.dart';
import 'package:dispatcher_1/features/catalog/widgets/subscription_paywall.dart';
import 'package:dispatcher_1/features/executor_card/executor_card_screen.dart';
import 'package:dispatcher_1/features/orders/widgets/order_alerts.dart';
import 'package:dispatcher_1/features/profile/account_block.dart';
import 'package:dispatcher_1/features/profile/reviews_screen.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';

import 'package:dispatcher_1/core/widgets/dialog_close_button.dart';
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
    this.initialTitle,
  });

  final String orderId;
  final bool multipleEquipment;

  /// Экран открыт тапом по заказу из карточки заказчика. В таком случае
  /// блок заказчика в шапке ведёт не на новый push `CustomerCardScreen`,
  /// а на pop обратно — чтобы избежать бесконечной цепочки «заказ →
  /// заказчик → заказ → заказчик → ...» в стеке навигации.
  final bool fromCustomerCard;

  /// Название заказа из ленты — показываем сразу в AppBar, чтобы
  /// заголовок не моргал «Заказ → реальное название» во время
  /// загрузки `_load()`. Если детали из БД отдадут другое значение,
  /// AppBar обновится после получения.
  final String? initialTitle;

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
    AccountBlock.notifier.addListener(_refresh);
  }

  @override
  void dispose() {
    AccountBlock.notifier.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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

    // 1. Профиль заблокирован.
    if (AccountBlock.isBlocked) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) => _BlockedDialog(),
      );
      return;
    }

    // 2. Документы на проверке — отклик пока недоступен.
    if (VerificationStatus.current == VerificationStatus.inProgress) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) => _InProgressDialog(),
      );
      return;
    }

    // 3. Верификация не пройдена — предлагаем отправить документы.
    if (!VerificationStatus.current.isVerified) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) => RespondModalDialog(verified: false),
      );
      if (mounted) setState(() {});
      return;
    }

    // 4. Подписка не активна — paywall либо «приостановлена» с возобновлением.
    if (!VerificationStatus.hasSubscription) {
      if (VerificationStatus.subscriptionPaidUntilText != null) {
        final bool? go = await showSubscriptionPausedDialog(context);
        if (go == true && mounted) context.push('/subscription');
        return;
      }
      // Paywall сам уводит юзера в реальный экран оплаты — отсюда
      // действие («Откликнуться») всегда прерываем. После оплаты юзер
      // вернётся в корень навигации, придёт сюда снова и нажмёт ещё раз.
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const SubscriptionPaywall(),
        ),
      );
      return;
    }

    // 5. Карточка исполнителя должна быть создана.
    if (!ExecutorCardScreen.cardCreated) {
      final bool? go = await showExecutorCardRequiredDialog(context);
      if (go == true && mounted) {
        await context.push('/executor-card/edit');
        if (mounted) setState(() {});
      }
      return;
    }

    setState(() => _responding = true);
    try {
      final CatalogService svc = CatalogService.instance;
      final List<MyActiveService> myServices =
          await svc.listMyActiveServices();
      // Пересечение моих услуг с техникой заказа: одна услуга = одна
      // строка в шторке выбора, разные тарифы за один и тот же экскаватор
      // не схлопываются.
      final List<MyActiveService> matching = myServices
          .where((MyActiveService s) =>
              order.machineryTitles.contains(s.machineryTitle))
          .toList();
      if (matching.isEmpty) {
        if (!mounted) return;
        setState(() => _responding = false);
        await showDialog<void>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.35),
          builder: (_) => _NoMatchingMachineryDialog(),
        );
        return;
      }

      String? serviceId;
      if (matching.length == 1) {
        serviceId = matching.first.id;
      } else {
        if (!mounted) return;
        serviceId = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => PickServiceSheet(options: matching),
        );
        if (serviceId == null || !mounted) {
          setState(() => _responding = false);
          return;
        }
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
    } on AlreadyRespondedException {
      // Этот же исполнитель уже откликался на этот заказ (его отклик
      // потом получил rejected_*/expired). По бизнес-правилу повторный
      // отклик запрещён — UNIQUE-индекс не пропускает INSERT. Сообщение
      // отличается от MatchAlreadyTakenException: тут вина не в заказе,
      // а в самом пользователе — он уже пытался.
      if (!mounted) return;
      setState(() {
        _justResponded = true;
        _responding = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Вы уже откликались на этот заказ.'),
          duration: Duration(seconds: 4),
        ),
      );
    } on MatchAlreadyTakenException {
      if (!mounted) return;
      setState(() {
        _justResponded = true;
        _responding = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Откликнуться на этот заказ нельзя: он уже снят с публикации '
            'или заказчик уже выбрал исполнителя.',
          ),
          duration: Duration(seconds: 4),
        ),
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
              final String title = snap.data?.order?.title ??
                  widget.initialTitle ??
                  'Заказ';
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
                        targetUserId: order.customer.id,
                        initialRating: order.customer.ratingAsCustomer,
                        initialCount: order.customer.reviewCountAsCustomer,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 10.h),
                Text('№${order.displayNumber.toString().padLeft(8, '0')}',
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
                    title: 'Описание заказа',
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
            enabled: !alreadyResponded &&
                !responding &&
                !AccountBlock.isBlocked,
            onPressed:
                (alreadyResponded || responding || AccountBlock.isBlocked)
                    ? null
                    : onRespond,
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
    final String? vol = w.volume;
    if (vol == null || vol.isEmpty) return w.name;
    final String unit = _unitToUi(w.unit);
    return unit.isEmpty
        ? '${w.name} — $vol'
        : '${w.name} — $vol $unit';
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

/// Шторка выбора конкретной услуги при отклике на заказ.
/// Возвращает `id` выбранной услуги (или null при отмене). Подходит
/// для случая, когда у исполнителя несколько услуг с одной техникой
/// (разные тарифы) — каждая услуга = отдельная строка с ценой.
class PickServiceSheet extends StatefulWidget {
  const PickServiceSheet({
    super.key,
    required this.options,
    this.ctaLabel = 'Откликнуться',
  });
  final List<MyActiveService> options;
  final String ctaLabel;

  @override
  State<PickServiceSheet> createState() => _PickServiceSheetState();
}

class _PickServiceSheetState extends State<PickServiceSheet> {
  String? _picked;

  String _priceLine(MyActiveService s) {
    final List<String> parts = <String>[];
    if (s.pricePerHour != null) {
      parts.add('${s.pricePerHour!.toStringAsFixed(0)} ₽/ч');
    }
    if (s.pricePerDay != null) {
      parts.add('${s.pricePerDay!.toStringAsFixed(0)} ₽/день');
    }
    if (s.minHours != null) parts.add('от ${s.minHours} ч');
    if (parts.isEmpty) return 'цена по запросу';
    return parts.join(' · ');
  }

  /// Собирает строку для одной услуги: «<техника> · <название> · <цена>».
  /// Любое из полей может быть пустым — фоллбэками гарантируем, что
  /// строка не схлопнется до одной точки.
  String _serviceLabel(MyActiveService s) {
    final String machinery =
        s.machineryTitle.isEmpty ? 'Услуга' : s.machineryTitle;
    final String title = s.title.trim();
    final String price = _priceLine(s);
    final List<String> parts = <String>[
      machinery,
      if (title.isNotEmpty) title,
      price,
    ];
    return parts.join(' · ');
  }

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
            'Выберите услугу, по которой\nготовы взяться за заказ',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          SizedBox(height: 16.h),
          for (final MyActiveService s in widget.options)
            _CheckRow(
              label: _serviceLabel(s),
              checked: _picked == s.id,
              onTap: () {
                setState(() => _picked = s.id);
              },
            ),
          SizedBox(height: 16.h),
          PrimaryButton(
            label: widget.ctaLabel,
            onPressed: _picked == null
                ? null
                : () => Navigator.of(context).pop(_picked),
          ),
        ],
      ),
    );
  }
}

/// Диалог «Ваши документы ещё на проверке» — показывается при попытке
/// откликнуться, пока верификация в статусе [VerificationStatus.inProgress].
class _InProgressDialog extends StatelessWidget {
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
              child: DialogCloseButton(
                onTap: () => Navigator.of(context).pop(),
                color: AppColors.textTertiary,
                iconSize: 22.r,
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Ваши документы ещё\nна проверке',
              textAlign: TextAlign.center,
              style:
                  AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8.h),
            Text(
              'Вы получите уведомление, когда проверка завершится',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMRegular
                  .copyWith(color: AppColors.textSecondary),
            ),
            SizedBox(height: 18.h),
            PrimaryButton(
              label: 'Ок',
              onPressed: () => Navigator.of(context).pop(),
            ),
            SizedBox(height: 12.h),
          ],
        ),
      ),
    );
  }
}

/// Диалог «Ваш профиль заблокирован на 30 дней» — показывается при попытке
/// откликнуться при активной [AccountBlock].
class _BlockedDialog extends StatelessWidget {
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
              child: DialogCloseButton(
                onTap: () => Navigator.of(context).pop(),
                color: AppColors.textTertiary,
                iconSize: 22.r,
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Ваш профиль заблокирован\n${AccountBlock.blockedUntilText ?? "на 30 дней"}',
              textAlign: TextAlign.center,
              style:
                  AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8.h),
            Text(
              'Во избежание дальнейших блокировок избегайте отзывов с низкой оценкой',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMRegular
                  .copyWith(color: AppColors.textSecondary),
            ),
            SizedBox(height: 18.h),
            PrimaryButton(
              label: 'Ок',
              onPressed: () => Navigator.of(context).pop(),
            ),
            SizedBox(height: 12.h),
          ],
        ),
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
              child: DialogCloseButton(
                onTap: () => Navigator.of(context).pop(),
                color: AppColors.textTertiary,
                iconSize: 22.r,
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

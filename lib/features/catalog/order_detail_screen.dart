import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/customer_header.dart';
import 'package:dispatcher_1/core/widgets/labeled_section.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/customer_card_screen.dart';
import 'package:dispatcher_1/features/catalog/order_feed_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/widgets/respond_bottom_sheet.dart';
import 'package:dispatcher_1/features/catalog/widgets/subscription_paywall.dart';
import 'package:dispatcher_1/features/executor_card/executor_card_screen.dart';
import 'package:dispatcher_1/features/orders/my_orders_screen.dart';
import 'package:dispatcher_1/features/orders/widgets/order_alerts.dart';
import 'package:dispatcher_1/features/profile/account_block.dart';
import 'package:dispatcher_1/features/services/my_services_screen.dart';
import 'package:dispatcher_1/features/profile/reviews_screen.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';

/// Карточка заказа (детали). По Figma — заголовок заказчика сверху,
/// далее «номер заказа → заголовок → дата публикации → секции».
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

  /// Трекер id заказов, на которые этот исполнитель уже откликнулся.
  /// Живёт в памяти до появления бэкенда — чтобы нельзя было отправить
  /// повторный отклик на тот же заказ. Чистится при logout/deleteAccount
  /// через [clearResponded].
  static final Set<String> respondedOrderIds = <String>{};

  /// Сбрасывает трекер откликов — вызывается при выходе/удалении аккаунта,
  /// чтобы на свежем аккаунте кнопка «Откликнуться» не была заблокирована
  /// прошлой сессией.
  static void clearResponded() {
    respondedOrderIds.clear();
  }

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  static const List<String> _multiEquipment = <String>[
    'Экскаватор',
    'Автокран',
    'Манипулятор',
    'Погрузчик',
    'Автовышка',
  ];

  @override
  void initState() {
    super.initState();
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

  bool get _verified => VerificationStatus.current.isVerified;
  bool get _hasSubscription => VerificationStatus.hasSubscription;
  bool get _alreadyResponded =>
      OrderDetailScreen.respondedOrderIds.contains(widget.orderId);

  /// Реальный список техники заказа. Если заказ найден в моке —
  /// отдаём его `equipment`; иначе падаем на фолбэк по флагу
  /// `multipleEquipment` (используется в точках вызова, где нет
  /// конкретного заказа — например, в тестовых плейсхолдерах).
  List<String> get _orderEquipment {
    final CatalogOrderMock? order = CatalogOrderMock.byId(widget.orderId);
    if (order != null && order.equipment.isNotEmpty) {
      return order.equipment;
    }
    return widget.multipleEquipment
        ? _multiEquipment
        : const <String>['Экскаватор'];
  }

  Future<void> _onRespondTap() async {
    if (AccountBlock.isBlocked) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) => _BlockedDialog(),
      );
      return;
    }

    // 1. Проверка верификации — в процессе.
    if (VerificationStatus.current == VerificationStatus.inProgress) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) => _InProgressDialog(),
      );
      return;
    }

    // 2. Верификация не пройдена — предлагаем отправить документы.
    if (!_verified) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) => RespondModalDialog(verified: false),
      );
      if (mounted) setState(() {});
      return;
    }

    // 3. Проверка подписки.
    if (!_hasSubscription) {
      if (VerificationStatus.subscriptionPaidUntilText != null) {
        // Подписка приостановлена — показываем попап с кнопкой возобновления.
        final bool? go = await showSubscriptionPausedDialog(context);
        if (go == true && mounted) context.push('/subscription');
        return;
      }
      final bool? subscribed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) => const SubscriptionPaywall(),
        ),
      );
      if (subscribed != true || !mounted) return;
      VerificationStatus.hasSubscription = true;
    }

    // 4. Проверка карточки исполнителя — должна быть создана.
    if (!ExecutorCardScreen.cardCreated) {
      final bool? go = await showExecutorCardRequiredDialog(context);
      if (go == true && mounted) {
        await context.push('/executor-card/edit');
        if (mounted) setState(() {});
      }
      return;
    }

    // 5. Фильтруем технику заказа по тому, что есть у исполнителя в
    // услугах (`ExecutorCardData.machinery` — computed из services).
    // Если пересечения нет — откликнуться нельзя, показываем диалог с
    // подсказкой добавить нужный вид техники.
    final List<String> eq = _orderEquipment;
    final Set<String> ownedMach = ExecutorCardData.machinery.toSet();
    final List<String> availableEq =
        eq.where((String e) => ownedMach.contains(e)).toList();
    if (availableEq.isEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) => _NoMatchingMachineryDialog(),
      );
      return;
    }
    List<String> respondedEquipment = availableEq;
    // Шторку выбора показываем только когда в заказе требуется
    // больше одного вида техники. Если требуется ровно один —
    // откликаемся без шторки, даже если у исполнителя совпали не
    // все (всё равно выбирать не из чего).
    if (eq.length > 1) {
      final List<String>? picked = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PickEquipmentSheet(options: availableEq),
      );
      if (picked == null || picked.isEmpty || !mounted) {
        return;
      }
      respondedEquipment = picked;
    }

    // 5. Отклик отправлен — фиксируем, чтобы повторно нельзя было,
    // и добавляем заказ в «Мои заказы» → «Новые» со статусом
    // `offerSent` («Ожидает ответа заказчика»).
    OrderDetailScreen.respondedOrderIds.add(widget.orderId);
    final CatalogOrderMock? catalogOrder =
        CatalogOrderMock.byId(widget.orderId);
    if (catalogOrder != null) {
      MyOrdersStore.addResponded(
        id: catalogOrder.id,
        title: catalogOrder.title,
        equipment: respondedEquipment,
        rentDate: catalogOrder.rentDate,
        address: catalogOrder.address,
        publishedAgo: catalogOrder.publishedAgo,
        customerId: catalogOrder.customerId,
        customerName: catalogOrder.customerName,
        customerRating: catalogOrder.customerRating,
        customerReviews: catalogOrder.customerReviews,
      );
    }
    if (!mounted) return;
    setState(() {});
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => RespondModalDialog(verified: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CatalogOrderMock? order = CatalogOrderMock.byId(widget.orderId);
    final List<String> equipment = order?.equipment ?? _orderEquipment;
    final String orderTitle = order?.title ?? 'Разработка котлована под фундамент';
    final String orderAddress =
        order?.address ?? 'Московская область, Москва, Улица1, д 144';
    final String orderRentDate = order?.rentDate ?? '15 июня · 09:00–18:00';
    final String orderPublishedAgo = order?.publishedAgo ?? 'Вчера в 14:30';
    final List<String> orderCategories = (order?.categories.isNotEmpty ?? false)
        ? order!.categories
        : const <String>['Земляные работы', 'Подготовка строительной площадки'];
    // Заказчик тянется из мока — чтобы шапка в деталях совпадала с тем,
    // что исполнитель видел в ленте. Фолбэк оставлен на случай, если
    // заказ не найден по id.
    final String customerId = order?.customerId ?? '1';
    final String customerName = order?.customerName ?? 'Александр Иванов';
    // Фолбэки синхронизированы с `CatalogOrderMock` (4.6/10) и длиной
    // `_customerInitialMock` в `reviews_screen.dart` — иначе в шапке
    // «15 отзывов», а в списке откроется 10.
    final double customerRating = order?.customerRating ?? 4.6;
    final int customerReviews = order?.customerReviews ?? 10;

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
          child: Text(
            orderTitle,
            style: AppTextStyles.titleS.copyWith(color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: const <Widget>[],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 88.h),
        child: AiAssistantFab(
          onTap: () => context.push('/assistant/chat'),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      CustomerHeader(
                        name: customerName,
                        rating: customerRating,
                        reviews: customerReviews,
                        onTap: widget.fromCustomerCard
                            ? () => Navigator.of(context).maybePop()
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => CustomerCardScreen(
                                      customerId: customerId,
                                      customerName: customerName,
                                      customerRating: customerRating,
                                      customerReviews: customerReviews,
                                    ),
                                  ),
                                ),
                        onReviewsTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ReviewsScreen(
                              subject: ReviewSubject.customer,
                              initialRating: customerRating,
                              initialCount: customerReviews,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 10.h),
                      Text('№${widget.orderId.padLeft(6, '0')}',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textTertiary)),
                      SizedBox(height: 4.h),
                      Text(orderTitle,
                          style: AppTextStyles.titleL.copyWith(height: 1.2)),
                      SizedBox(height: 7.h),
                      Text(orderPublishedAgo,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textTertiary)),
                      SizedBox(height: 11.h),
                      LabeledSection(
                        title: 'Дата и время аренды',
                        child: Text(orderRentDate,
                            style: AppTextStyles.subBody.copyWith(fontWeight: FontWeight.w400)),
                      ),
                      LabeledSection(
                        title: 'Адрес',
                        child: Text(
                            orderAddress,
                            style: AppTextStyles.subBody.copyWith(
                              fontWeight: FontWeight.w400,
                              decoration: TextDecoration.underline,
                            )),
                      ),
                      LabeledSection(
                        title: 'Требуемая спецтехника',
                        child: Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: equipment
                              .map((String e) => _OutlinedChip(label: e))
                              .toList(),
                        ),
                      ),
                      LabeledSection(
                        title: 'Категория работ',
                        child: Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: orderCategories
                              .map((String c) => _OutlinedChip(label: c))
                              .toList(),
                        ),
                      ),
                      LabeledSection(
                        title: 'Характер работ',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('Разработка грунта — 40 м³',
                                style: AppTextStyles.subBody.copyWith(fontWeight: FontWeight.w400)),
                            Text('Планировка участка — 2 × 12 × 15 м',
                                style: AppTextStyles.subBody.copyWith(fontWeight: FontWeight.w400)),
                          ],
                        ),
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
              label: _alreadyResponded ? 'Вы уже откликнулись' : 'Откликнуться',
              enabled: !AccountBlock.isBlocked && !_alreadyResponded,
              onPressed: (AccountBlock.isBlocked || _alreadyResponded)
                  ? null
                  : _onRespondTap,
            ),
          ),
        ],
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
/// позициями через `Navigator.pop`. Используется и при отклике из
/// каталога (кнопка «Откликнуться»), и при подтверждении заказа из
/// «Мои заказы» (кнопка «Подтвердить»).
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
                final bool alreadyChecked = _picked.contains(e);
                if (!alreadyChecked) {
                  final bool hasService = ServiceData.services
                      .any((ServiceMock s) => s.machinery.contains(e));
                  if (!hasService) {
                    showNoServiceForEquipmentDialog(
                      context,
                      equipment: e,
                      onGoToServices: () {
                        Navigator.of(context).pop();
                        context.push('/services');
                      },
                    );
                    return;
                  }
                }
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
/// спецтехники не заведён у него в услугах. Кнопка ведёт в «Мои услуги»,
/// чтобы создать недостающую услугу.
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
          children: [
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
              'Ваши документы ещё\nна проверке',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
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

/// Диалог «Ваш профиль заблокирован на 30 дней» — показывается, если
/// исполнитель пытается откликнуться при активной блокировке.
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
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Icon(Icons.close_rounded,
                    size: 22.r, color: AppColors.textTertiary),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Ваш профиль заблокирован\nна 30 дней',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
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

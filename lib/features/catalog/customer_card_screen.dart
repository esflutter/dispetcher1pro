import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/ai/ai_navigation.dart';
import 'package:dispatcher_1/core/catalog/catalog_service.dart';
import 'package:dispatcher_1/core/catalog/format.dart';
import 'package:dispatcher_1/core/catalog/models.dart';
import 'package:dispatcher_1/core/my_orders/my_orders_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/plural.dart';
import 'package:dispatcher_1/core/widgets/avatar_circle.dart';
import 'package:dispatcher_1/features/catalog/order_detail_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/widgets/order_card.dart';
import 'package:dispatcher_1/features/profile/reviews_screen.dart';

/// Карточка заказчика — публичный профиль, который видит исполнитель.
/// Данные тянутся из БД: `profiles` + `orders` этого заказчика.
/// Контакты (телефон/email) лежат в `profiles_private` под RLS — RLS
/// пропустит их только участнику accepted/completed мэтча. Если флаг
/// [hasMatch] выставлен снаружи, экран дополнительно тянет контакты.
class CustomerCardScreen extends StatefulWidget {
  const CustomerCardScreen({
    super.key,
    required this.customerId,
    // Следующие параметры приходят из старого контракта «Мои заказы» —
    // игнорируются, т.к. имя/рейтинг теперь тянутся из БД.
    this.customerName,
    this.customerRating,
    this.customerReviews,
    this.customerPhone,
    this.customerEmail,
    this.hasMatch,
  });

  final String customerId;
  final String? customerName;
  final double? customerRating;
  final int? customerReviews;
  final String? customerPhone;
  final String? customerEmail;

  /// Был ли уже хотя бы один accepted/completed мэтч с этим заказчиком.
  /// Если `true` — экран попытается прочитать `profiles_private` и
  /// показать телефон/email. Если `null` или `false` — контакты не
  /// загружаются и не показываются.
  final bool? hasMatch;

  @override
  State<CustomerCardScreen> createState() => _CustomerCardScreenState();
}

class _CustomerCardScreenState extends State<CustomerCardScreen> {
  late Future<_CustomerCardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_CustomerCardData> _load() async {
    final CatalogService svc = CatalogService.instance;
    final bool wantsContacts = widget.hasMatch == true;
    final List<dynamic> res = await Future.wait<dynamic>(<Future<dynamic>>[
      svc.getCustomer(widget.customerId),
      svc.listCustomerOrders(widget.customerId),
      if (wantsContacts)
        MyOrdersService.instance.getCustomerContacts(widget.customerId)
      else
        Future<({String? phone, String? email})?>.value(null),
    ]);
    final ({String? phone, String? email})? contacts =
        res[2] as ({String? phone, String? email})?;
    return _CustomerCardData(
      profile: res[0] as CustomerProfile?,
      orders: res[1] as List<OrderListItem>,
      phone: contacts?.phone ?? widget.customerPhone,
      email: contacts?.email ?? widget.customerEmail,
    );
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
        title: Text(
          'Заказчик',
          style: AppTextStyles.titleS.copyWith(color: Colors.white),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20.r),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 24.h),
        child: AiAssistantFab(
          onTap: () => openAssistantChat(context),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: FutureBuilder<_CustomerCardData>(
        future: _future,
        builder:
            (BuildContext context, AsyncSnapshot<_CustomerCardData> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _RetryView(onRetry: () => setState(() {
                  _future = _load();
                }));
          }
          final _CustomerCardData? data = snap.data;
          if (data == null || data.profile == null) {
            return Center(
              child: Text(
                'Профиль заказчика недоступен',
                style: AppTextStyles.bodyMRegular
                    .copyWith(color: AppColors.textTertiary),
              ),
            );
          }
          return _Content(
            profile: data.profile!,
            orders: data.orders,
            phone: data.phone,
            email: data.email,
          );
        },
      ),
    );
  }
}

class _CustomerCardData {
  const _CustomerCardData({
    required this.profile,
    required this.orders,
    this.phone,
    this.email,
  });
  final CustomerProfile? profile;
  final List<OrderListItem> orders;
  final String? phone;
  final String? email;
}

class _Content extends StatelessWidget {
  const _Content({
    required this.profile,
    required this.orders,
    this.phone,
    this.email,
  });
  final CustomerProfile profile;
  final List<OrderListItem> orders;
  final String? phone;
  final String? email;

  @override
  Widget build(BuildContext context) {
    final String statusLabel = _legalStatusLabel(profile.legalStatus);
    final bool hasAbout =
        profile.about != null && profile.about!.trim().isNotEmpty;
    final bool showPhone = phone != null && phone!.trim().isNotEmpty;
    final bool showEmail = email != null && email!.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _HeaderBlock(profile: profile),
            SizedBox(height: 20.h),
            if (showPhone) ...<Widget>[
              _Field(label: 'Номер телефона', value: phone!),
              SizedBox(height: 16.h),
            ],
            if (showEmail) ...<Widget>[
              _Field(label: 'Электронная почта', value: email!),
              SizedBox(height: 16.h),
            ],
            if (hasAbout) ...<Widget>[
              _Field(label: 'О себе', value: profile.about!),
              SizedBox(height: 16.h),
            ],
            _Field(label: 'Статус', value: statusLabel),
            if (orders.isNotEmpty) ...<Widget>[
              SizedBox(height: 20.h),
              for (int i = 0; i < orders.length; i++) ...<Widget>[
                _OrderTile(order: orders[i]),
                if (i != orders.length - 1) SizedBox(height: 10.h),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _legalStatusLabel(String? code) {
    switch (code) {
      case 'individual':
        return 'Физ. лицо';
      case 'self_employed':
        return 'Самозанятый';
      case 'ip':
        return 'ИП';
      case 'legal_entity':
        return 'ООО';
      default:
        return 'Физ. лицо';
    }
  }
}

class _HeaderBlock extends StatelessWidget {
  const _HeaderBlock({required this.profile});
  final CustomerProfile profile;

  String _fmtRating(double v) =>
      v.toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        AvatarCircle(size: 72.r, avatarUrl: profile.avatarUrl),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(profile.name, style: AppTextStyles.titleS),
              SizedBox(height: 4.h),
              Row(
                children: <Widget>[
                  if (profile.reviewCountAsCustomer > 0) ...<Widget>[
                    Image.asset(
                      'assets/images/catalog/star.webp',
                      width: 20.r,
                      height: 20.r,
                      errorBuilder: (_, _, _) => Icon(Icons.star_rounded,
                          size: 20.r, color: AppColors.ratingStar),
                    ),
                    SizedBox(width: 4.w),
                    Text(_fmtRating(profile.ratingAsCustomer),
                        style: AppTextStyles.body),
                    SizedBox(width: 16.w),
                  ],
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReviewsScreen(
                          subject: ReviewSubject.customer,
                          targetUserId: profile.id,
                          initialRating: profile.ratingAsCustomer,
                          initialCount: profile.reviewCountAsCustomer,
                        ),
                      ),
                    ),
                    child: Text(
                      '${profile.reviewCountAsCustomer} ${reviewsWord(profile.reviewCountAsCustomer)}',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textPrimary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style:
              AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 4.h),
        Text(value, style: AppTextStyles.body),
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});
  final OrderListItem order;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryTint,
      borderRadius: BorderRadius.circular(12.r),
      clipBehavior: Clip.antiAlias,
      child: OrderCard(
        title: order.title,
        address: order.address,
        rentDate: formatRentDate(order),
        publishedAgo: formatPublishedAgo(order.publishedAt),
        equipment: order.machineryTitles,
        highlightEquipment: const <String>{},
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OrderDetailScreen(
              orderId: order.id,
              initialTitle: order.title,
              multipleEquipment: order.machineryTitles.length > 1,
              fromCustomerCard: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _RetryView extends StatelessWidget {
  const _RetryView({required this.onRetry});
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
              'Не удалось загрузить профиль',
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

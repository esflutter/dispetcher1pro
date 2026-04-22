import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/features/catalog/order_detail_screen.dart';
import 'package:dispatcher_1/features/catalog/order_feed_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/catalog/widgets/order_card.dart';

/// Мок-профиль заказчика. Пока нет бэкенда, получаем из локального
/// каталога по `customerId`. [hasMatch] = был ли уже принятый обоюдно
/// заказ — до этого телефон и email не показываем.
class _CustomerInfo {
  const _CustomerInfo({
    required this.id,
    required this.name,
    required this.status,
    required this.reviewsCount,
    required this.rating,
    this.phone,
    this.email,
    this.about,
    this.hasMatch = false,
  });

  final String id;
  final String name;
  final String status;
  final int reviewsCount;
  final double rating;
  final String? phone;
  final String? email;
  final String? about;
  final bool hasMatch;
}

/// Доп. поля по каждому заказчику (то, чего нет в `CatalogOrderMock`).
/// Имя / рейтинг / число отзывов НЕ дублируем — тянем из моков заказов.
const Map<String, ({String status, String? phone, String? email, String about})>
    _customerExtras = <String, ({String status, String? phone, String? email, String about})>{
  '1': (
    status: 'Физ. лицо',
    phone: '+7 999 123-45-67',
    email: null,
    about: 'Частный заказчик. Периодически нужны услуги спецтехники для '
        'строительных работ и благоустройства участка.',
  ),
  '2': (
    status: 'ИП',
    phone: '+7 999 234-56-78',
    email: 'petrov@example.ru',
    about: 'Строительная бригада. Регулярно заказываем спецтехнику на объекты.',
  ),
  '3': (
    status: 'Физ. лицо',
    phone: '+7 999 345-67-89',
    email: null,
    about: 'Частный заказчик. Ведём работы на собственном участке.',
  ),
  '4': (
    status: 'ООО',
    phone: '+7 999 456-78-90',
    email: 'kozlov@example.ru',
    about: 'Компания, занимается строительством и благоустройством.',
  ),
};

_CustomerInfo _customerFor(String id) {
  CatalogOrderMock? orderRef;
  for (final CatalogOrderMock o in CatalogOrderMock.all) {
    if (o.customerId == id) {
      orderRef = o;
      break;
    }
  }
  final extras = _customerExtras[id];
  return _CustomerInfo(
    id: id,
    name: orderRef?.customerName ?? 'Заказчик',
    status: extras?.status ?? 'Физ. лицо',
    reviewsCount: orderRef?.customerReviews ?? 0,
    rating: orderRef?.customerRating ?? 0.0,
    phone: extras?.phone,
    email: extras?.email,
    about: extras?.about,
    // До появления бэкенда: считаем, что совпадений по заказам ещё не
    // было — контакты скрыты. На реальных данных флаг придёт с сервера.
    hasMatch: false,
  );
}

/// Карточка заказчика — публичный профиль, который видит исполнитель.
///
/// Основные поля (имя/рейтинг/отзывы/телефон/email) можно переопределить
/// параметрами, если экран-источник уже знает эти данные — это нужно
/// для входов из «Моих заказов» и «Моего графика», где заказ не лежит в
/// `CatalogOrderMock.all` и lookup по `customerId` вернул бы дефолт
/// «Заказчик, 0 отзывов». Если override задан — используем его; иначе —
/// fallback на лукап по id.
class CustomerCardScreen extends StatelessWidget {
  const CustomerCardScreen({
    super.key,
    required this.customerId,
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

  /// Было ли у исполнителя и этого заказчика хотя бы одно принятое
  /// взаимодействие. Если да — контакты показываем; если нет (или null
  /// → fallback на дефолт `false`) — телефон/email скрыты.
  final bool? hasMatch;

  @override
  Widget build(BuildContext context) {
    final _CustomerInfo base = _customerFor(customerId);
    final _CustomerInfo c = _CustomerInfo(
      id: customerId,
      name: (customerName != null && customerName!.trim().isNotEmpty)
          ? customerName!
          : base.name,
      status: base.status,
      reviewsCount: customerReviews ?? base.reviewsCount,
      rating: customerRating ?? base.rating,
      phone: customerPhone ?? base.phone,
      email: customerEmail ?? base.email,
      about: base.about,
      hasMatch: hasMatch ?? base.hasMatch,
    );
    final List<CatalogOrderMock> orders = CatalogOrderMock.all
        .where((CatalogOrderMock o) => o.customerId == customerId)
        .toList();

    final bool showPhone =
        c.hasMatch && c.phone != null && c.phone!.trim().isNotEmpty;
    final bool showEmail =
        c.hasMatch && c.email != null && c.email!.trim().isNotEmpty;
    final bool hasAbout = c.about != null && c.about!.trim().isNotEmpty;

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
          onTap: () => context.push('/assistant/chat'),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _HeaderBlock(info: c),
              SizedBox(height: 20.h),
              if (showPhone) ...<Widget>[
                _Field(label: 'Номер телефона', value: c.phone!),
                SizedBox(height: 16.h),
              ],
              if (showEmail) ...<Widget>[
                _Field(label: 'Электронная почта', value: c.email!),
                SizedBox(height: 16.h),
              ],
              if (hasAbout) ...<Widget>[
                _Field(label: 'О себе', value: c.about!),
                SizedBox(height: 16.h),
              ],
              _Field(label: 'Статус', value: c.status),
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
      ),
    );
  }
}

class _HeaderBlock extends StatelessWidget {
  const _HeaderBlock({required this.info});
  final _CustomerInfo info;

  String _fmtRating(double v) =>
      v.toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        CircleAvatar(
          radius: 36.r,
          backgroundColor: AppColors.primaryTint,
          backgroundImage: const AssetImage(
              'assets/images/catalog/avatar_placeholder.webp'),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(info.name, style: AppTextStyles.titleS),
              SizedBox(height: 4.h),
              Row(
                children: <Widget>[
                  Image.asset(
                    'assets/images/catalog/star.webp',
                    width: 20.r,
                    height: 20.r,
                    errorBuilder: (_, _, _) => Icon(Icons.star_rounded,
                        size: 20.r, color: AppColors.ratingStar),
                  ),
                  SizedBox(width: 4.w),
                  Text(_fmtRating(info.rating), style: AppTextStyles.body),
                  SizedBox(width: 16.w),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/profile/reviews'),
                    child: Text(
                      '${info.reviewsCount} отзывов',
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
          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 4.h),
        Text(value, style: AppTextStyles.body),
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});
  final CatalogOrderMock order;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryTint,
      borderRadius: BorderRadius.circular(12.r),
      clipBehavior: Clip.antiAlias,
      child: OrderCard(
        title: order.title,
        address: order.address,
        rentDate: order.rentDate,
        publishedAgo: order.publishedAgo,
        equipment: order.equipment,
        highlightEquipment: const <String>{},
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OrderDetailScreen(
              orderId: order.id,
              multipleEquipment: order.equipment.length > 1,
              fromCustomerCard: true,
            ),
          ),
        ),
      ),
    );
  }
}

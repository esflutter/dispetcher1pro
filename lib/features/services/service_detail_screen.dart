import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/my_services/models.dart';
import 'package:dispatcher_1/core/my_services/my_services_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/photo_source.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/photo_gallery_screen.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';

/// Склонение «час» после предлога «от» (род. падеж).
String _hoursWord(int n) {
  final int mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'часов';
  if (n % 10 == 1) return 'часа';
  return 'часов';
}

/// Экран «Детали услуги» — читает одну услугу из БД.
class ServiceDetailScreen extends StatefulWidget {
  const ServiceDetailScreen({super.key, required this.serviceId});

  final String serviceId;

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  late Future<MyServiceDetail?> _future;

  @override
  void initState() {
    super.initState();
    _future = MyServicesService.instance.getMine(widget.serviceId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Детали услуги'),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 88.h),
        child: AiAssistantFab(onTap: () => context.push('/assistant/chat')),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: FutureBuilder<MyServiceDetail?>(
        future: _future,
        builder: (BuildContext context,
            AsyncSnapshot<MyServiceDetail?> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _RetryView(
              onRetry: () => setState(() {
                _future =
                    MyServicesService.instance.getMine(widget.serviceId);
              }),
            );
          }
          final MyServiceDetail? s = snap.data;
          if (s == null) {
            return Center(
              child: Text('Услуга не найдена', style: AppTextStyles.body),
            );
          }
          return _Content(
            service: s,
            onEdit: () async {
              await context.push('/services/${widget.serviceId}/edit');
              if (!mounted) return;
              setState(() {
                _future =
                    MyServicesService.instance.getMine(widget.serviceId);
              });
            },
          );
        },
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.service, required this.onEdit});
  final MyServiceDetail service;
  final VoidCallback onEdit;

  String _fmtPrice(double? v) {
    if (v == null) return '';
    final int i = v.round();
    final String s = i.toString();
    final StringBuffer b = StringBuffer();
    for (int k = 0; k < s.length; k++) {
      if (k > 0 && (s.length - k) % 3 == 0) b.write(' ');
      b.write(s[k]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final String perHour = _fmtPrice(service.pricePerHour);
    final String perDay = _fmtPrice(service.pricePerDay);
    final bool hasPerHour = perHour.isNotEmpty;
    final bool hasPerDay = perDay.isNotEmpty;
    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  service.title,
                  style: AppTextStyles.titleL.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                if (hasPerHour || hasPerDay) SizedBox(height: 16.h),
                if (hasPerHour || hasPerDay)
                  Row(
                    children: <Widget>[
                      if (hasPerHour) ...<Widget>[
                        Text('₽ / час',
                            style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            )),
                        SizedBox(width: 6.w),
                        Text('$perHour ₽',
                            style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                        if (hasPerDay) SizedBox(width: 24.w),
                      ],
                      if (hasPerDay) ...<Widget>[
                        Text('₽ / день',
                            style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            )),
                        SizedBox(width: 6.w),
                        Text('$perDay ₽',
                            style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                      ],
                    ],
                  ),
                if (service.minHours != null) ...<Widget>[
                  SizedBox(height: 16.h),
                  Row(
                    children: <Widget>[
                      Text('Минимальный заказ:',
                          style: AppTextStyles.body.copyWith(
                            fontSize: 14.sp,
                            color: AppColors.textSecondary,
                          )),
                      SizedBox(width: 6.w),
                      Text(
                        'от ${service.minHours} ${_hoursWord(service.minHours!)}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                if (service.description != null &&
                    service.description!.trim().isNotEmpty) ...<Widget>[
                  SizedBox(height: 16.h),
                  Text(
                    service.description!,
                    style: AppTextStyles.body
                        .copyWith(fontSize: 14.sp, height: 1.4),
                  ),
                ],
                SizedBox(height: 16.h),
                _SectionTitle('Спецтехника'),
                SizedBox(height: 8.h),
                _ChipRow(items: service.machineryTitles),
                SizedBox(height: 16.h),
                _SectionTitle('Категория работ'),
                SizedBox(height: 8.h),
                _ChipRow(items: service.categoryTitles),
                SizedBox(height: 16.h),
                if (service.photos.isNotEmpty) ...<Widget>[
                  _SectionTitle('Фото'),
                  SizedBox(height: 8.h),
                  _PhotosGrid(photos: service.photos),
                ],
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
            16.h + MediaQuery.of(context).padding.bottom,
          ),
          child: PrimaryButton(
            label: 'Редактировать',
            onPressed: onEdit,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Text(
        title,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16.sp,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      );
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: items
          .map(
            (String label) => Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.primary, width: 1),
                borderRadius: BorderRadius.circular(100.r),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w400,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PhotosGrid extends StatelessWidget {
  const _PhotosGrid({required this.photos});

  final List<String> photos;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 4.r,
        crossAxisSpacing: 4.r,
      ),
      itemCount: photos.length,
      itemBuilder: (BuildContext ctx, int i) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(ctx).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => PhotoGalleryScreen(
              photos: photos,
              initialIndex: i,
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.r),
          child: isAssetPath(photos[i])
              ? Image.asset(photos[i], fit: BoxFit.cover)
              : Image.file(File(photos[i]), fit: BoxFit.cover),
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
            Text('Не удалось загрузить услугу',
                style: AppTextStyles.bodyMRegular
                    .copyWith(color: AppColors.textPrimary)),
            SizedBox(height: 12.h),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

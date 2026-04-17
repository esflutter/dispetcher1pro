import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/features/services/my_services_screen.dart';

/// Склонение «час» после предлога «от» (род. падеж).
String _hoursWord(String text) {
  final int? n = int.tryParse(text);
  if (n == null) return 'часов';
  final int mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'часов';
  if (n % 10 == 1) return 'часа';
  return 'часов';
}

/// Экран «Детали услуги».
class ServiceDetailScreen extends StatefulWidget {
  const ServiceDetailScreen({super.key, required this.serviceId});

  final String serviceId;

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  ServiceMock? get _service {
    try {
      return ServiceData.services.firstWhere((s) => s.id == widget.serviceId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _service;
    if (s == null) {
      return Scaffold(
        appBar: const DarkSubAppBar(title: 'Детали услуги'),
        body: Center(
          child: Text('Услуга не найдена', style: AppTextStyles.body),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Детали услуги'),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 88.h),
        child: AiAssistantFab(onTap: () => context.push('/assistant/chat')),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    style: AppTextStyles.titleL.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Row(
                    children: [
                      Text('₽ / час',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          )),
                      SizedBox(width: 6.w),
                      Text('${s.pricePerHour} ₽',
                          style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                      SizedBox(width: 24.w),
                      Text('₽ / день',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          )),
                      SizedBox(width: 6.w),
                      Text('${s.pricePerDay} ₽',
                          style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  Row(
                    children: [
                      Text('Минимальный заказ:',
                          style: AppTextStyles.body.copyWith(
                            fontSize: 14.sp,
                            color: AppColors.textSecondary,
                          )),
                      SizedBox(width: 6.w),
                      Text('от ${s.minOrder} ${_hoursWord(s.minOrder)}',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  Text(s.description,
                      style: AppTextStyles.body
                          .copyWith(fontSize: 14.sp, height: 1.4)),
                  SizedBox(height: 16.h),
                  _SectionTitle('Спецтехника'),
                  SizedBox(height: 8.h),
                  _ChipRow(items: s.machinery),
                  SizedBox(height: 16.h),
                  _SectionTitle('Категория работ'),
                  SizedBox(height: 8.h),
                  _ChipRow(items: s.categories),
                  SizedBox(height: 16.h),
                  _SectionTitle('Фото'),
                  SizedBox(height: 8.h),
                  _PhotosGrid(),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              boxShadow: [
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
              onPressed: () async {
                await context.push('/services/${widget.serviceId}/edit');
                if (mounted) setState(() {});
              },
            ),
          ),
        ],
      ),
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
            (label) => Container(
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
  static const _photos = [
    'assets/images/profile/photo_1.webp',
    'assets/images/profile/photo_2.webp',
    'assets/images/profile/photo_3.webp',
    'assets/images/profile/photo_4.webp',
    'assets/images/profile/photo_5.webp',
    'assets/images/profile/photo_6.webp',
  ];

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
      itemCount: _photos.length,
      itemBuilder: (_, i) => ClipRRect(
        borderRadius: BorderRadius.circular(8.r),
        child: Image.asset(
          _photos[i],
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

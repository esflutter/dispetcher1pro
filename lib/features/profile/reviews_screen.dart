import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';

class Review {
  const Review({
    required this.author,
    required this.role,
    required this.text,
    this.photos = 0,
  });
  final String author;
  final String role;
  final String text;
  final int photos;
}

class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key, this.empty = false});

  final bool empty;

  static const String _reviewText =
      'Заказчик очень ответственный и чётко ставит задачи. Предоставил все необходимые материалы и быстро отвечал на вопросы по ремонту кухни. Условия по оплате соблюдал в срок, без задержек. Работать было комфортно, все договорённости выполнялись. С удовольствием взял бы ещё подобные заказы от этого клиента.';

  static const List<Review> _mock = [
    Review(author: 'Алексей К.', role: 'Заказчик', text: _reviewText, photos: 3),
    Review(author: 'Мария С.', role: 'Заказчик', text: _reviewText, photos: 3),
    Review(author: 'Дмитрий П.', role: 'Заказчик', text: _reviewText, photos: 3),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20.r, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: Text(
          'Отзывы',
          style: AppTextStyles.titleS.copyWith(color: Colors.white),
        ),
      ),
      body: empty
          ? const _Empty()
          : ListView.separated(
              padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenH, vertical: AppSpacing.md),
              itemCount: _mock.length + 1,
              separatorBuilder: (_, _) => SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) {
                if (i == 0) return const _RatingHeader(rating: '4,5', count: 10);
                return _ReviewCard(review: _mock[i - 1]);
              },
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 128.r, color: AppColors.primary),
          SizedBox(height: AppSpacing.md),
          Text('Пока нет отзывов',
              style: AppTextStyles.body.copyWith(color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _RatingHeader extends StatelessWidget {
  const _RatingHeader({required this.rating, required this.count});
  final String rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.star_rounded, color: AppColors.ratingStar, size: 32.r),
            SizedBox(width: AppSpacing.xs),
            Text(rating,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 40.sp,
                  height: 1.0,
                  color: AppColors.textPrimary,
                )),
          ],
        ),
        SizedBox(height: AppSpacing.xs),
        Text('$count отзывов',
            style: AppTextStyles.body.copyWith(color: AppColors.textTertiary)),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final Review review;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 36.r,
              backgroundColor: AppColors.surfaceVariant,
              child: Icon(Icons.person,
                  size: 36.r, color: AppColors.textTertiary),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(review.author, style: AppTextStyles.bodyMMedium),
                  SizedBox(height: 2.h),
                  Text(review.role,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
        if (review.photos > 0) ...[
          SizedBox(height: AppSpacing.sm),
          Row(
            children: List.generate(
              review.photos,
              (i) => Padding(
                padding: EdgeInsets.only(right: i == review.photos - 1 ? 0 : 8.w),
                child: Container(
                  width: 78.w,
                  height: 78.w,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusS),
                  ),
                  child: Icon(Icons.image_outlined,
                      color: AppColors.textTertiary, size: 24.r),
                ),
              ),
            ),
          ),
        ],
        SizedBox(height: AppSpacing.sm),
        Text(review.text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body),
        SizedBox(height: AppSpacing.xxs),
        Text('Читать далее',
            style: AppTextStyles.body.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}

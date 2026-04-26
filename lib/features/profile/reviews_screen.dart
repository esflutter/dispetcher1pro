import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/plural.dart';
import 'package:dispatcher_1/core/widgets/avatar_circle.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';

import 'account_block.dart';

class Review {
  const Review({
    required this.author,
    required this.date,
    required this.rating,
    required this.text,
    this.authorAvatarUrl,
  });
  final String author;
  final String date;
  final int rating;
  final String text;
  final String? authorAvatarUrl;
}

/// Про кого открыт список отзывов. [executor] — отзывы заказчиков об
/// исполнителе (мой профиль в приложении исполнителя). [customer] —
/// отзывы исполнителей о заказчике (открывается при тапе на «N отзывов»
/// в шапке заказа или в карточке заказчика).
enum ReviewSubject { executor, customer }

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({
    super.key,
    this.subject = ReviewSubject.executor,
    this.initialRating,
    this.initialCount,
    this.targetUserId,
  });

  final ReviewSubject subject;
  /// Рейтинг и количество отзывов из карточки заказчика/исполнителя.
  /// Если заданы — используются в шапке вместо вычисленных из мока.
  final double? initialRating;
  final int? initialCount;

  /// id пользователя, чьи отзывы смотрим. Для `executor`-режима, если
  /// не задан — подставляется текущий `auth.uid()`.
  final String? targetUserId;

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  bool get _isCustomer => widget.subject == ReviewSubject.customer;

  late Future<List<Review>?> _futureDb;

  @override
  void initState() {
    super.initState();
    if (!_isCustomer) {
      ReviewsData.revision.addListener(_refresh);
    }
    _futureDb = _loadFromDb();
  }

  @override
  void dispose() {
    if (!_isCustomer) {
      ReviewsData.revision.removeListener(_refresh);
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<List<Review>?> _loadFromDb() async {
    final SupabaseClient client = Supabase.instance.client;
    final User? me = client.auth.currentUser;
    String? targetId = widget.targetUserId;
    if (targetId == null && !_isCustomer && me != null) {
      targetId = me.id;
    }
    if (targetId == null) return null;
    try {
      final List<Map<String, dynamic>> rows = await client
          .from('reviews')
          .select(
            'id, rating, text, created_at, '
            'author:profiles!reviews_author_id_fkey(name, avatar_url)',
          )
          .eq('target_id', targetId)
          .eq('subject', _isCustomer ? 'customer' : 'executor')
          .eq('is_hidden', false)
          .order('created_at', ascending: false)
          .limit(50);
      return rows.map(_dbToReview).toList();
    } catch (_) {
      return null;
    }
  }

  Review _dbToReview(Map<String, dynamic> r) {
    final dynamic author = r['author'];
    final String authorName = author is Map<String, dynamic>
        ? (author['name'] as String?) ?? 'Пользователь'
        : 'Пользователь';
    final String? authorAvatarUrl = author is Map<String, dynamic>
        ? author['avatar_url'] as String?
        : null;
    final DateTime created = DateTime.parse(r['created_at'] as String);
    final String date =
        '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year}';
    return Review(
      author: authorName,
      date: date,
      rating: r['rating'] as int,
      text: (r['text'] as String?) ?? '',
      authorAvatarUrl: authorAvatarUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Отзывы'),
      body: SafeArea(
        child: FutureBuilder<List<Review>?>(
          future: _futureDb,
          builder: (BuildContext context, AsyncSnapshot<List<Review>?> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final List<Review> reviews =
                snap.data ?? const <Review>[];
            // Источник правды для агрегата — `profiles.rating_as_*` /
            // `review_count_as_*` из карточки заказа/исполнителя. На
            // экране показываем `LIMIT 50` отзывов, поэтому считать
            // по выборке = расходиться с цифрой в карточке. Если
            // initialRating/initialCount не переданы (пустой push без
            // контекста) — fallback на подсчёт по выборке.
            final int count = widget.initialCount ?? reviews.length;
            final double aggregate = widget.initialRating ??
                (reviews.isEmpty
                    ? 0
                    : reviews.fold<int>(0, (int s, Review r) => s + r.rating) /
                        reviews.length);
            final String ratingText = aggregate > 0
                ? aggregate.toStringAsFixed(1).replaceAll('.', ',')
                : '0,0';
            return reviews.isEmpty
                ? const _Empty()
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(AppSpacing.screenH, 28.h,
                        AppSpacing.screenH, AppSpacing.md),
                    itemCount: reviews.length + 1,
                    separatorBuilder: (_, _) => SizedBox(height: 18.h),
                    itemBuilder: (BuildContext context, int i) {
                      if (i == 0) {
                        return _RatingHeader(
                            rating: ratingText, count: count);
                      }
                      return _ReviewCard(review: reviews[i - 1]);
                    },
                  );
          },
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 80.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.asset(
              'assets/icons/profile/star_empty.webp',
              width: 128.r,
              height: 128.r,
              errorBuilder: (_, _, _) => Icon(Icons.star_rounded,
                  size: 128.r, color: AppColors.primary),
            ),
            SizedBox(height: 8.h),
            Text('Пока нет отзывов',
                style: AppTextStyles.bodyMRegular
                    .copyWith(color: AppColors.textPrimary)),
          ],
        ),
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
      children: <Widget>[
        Row(
          children: <Widget>[
            Image.asset('assets/icons/profile/star_result.webp',
                width: 32.r, height: 32.r),
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
        SizedBox(height: 8.h),
        Text('$count ${reviewsWord(count)}',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textTertiary)),
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
      children: <Widget>[
        Row(
          children: <Widget>[
            AvatarCircle(size: 72.r, avatarUrl: review.authorAvatarUrl),
            SizedBox(width: 20.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(review.author, style: AppTextStyles.bodyMMedium),
                      SizedBox(width: 8.w),
                      Image.asset('assets/images/catalog/star.webp',
                          width: 20.r, height: 20.r),
                      SizedBox(width: 3.w),
                      Text('${review.rating}', style: AppTextStyles.body),
                    ],
                  ),
                  SizedBox(height: 2.h),
                  Text(review.date,
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        _ExpandableText(text: review.text),
      ],
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});
  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final TextSpan span = TextSpan(text: widget.text, style: AppTextStyles.body);
        final TextPainter tp = TextPainter(
          text: span,
          maxLines: 5,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final bool overflows = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.text,
                maxLines: _expanded ? null : 5,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: AppTextStyles.body),
            if (overflows || _expanded) ...<Widget>[
              SizedBox(height: 6.h),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded ? 'Свернуть' : 'Читать далее',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

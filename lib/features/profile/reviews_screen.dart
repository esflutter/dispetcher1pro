import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';

import 'account_block.dart';

class Review {
  const Review({
    required this.author,
    required this.date,
    required this.rating,
    required this.text,
    this.avatarIndex = 0,
  });
  final String author;
  final String date;
  final int rating;
  final String text;
  final int avatarIndex;
}

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  static const String _t1 = 'Исполнитель очень ответственный и чётко выполняет задачи. Приехал вовремя, привёз всё необходимое оборудование. Работу сделал качественно и аккуратно, убрал за собой территорию. Общение было комфортным, всегда на связи. Обязательно обращусь ещё раз. Однозначно рекомендую к сотрудничеству.';
  static const String _t2 = 'Отличный исполнитель! Всё сделал быстро и качественно. Приехал вовремя, никаких проблем. Рекомендую!';
  static const String _t3 = 'Хороший специалист, но немного затянул со сроками. Пришлось несколько раз уточнять детали по ходу работы. Тем не менее, результат получился хорошим, все замечания учёл и исправил. Техника была в отличном состоянии, работал аккуратно. В целом доволен, но хотелось бы более чёткого соблюдения графика.';
  static const String _t4 = 'Очень приятный в общении человек. Всё объяснил, показал как будет работать. Результатом полностью довольны.';
  static const String _t5 = 'Исполнитель знает своё дело. Быстро разобрался с задачей, не затягивал. Работа выполнена на совесть.';
  static const String _t1Bad = 'Сорвал сроки, работу пришлось доделывать с другим исполнителем. Связь держал плохо. Не рекомендую.';

  static const List<Review> _initialMock = <Review>[
    Review(author: 'Илья Иванов', date: '29/03/2024', rating: 5, text: _t1, avatarIndex: 1),
    Review(author: 'Анна Петрова', date: '15/02/2024', rating: 5, text: _t4, avatarIndex: 2),
    Review(author: 'Сергей Козлов', date: '10/02/2024', rating: 5, text: _t2, avatarIndex: 3),
    Review(author: 'Мария Смирнова', date: '28/01/2024', rating: 5, text: _t2, avatarIndex: 4),
    Review(author: 'Дмитрий Волков', date: '15/01/2024', rating: 5, text: _t5, avatarIndex: 5),
    Review(author: 'Елена Новикова', date: '10/01/2024', rating: 5, text: _t4, avatarIndex: 6),
    Review(author: 'Артём Соколов', date: '25/12/2023', rating: 4, text: _t1, avatarIndex: 1),
    Review(author: 'Ольга Морозова', date: '20/12/2023', rating: 4, text: _t5, avatarIndex: 2),
    Review(author: 'Павел Фёдоров', date: '10/12/2023', rating: 4, text: _t5, avatarIndex: 3),
    Review(author: 'Ирина Лебедева', date: '05/12/2023', rating: 3, text: _t3, avatarIndex: 4),
  ];

  /// Список отзывов, синхронизированный с `ReviewsData`. Сортировка:
  /// сверху самые свежие (добавленные через `receive` идут первыми,
  /// самый последний — в самом верху), ниже — дефолтные (они уже
  /// упорядочены от новых к старым).
  static List<Review> _buildReviews() {
    final List<Review> shown = <Review>[];
    final List<ReviewRecord> all = ReviewsData.all;

    for (int i = all.length - 1; i >= _initialMock.length; i--) {
      final int r = all[i].rating;
      shown.add(Review(
        author: 'Новый заказчик',
        date: 'Сегодня',
        rating: r,
        text: r == 1 ? _t1Bad : _t2,
        avatarIndex: (i % 6) + 1,
      ));
    }

    final int initialShown =
        all.length < _initialMock.length ? all.length : _initialMock.length;
    for (int i = 0; i < initialShown; i++) {
      shown.add(_initialMock[i]);
    }
    return shown;
  }

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  @override
  void initState() {
    super.initState();
    ReviewsData.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    ReviewsData.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<Review> reviews = ReviewsScreen._buildReviews();
    final int count = ReviewsData.count;
    final double avg = ReviewsData.aggregate;
    final String ratingText = count == 0
        ? '0,0'
        : avg.toStringAsFixed(1).replaceAll('.', ',');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Отзывы'),
      body: SafeArea(
        child: reviews.isEmpty
            ? const _Empty()
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.screenH, 28.h, AppSpacing.screenH, AppSpacing.md),
                itemCount: reviews.length + 1,
                separatorBuilder: (_, _) => SizedBox(height: 18.h),
                itemBuilder: (BuildContext context, int i) {
                  if (i == 0) {
                    return _RatingHeader(rating: ratingText, count: count);
                  }
                  return _ReviewCard(review: reviews[i - 1]);
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
        Text('$count отзывов',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textTertiary)),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final Review review;

  static const List<String> _avatars = <String>[
    'assets/images/profile/photo_1.webp',
    'assets/images/profile/photo_2.webp',
    'assets/images/profile/photo_3.webp',
    'assets/images/profile/photo_4.webp',
    'assets/images/profile/photo_5.webp',
    'assets/images/profile/photo_6.webp',
  ];

  @override
  Widget build(BuildContext context) {
    final String avatarPath = _avatars[(review.avatarIndex - 1) % _avatars.length];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            ClipOval(
              child: Image.asset(avatarPath,
                  width: 72.r, height: 72.r, fit: BoxFit.cover),
            ),
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/system_bar_style.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/orders/widgets/order_alerts.dart';

/// Экран «Как всё прошло?» — оценка пользователя + комментарий + кнопка.
///
/// INSERT в `public.reviews`: автор — `auth.uid()`, `target_id` = тот,
/// кого оцениваем (заказчик — для исполнителя, исполнитель — для заказчика),
/// `subject` — соответствующий enum. RLS-политика `reviews_insert_participant`
/// пропустит только если match в статусе `completed` и стороны совпадают.
/// Триггер `handle_review_insert` пересчитывает рейтинг target'а.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    this.matchId,
    this.targetId,
    this.subject = 'customer',
  });

  /// id соответствующего `order_matches` — обязательно для реального INSERT.
  /// Если null, экран работает в "демо"-режиме: показывает успех без записи.
  final String? matchId;

  /// id пользователя, которому выставляется отзыв (`profiles.id`).
  final String? targetId;

  /// 'customer' — исполнитель оценивает заказчика (приложение исполнителя).
  /// 'executor' — наоборот (приложение заказчика).
  final String subject;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  int _rating = 0;
  bool _submitting = false;
  final TextEditingController _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    if (widget.matchId != null && widget.targetId != null) {
      try {
        final SupabaseClient client = Supabase.instance.client;
        final User? user = client.auth.currentUser;
        if (user == null) {
          throw const AuthException('Нет активной сессии');
        }
        final String? text = _comment.text.trim().isEmpty
            ? null
            : _comment.text.trim();
        await client.from('reviews').insert(<String, dynamic>{
          'match_id': widget.matchId,
          'author_id': user.id,
          'target_id': widget.targetId,
          'subject': widget.subject,
          'rating': _rating,
          'text': ?text,
        });
      } on PostgrestException catch (e) {
        if (!mounted) return;
        // 23505 — уникальный индекс (match_id, author_id): отзыв на этот заказ
        // уже оставлен (например, в прошлой сессии, а локальная отметка
        // «оценено» не подтянулась). Не ошибка ввода — относимся как к «уже
        // оставлен»: помечаем заказ оценённым (pop true) и закрываем, чтобы
        // кнопка «Оставить отзыв» пропала, а не зацикливала ошибку.
        if (e.code == '23505') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Вы уже оставили отзыв на этот заказ.')),
          );
          Navigator.of(context).pop(true);
          return;
        }
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось отправить отзыв. Попробуйте ещё раз.')),
        );
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось отправить отзыв.')),
        );
        return;
      }
    }

    if (!mounted) return;
    await showReviewSentDialog(context);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bool canSubmit = _rating > 0 && !_submitting;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        // Светлая шапка — тёмные иконки статус-бара (перебиваем светлый дефолт).
        systemOverlayStyle: dispatcherSystemBarStyle(),
        elevation: 0,
        toolbarHeight: 48.h,
        centerTitle: true,
        leading: IconButton(
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
          icon: Padding(
            padding: EdgeInsets.only(left: 8.w),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary,
              size: 22.r,
            ),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Как всё прошло?',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 17.sp,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Ваш отзыв поможет другим понять, с кем лучше '
                    'работать. Оцените заказчика и при желании '
                    'оставьте комментарий.',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 24.h),
                  Text(
                    'Оцените пользователя',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 17.h),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.w),
                      for (int i = 0; i < 5; i++) ...<Widget>[
                        if (i > 0) SizedBox(width: 28.w),
                        GestureDetector(
                          onTap: () => setState(() => _rating = i + 1),
                          child: Image.asset(
                            i < _rating
                                ? 'assets/images/orders/star_filled.webp'
                                : 'assets/images/orders/star_empty.webp',
                            width: 24.r,
                            height: 24.r,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 36.h),
                  Container(
                    constraints: BoxConstraints(minHeight: 56.h),
                    decoration: BoxDecoration(
                      color: AppColors.fieldFill,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 16.h,
                    ),
                    child: TextField(
                      controller: _comment,
                      // null — поле растёт вниз по мере добавления строк.
                      maxLines: null,
                      minLines: 1,
                      maxLength: 1000,
                      inputFormatters: <TextInputFormatter>[
                        LengthLimitingTextInputFormatter(1000),
                      ],
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        // Скрываем счётчик "0/500" снизу — ограничение нужно
                        // только как валидация ввода, показывать не надо.
                        counterText: '',
                        hintText: 'Введите комментарий',
                        hintStyle: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                          color: AppColors.textTertiary,
                        ),
                      ),
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
                  color: Colors.black.withValues(alpha: 0.06),
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
              label: 'Оставить отзыв',
              enabled: canSubmit,
              onPressed: canSubmit ? _submit : null,
            ),
          ),
        ],
      ),
    );
  }
}

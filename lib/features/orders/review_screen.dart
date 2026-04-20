import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/orders/widgets/order_alerts.dart';

/// Экран «Как всё прошло?» — оценка пользователя + комментарий + кнопка.
/// Принимает `orderId` и `customerId`, чтобы при появлении бэкенда было
/// к чему привязать отзыв. Сейчас используется только вызывающим
/// экраном: он получает назад `true` и помечает заказ как прокомментированный.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, this.orderId, this.customerId});

  final String? orderId;
  final String? customerId;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  int _rating = 0;
  final TextEditingController _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // TODO(backend): отправить отзыв на сервер с orderId/customerId
    // вместе с _rating и _comment.text.trim(). Пока только закрываем
    // экран и возвращаем true — вызывающий помечает заказ как
    // прокомментированный в `_reviewedOrders`.
    await showReviewSentDialog(context);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bool canSubmit = _rating > 0;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
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

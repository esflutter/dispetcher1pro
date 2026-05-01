import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';

/// Состояния заказа исполнителя — определяют цвет и текст пилюли статуса.
enum MyOrderStatus {
  /// Исполнитель откликнулся, заказчик ещё не ответил.
  offerSent,

  /// Заказчик выбрал этого исполнителя — ждём его подтверждения.
  pendingConfirmation,

  /// Заказчик выбрал — можно связаться. Зелёная.
  accepted,

  /// Заказ выполнен.
  completed,

  /// Выбран другой исполнитель.
  rejectedOther,

  /// Заказ был отклонён.
  rejectedDeclined,

  /// Заказ был снят с публикации.
  rejectedRemoved,
}

extension MyOrderStatusX on MyOrderStatus {
  /// Базовая подпись пилюли. Для [MyOrderStatus.completed] возвращает
  /// дефолтный «Завершён. Оставьте отзыв» — т.е. как будто отзыв ещё не
  /// оставлен. Когда отзыв уже оставлен, виджет [OrderStatusPill]
  /// подменяет надпись на «Завершён» через параметр `reviewLeft`.
  String get label {
    switch (this) {
      case MyOrderStatus.offerSent:
        return 'Ожидает ответа заказчика';
      case MyOrderStatus.pendingConfirmation:
        return 'Ждёт подтверждения';
      case MyOrderStatus.accepted:
        return 'Свяжитесь с заказчиком';
      case MyOrderStatus.completed:
        return 'Завершён. Оставьте отзыв';
      case MyOrderStatus.rejectedOther:
        return 'Выбран другой исполнитель';
      case MyOrderStatus.rejectedDeclined:
        return 'Отклонён';
      case MyOrderStatus.rejectedRemoved:
        return 'Снят с публикации';
    }
  }

  Color get bg {
    switch (this) {
      case MyOrderStatus.offerSent:
        return AppColors.primaryTint;
      case MyOrderStatus.pendingConfirmation:
        return AppColors.statusPillSuccessBg;
      case MyOrderStatus.accepted:
        // statusPillInfoFg @ 10%
        return const Color(0x1A1DAEDE);
      case MyOrderStatus.completed:
      case MyOrderStatus.rejectedRemoved:
        return AppColors.categoryCard;
      case MyOrderStatus.rejectedOther:
      case MyOrderStatus.rejectedDeclined:
        return AppColors.errorTint;
    }
  }

  Color get fg {
    switch (this) {
      case MyOrderStatus.offerSent:
        return AppColors.primary;
      case MyOrderStatus.pendingConfirmation:
        return AppColors.statusPillSuccessFg;
      case MyOrderStatus.accepted:
        return AppColors.statusPillInfoFg;
      case MyOrderStatus.completed:
      case MyOrderStatus.rejectedRemoved:
        return AppColors.textMuted;
      case MyOrderStatus.rejectedOther:
      case MyOrderStatus.rejectedDeclined:
        return AppColors.error;
    }
  }
}

/// Полноразмерная пилюля статуса (на всю ширину контейнера).
/// Используется и в карточках списка, и в экране деталей.
class OrderStatusPill extends StatelessWidget {
  const OrderStatusPill({
    super.key,
    required this.status,
    this.reviewLeft = false,
  });

  final MyOrderStatus status;

  /// Для [MyOrderStatus.completed]: если отзыв уже оставлен — показываем
  /// короткое «Завершён» без призыва. По умолчанию `false`, т.е. дефолт
  /// — «Завершён. Оставьте отзыв».
  final bool reviewLeft;

  @override
  Widget build(BuildContext context) {
    final String label = (status == MyOrderStatus.completed && reviewLeft)
        ? 'Завершён'
        : status.label;
    return Container(
      width: double.infinity,
      height: 25.h,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: status.bg,
        borderRadius: BorderRadius.circular(100.r),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
          height: 1.0,
          color: status.fg,
        ),
      ),
    );
  }
}

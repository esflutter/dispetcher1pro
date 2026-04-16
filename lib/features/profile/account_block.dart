import 'package:flutter/foundation.dart';

/// Одна запись отзыва, оставленного о пользователе.
class ReviewRecord {
  const ReviewRecord({required this.rating});

  /// Оценка от 1 до 5.
  final int rating;
}

/// Глобальное состояние отзывов о пользователе + производные значения
/// (средний рейтинг, количество). При добавлении нового отзыва проверяет
/// условия блокировки и при необходимости активирует `AccountBlock`.
class ReviewsData {
  ReviewsData._();

  static final List<ReviewRecord> _reviews = <ReviewRecord>[
    // Начальный набор: средний рейтинг 4,5 при 10 отзывах.
    ReviewRecord(rating: 5),
    ReviewRecord(rating: 5),
    ReviewRecord(rating: 5),
    ReviewRecord(rating: 5),
    ReviewRecord(rating: 5),
    ReviewRecord(rating: 5),
    ReviewRecord(rating: 4),
    ReviewRecord(rating: 4),
    ReviewRecord(rating: 4),
    ReviewRecord(rating: 3),
  ];

  /// Любое изменение списка отзывов инкрементит revision —
  /// UI-слой слушает и перерисовывается.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<ReviewRecord> get all => List<ReviewRecord>.unmodifiable(_reviews);

  static int get count => _reviews.length;

  static double get aggregate {
    if (_reviews.isEmpty) return 0.0;
    final int sum = _reviews.fold<int>(0, (int a, ReviewRecord r) => a + r.rating);
    return sum / _reviews.length;
  }

  /// Пришёл новый отзыв. Добавляем в список и проверяем условия блокировки:
  /// оба должны выполняться — (1) новый отзыв на 1★ и (2) совокупный
  /// рейтинг стал меньше 2,0. При 0 отзывов (т.е. до первой оценки)
  /// блокировка невозможна.
  static void receive(int rating) {
    assert(rating >= 1 && rating <= 5, 'rating must be 1..5');
    _reviews.add(ReviewRecord(rating: rating));
    revision.value = revision.value + 1;
    final double avg = aggregate;
    if (rating == 1 && avg < 2.0) {
      AccountBlock.activate();
    }
  }

  /// Сбросить отзывы к дефолтному набору (для тестов/демо).
  static void resetToDefault() {
    _reviews
      ..clear()
      ..addAll(<ReviewRecord>[
        ReviewRecord(rating: 5),
        ReviewRecord(rating: 5),
        ReviewRecord(rating: 5),
        ReviewRecord(rating: 5),
        ReviewRecord(rating: 5),
        ReviewRecord(rating: 5),
        ReviewRecord(rating: 4),
        ReviewRecord(rating: 4),
        ReviewRecord(rating: 4),
        ReviewRecord(rating: 3),
      ]);
    revision.value = revision.value + 1;
  }
}

/// Глобальное состояние блокировки профиля. Блок активируется при
/// получении нового отзыва на 1★, если совокупный рейтинг < 2,0. Длится
/// 30 дней и автоматически снимается по истечении срока. Повторно
/// триггерится только при новом отзыве — просто «низкий рейтинг без
/// нового отзыва» блок не создаёт.
class AccountBlock {
  AccountBlock._();

  static DateTime? _until;

  /// Уведомитель для подписок UI. true — блок активен.
  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  /// Проверка с авто-снятием просроченного блока. При чтении может
  /// менять `_until` и `notifier`, если срок истёк.
  static bool get isBlocked {
    final DateTime? until = _until;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _until = null;
    if (notifier.value) notifier.value = false;
    return false;
  }

  static DateTime? get blockedUntil => isBlocked ? _until : null;

  /// Сколько дней осталось до снятия (0 если блок не активен).
  static int get daysLeft {
    final DateTime? until = blockedUntil;
    if (until == null) return 0;
    final int d = until.difference(DateTime.now()).inDays + 1;
    return d.clamp(0, 30);
  }

  /// Включить блок на 30 дней. Если уже был активен — перезапускается
  /// от момента нового триггера.
  static void activate() {
    _until = DateTime.now().add(const Duration(days: 30));
    notifier.value = true;
  }

  /// Тестовая утилита — досрочно снять блок.
  static void forceLift() {
    _until = null;
    if (notifier.value) notifier.value = false;
  }
}

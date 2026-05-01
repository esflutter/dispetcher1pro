import 'package:flutter/foundation.dart';

/// Текущий агрегированный рейтинг и количество отзывов о пользователе.
/// Источник правды — БД (`profiles.rating_as_executor` /
/// `review_count_as_executor`); этот класс просто кэширует последние
/// прочитанные значения и оповещает UI об их обновлении.
///
/// Логика реальной блокировки (`profiles.blocked_until`) живёт в БД —
/// триггер на отзыв сам выставит дату, клиент только читает её через
/// `AccountBlock.setUntil`.
class ReviewsData {
  ReviewsData._();

  static double _aggregate = 0;
  static int _count = 0;

  /// Любое обновление инкрементит revision — UI-слой слушает и
  /// перерисовывается. Имя поля сохранено для обратной совместимости с
  /// reviews_screen.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Средний рейтинг (0 = ещё нет отзывов).
  static double get aggregate => _aggregate;

  /// Количество отзывов.
  static int get count => _count;

  /// Заполнить из БД (при загрузке профиля). Если значения изменились —
  /// бампим revision, чтобы экраны, подписанные на отзывы, перерисовались.
  static void setFromDb({required double rating, required int reviewCount}) {
    if (_aggregate == rating && _count == reviewCount) return;
    _aggregate = rating;
    _count = reviewCount;
    revision.value = revision.value + 1;
  }

  /// Полный сброс — после logout/удаления аккаунта.
  static void resetToDefault() {
    if (_aggregate == 0 && _count == 0) return;
    _aggregate = 0;
    _count = 0;
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

  /// Дата снятия блока в формате «до 30 мая 2026» — для UI-плашек,
  /// чтобы пользователь видел конкретный день, а не абстрактное «30 дней».
  /// Возвращает null, если блок не активен; UI должен сначала проверять
  /// `isBlocked` и показывать плашку только тогда.
  static String? get blockedUntilText {
    final DateTime? until = blockedUntil;
    if (until == null) return null;
    final DateTime local = until.toLocal();
    return 'до ${local.day} ${_monthsRu[local.month - 1]} ${local.year} г.';
  }

  static const List<String> _monthsRu = <String>[
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

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

  /// Установить точную дату снятия (из `profiles.blocked_until` БД).
  /// Если в прошлом или null — блок снимается.
  static void setUntil(DateTime? until) {
    if (until == null || until.isBefore(DateTime.now())) {
      _until = null;
      if (notifier.value) notifier.value = false;
      return;
    }
    _until = until;
    if (!notifier.value) notifier.value = true;
  }
}

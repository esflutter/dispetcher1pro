import 'models.dart';

/// Форматирование даты/времени заказа для карточек каталога.
/// Контракт: строка в стиле «10 июня · 09:00–18:00», «12–14 июня · Весь день».

const List<String> _monthsRuGenitive = <String>[
  '', // index 1..12
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

String _fmtDay(DateTime d) => '${d.day} ${_monthsRuGenitive[d.month]}';

String _fmtHm(String time) {
  // time приходит в формате HH:mm:ss — отрезаем секунды для отображения.
  if (time.length >= 5) return time.substring(0, 5);
  return time;
}

String formatRentDate(OrderListItem o) {
  final String datePart;
  if (o.exactDate || o.dateTo == null || o.dateTo == o.dateFrom) {
    datePart = _fmtDay(o.dateFrom);
  } else {
    final DateTime to = o.dateTo!;
    if (o.dateFrom.month == to.month) {
      // Один месяц: "12–14 июня"
      datePart = '${o.dateFrom.day}–${to.day} ${_monthsRuGenitive[to.month]}';
    } else {
      datePart = '${_fmtDay(o.dateFrom)} – ${_fmtDay(to)}';
    }
  }

  final String timePart;
  if (o.wholeDay || o.timeFrom == null) {
    timePart = 'Весь день';
  } else if (o.timeTo == null) {
    timePart = 'c ${_fmtHm(o.timeFrom!)}';
  } else {
    timePart = '${_fmtHm(o.timeFrom!)}–${_fmtHm(o.timeTo!)}';
  }

  return '$datePart · $timePart';
}

/// "2 часа назад", "Сегодня в 11:30", "Вчера", "10 июня".
String formatPublishedAgo(DateTime publishedAt, {DateTime? now}) {
  final DateTime n = now ?? DateTime.now();
  final Duration d = n.difference(publishedAt);

  if (d.inMinutes < 1) return 'Только что';
  if (d.inHours < 1) {
    final int m = d.inMinutes;
    return '$m ${_minutesWord(m)} назад';
  }
  if (_isSameDay(publishedAt, n)) {
    return 'Сегодня в ${_fmtHmDateTime(publishedAt)}';
  }
  final DateTime yesterday = DateTime(n.year, n.month, n.day - 1);
  if (_isSameDay(publishedAt, yesterday)) {
    return 'Вчера';
  }
  return _fmtDay(publishedAt);
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _fmtHmDateTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _minutesWord(int n) {
  final int n10 = n % 10;
  final int n100 = n % 100;
  if (n100 >= 11 && n100 <= 14) return 'минут';
  if (n10 == 1) return 'минуту';
  if (n10 >= 2 && n10 <= 4) return 'минуты';
  return 'минут';
}

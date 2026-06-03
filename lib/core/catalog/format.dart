import 'package:dispatcher_1/core/utils/plural.dart';

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

String formatRentDate(OrderListItem o) => _formatRentDateRaw(
      dateFrom: o.dateFrom,
      dateTo: o.dateTo,
      timeFrom: o.timeFrom,
      timeTo: o.timeTo,
      exactDate: o.exactDate,
      wholeDay: o.wholeDay,
    );

/// Тот же контракт, что и [formatRentDate], но принимает [OrderDetail].
/// Переиспользуется на экране «Заказ на карте», где у нас есть только
/// деталка, а не строка ленты.
String formatRentDateFromDetail(OrderDetail o) => _formatRentDateRaw(
      dateFrom: o.dateFrom,
      dateTo: o.dateTo,
      timeFrom: o.timeFrom,
      timeTo: o.timeTo,
      exactDate: o.exactDate,
      wholeDay: o.wholeDay,
    );

String _formatRentDateRaw({
  required DateTime dateFrom,
  required DateTime? dateTo,
  required String? timeFrom,
  required String? timeTo,
  required bool exactDate,
  required bool wholeDay,
}) {
  final String datePart;
  if (exactDate || dateTo == null || dateTo == dateFrom) {
    datePart = _fmtDay(dateFrom);
  } else {
    if (dateFrom.month == dateTo.month) {
      datePart =
          '${dateFrom.day}–${dateTo.day} ${_monthsRuGenitive[dateTo.month]}';
    } else {
      datePart = '${_fmtDay(dateFrom)} – ${_fmtDay(dateTo)}';
    }
  }

  final String timePart;
  if (wholeDay || timeFrom == null) {
    timePart = 'Весь день';
  } else if (timeTo == null) {
    timePart = 'c ${_fmtHm(timeFrom)}';
  } else {
    timePart = '${_fmtHm(timeFrom)}–${_fmtHm(timeTo)}';
  }

  return '$datePart · $timePart';
}

/// "Только что", "5 минут назад", "2 часа назад", "3 дня назад".
/// Раньше для сегодня/вчера возвращались «Сегодня в 11:30» / «Вчера», и
/// рядом с «3 дня назад» пользователь видел два разных формата времени.
String formatPublishedAgo(DateTime publishedAt, {DateTime? now}) {
  final DateTime n = now ?? DateTime.now();
  final Duration d = n.difference(publishedAt);

  if (d.inMinutes < 1) return 'Только что';
  if (d.inHours < 1) {
    final int m = d.inMinutes;
    return '$m ${_minutesWord(m)} назад';
  }
  if (d.inHours < 24) {
    final int h = d.inHours;
    return '$h ${_hoursWord(h)} назад';
  }
  final int days = d.inDays;
  return '$days ${_daysWord(days)} назад';
}

String _minutesWord(int n) => pluralForms(n, 'минуту', 'минуты', 'минут');

String _hoursWord(int n) => pluralForms(n, 'час', 'часа', 'часов');

String _daysWord(int n) => pluralForms(n, 'день', 'дня', 'дней');

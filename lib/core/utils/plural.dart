/// Словоформа «отзыв» для русского склонения по числу.
/// 1, 21, 31… — «отзыв»
/// 2–4, 22–24… — «отзыва»
/// 5–20, 25–30, 0… — «отзывов»
String reviewsWord(int n) {
  final int mod100 = n.abs() % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'отзывов';
  final int mod10 = n.abs() % 10;
  if (mod10 == 1) return 'отзыв';
  if (mod10 >= 2 && mod10 <= 4) return 'отзыва';
  return 'отзывов';
}

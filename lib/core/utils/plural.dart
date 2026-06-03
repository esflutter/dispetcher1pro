/// Русское склонение по числу: выбирает форму для 1 / 2–4 / 5–0.
///   pluralForms(n, 'час', 'часа', 'часов')
/// Особый случай 11–14 — всегда форма «много» (одиннадцать часОВ).
String pluralForms(int n, String one, String few, String many) {
  final int mod100 = n.abs() % 100;
  if (mod100 >= 11 && mod100 <= 14) return many;
  final int mod10 = n.abs() % 10;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}

/// Словоформа «отзыв» для русского склонения по числу.
String reviewsWord(int n) => pluralForms(n, 'отзыв', 'отзыва', 'отзывов');

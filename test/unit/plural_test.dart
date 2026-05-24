import 'package:flutter_test/flutter_test.dart';
import 'package:dispatcher_1/core/utils/plural.dart';

/// Русское склонение для «отзыв/отзыва/отзывов». Правила:
///   1, 21, 31… → «отзыв»
///   2-4, 22-24, 32-34… → «отзыва»
///   5-20, 25-30, 0 → «отзывов»
///   Особый случай: 11-14 всегда «отзывов» (-надцать-форма).
void main() {
  group('reviewsWord', () {
    test('0 → отзывов', () {
      expect(reviewsWord(0), 'отзывов');
    });

    test('1, 21, 31, 101 → отзыв', () {
      expect(reviewsWord(1), 'отзыв');
      expect(reviewsWord(21), 'отзыв');
      expect(reviewsWord(31), 'отзыв');
      expect(reviewsWord(101), 'отзыв');
      expect(reviewsWord(1001), 'отзыв');
    });

    test('2, 3, 4, 22, 33 → отзыва', () {
      expect(reviewsWord(2), 'отзыва');
      expect(reviewsWord(3), 'отзыва');
      expect(reviewsWord(4), 'отзыва');
      expect(reviewsWord(22), 'отзыва');
      expect(reviewsWord(33), 'отзыва');
      expect(reviewsWord(104), 'отзыва');
    });

    test('5-20 → отзывов', () {
      for (int n = 5; n <= 20; n++) {
        expect(reviewsWord(n), 'отзывов', reason: 'n=$n');
      }
    });

    test('критичный кейс: 11-14 — всегда отзывов (-надцать)', () {
      expect(reviewsWord(11), 'отзывов');
      expect(reviewsWord(12), 'отзывов');
      expect(reviewsWord(13), 'отзывов');
      expect(reviewsWord(14), 'отзывов');
      expect(reviewsWord(111), 'отзывов');
      expect(reviewsWord(112), 'отзывов');
      expect(reviewsWord(113), 'отзывов');
      expect(reviewsWord(114), 'отзывов');
    });

    test('отрицательные числа — по модулю', () {
      // На UI это вряд ли встретится (счётчики неотрицательные),
      // но функция корректно работает с abs() — фиксируем поведение.
      expect(reviewsWord(-1), 'отзыв');
      expect(reviewsWord(-2), 'отзыва');
      expect(reviewsWord(-5), 'отзывов');
    });
  });
}

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dispatcher_1/core/utils/avatar_crop.dart';

/// Пересчёт выбранного круга (в координатах экрана кропа, где фото вписано
/// по cover) в прямоугольник вырезки в координатах самого изображения.
/// Эта математика должна совпадать с тем, как превью рисует CroppedAvatar,
/// иначе у автора и у других аватар разойдётся.
void main() {
  group('avatarCropRect', () {
    test('круг во весь квадратный экран → всё фото', () {
      final r = avatarCropRect(
        image: const Size(200, 200),
        center: const Offset(50, 50),
        radius: 50,
        area: const Size(100, 100),
      );
      expect(r, const Rect.fromLTWH(0, 0, 200, 200));
    });

    test('круг в центре, половина радиуса → центральный квадрат', () {
      final r = avatarCropRect(
        image: const Size(200, 200),
        center: const Offset(50, 50),
        radius: 25,
        area: const Size(100, 100),
      );
      expect(r, const Rect.fromLTWH(50, 50, 100, 100));
    });

    test('широкое фото (cover по высоте) → квадрат из центра', () {
      final r = avatarCropRect(
        image: const Size(400, 200),
        center: const Offset(50, 50),
        radius: 50,
        area: const Size(100, 100),
      );
      expect(r, const Rect.fromLTWH(100, 0, 200, 200));
    });

    test('круг у края клампится внутрь изображения', () {
      final r = avatarCropRect(
        image: const Size(200, 200),
        center: const Offset(25, 50),
        radius: 25,
        area: const Size(100, 100),
      );
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.left + r.width, lessThanOrEqualTo(200));
      expect(r.top + r.height, lessThanOrEqualTo(200));
      expect(r.width, 100);
    });

    test('квадрат не больше короткой стороны изображения', () {
      final r = avatarCropRect(
        image: const Size(300, 100),
        center: const Offset(50, 50),
        radius: 50,
        area: const Size(100, 100),
      );
      expect(r.width, lessThanOrEqualTo(100));
      expect(r.height, lessThanOrEqualTo(100));
      expect(r.width, r.height);
    });
  });
}

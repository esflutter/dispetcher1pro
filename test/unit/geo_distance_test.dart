import 'package:flutter_test/flutter_test.dart';
import 'package:dispatcher_1/core/utils/geo_distance.dart';

/// Расстояние haversine между точками. Используется для фильтра
/// «в радиусе N км» в каталоге заказов. Точность для коротких
/// расстояний (≤50 км) лучше 0.5% — заведомо превышает разброс
/// координат адресов после DaData reverse-geocoding.

void main() {
  group('haversineKm', () {
    test('точка сама с собой → 0', () {
      expect(haversineKm(55.7558, 37.6173, 55.7558, 37.6173), 0.0);
    });

    test('Москва — СПб ≈ 635 км', () {
      // Кремль (55.7520, 37.6175) ↔ Дворцовая (59.9398, 30.3146).
      final double d = haversineKm(55.7520, 37.6175, 59.9398, 30.3146);
      expect(d, closeTo(634, 5));
    });

    test('1 градус по широте ≈ 111 км', () {
      final double d = haversineKm(0, 0, 1, 0);
      expect(d, closeTo(111.19, 0.1));
    });

    test('1 градус по долготе на экваторе ≈ 111 км', () {
      final double d = haversineKm(0, 0, 0, 1);
      expect(d, closeTo(111.19, 0.1));
    });

    test('1 градус по долготе на широте 60° ≈ 55.6 км', () {
      // На высоких широтах долгота «короче» — нужно для корректного
      // bbox-фильтра в Питере/Мурманске.
      final double d = haversineKm(60, 0, 60, 1);
      expect(d, closeTo(55.6, 0.5));
    });

    test('симметрия d(A, B) == d(B, A)', () {
      final double ab = haversineKm(55.7558, 37.6173, 59.9398, 30.3146);
      final double ba = haversineKm(59.9398, 30.3146, 55.7558, 37.6173);
      expect(ab, closeTo(ba, 0.01));
    });

    test('маленькие расстояния (Москва, 2.5 км) — точность ±50 м', () {
      // Кремль ↔ Парк Горького ≈ 2.57 км (haversine, реальные координаты).
      final double d = haversineKm(55.7520, 37.6175, 55.7307, 37.6014);
      expect(d, closeTo(2.57, 0.05));
    });
  });
}

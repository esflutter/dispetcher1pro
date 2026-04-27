import 'dart:math' as math;

/// Расстояние между двумя точками на сфере (Земля) по формуле haversine.
/// Возвращает километры.
///
/// Используется для клиентского фильтра «в радиусе N км» в каталоге заказов
/// и каталоге исполнителей. Точность для малых расстояний (десятки км) —
/// в пределах 0.5%, что заведомо лучше, чем разброс координат адреса
/// после reverse-geocoding в DaData.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const double earthRadiusKm = 6371.0;
  final double dLat = _toRad(lat2 - lat1);
  final double dLon = _toRad(lon2 - lon1);
  final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _toRad(double deg) => deg * math.pi / 180.0;

import 'package:latlong2/latlong.dart';

/// Москва (центр) — Красная площадь.
const LatLng moscowCenter = LatLng(55.7558, 37.6173);

/// Детерминированно генерирует точку «в Москве» из id заказа.
///
/// Используется как мок до тех пор, пока в `orders.address` БД не появятся
/// настоящие координаты из DaData. Пока значения там — пустые/моковые,
/// карта показывает разлёт точек вокруг центра Москвы, чтобы UI не выглядел
/// сломанно (все маркеры в одной точке).
///
/// Распределение: ±~11 км по широте, ±~10 км по долготе — примерно МКАД.
/// Хеш стабилен, т.е. один и тот же заказ всегда ложится на одну и ту же
/// точку — иначе при свайпе списка маркер бы прыгал.
LatLng mockMoscowCoordsForId(String orderId) {
  final int h = orderId.hashCode;
  final int low = h & 0xFFFF;
  final int high = (h >> 16) & 0xFFFF;
  final double dLat = (low / 0xFFFF - 0.5) * 0.20;
  final double dLon = (high / 0xFFFF - 0.5) * 0.36;
  return LatLng(moscowCenter.latitude + dLat, moscowCenter.longitude + dLon);
}

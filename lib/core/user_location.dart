import 'package:geolocator/geolocator.dart';

import 'location_permission.dart';

/// Кэш геопозиции пользователя для ИИ-ассистента.
///
/// Один раз спрашиваем разрешение и берём координаты — дальше переиспользуем.
/// Нужно ассистенту, чтобы считать расстояние «от вас» точно (от реального
/// местоположения пользователя), а не от центра города.
class UserLocation {
  UserLocation._();

  static double? lat;
  static double? lng;

  static bool get has => lat != null && lng != null;

  /// Best-effort получение координат. Если они уже есть — ничего не делает.
  /// НИКОГДА не бросает: при отказе в разрешении, выключенном сервисе или
  /// таймауте просто оставляет координаты пустыми, и ассистент работает по
  /// городу/центру, как раньше.
  static Future<void> ensure() async {
    if (has) return;
    try {
      if (!await ensureLocationPermission()) return;
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      // нет геопозиции — не страшно, поиск работает по названному городу
    }
  }
}

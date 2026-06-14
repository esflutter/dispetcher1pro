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

  /// Сброс кэша при выходе из аккаунта. Без него у следующего пользователя
  /// на этом устройстве ассистент считал бы «рядом со мной» от координат
  /// предыдущего — и чужая геопозиция (ПДн) перетекла бы в новую сессию.
  /// Поднимаем «поколение»: если запрос координат ещё идёт (до 8 секунд),
  /// его результат после выхода будет отброшен и не запишется обратно.
  static void clear() {
    _generation++;
    lat = null;
    lng = null;
    _inFlight = null;
  }

  // Текущий идущий запрос координат. Прогрев при открытии экрана и ожидание
  // перед поиском могут вызвать ensure() почти одновременно — без этого оба
  // стартовали бы getCurrentPosition (двойной запрос GPS), т.к. `has` ещё
  // false у обоих. Делим один Future на всех ждущих.
  static Future<void>? _inFlight;

  // «Поколение» сессии. clear() (выход из аккаунта) его увеличивает, и
  // результат запроса координат, стартовавшего ДО выхода, отбрасывается —
  // иначе он записал бы чужую геопозицию уже в новую сессию.
  static int _generation = 0;

  /// Best-effort получение координат. Если они уже есть — ничего не делает.
  /// НИКОГДА не бросает: при отказе в разрешении, выключенном сервисе или
  /// таймауте просто оставляет координаты пустыми, и ассистент работает по
  /// городу/центру, как раньше.
  static Future<void> ensure() {
    if (has) return Future<void>.value();
    return _inFlight ??= _fetch();
  }

  static Future<void> _fetch() async {
    final int gen = _generation;
    try {
      if (!await ensureLocationPermission()) return;
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      // Пользователь вышел из аккаунта, пока шёл запрос → координаты уже не
      // его. Не записываем (иначе утекут следующему на этом устройстве).
      if (gen != _generation) return;
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      // нет геопозиции — не страшно, поиск работает по названному городу
    } finally {
      if (gen == _generation) _inFlight = null;
    }
  }
}

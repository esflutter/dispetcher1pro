import 'package:geolocator/geolocator.dart';

/// Кэш геопозиции пользователя для ИИ-ассистента.
///
/// Координаты берём ТОЛЬКО если пользователь уже разрешил геолокацию (через
/// карту, кнопку «Моё местоположение» или фильтр). Сам ассистент разрешение
/// НЕ запрашивает — иначе системный диалог всплывал бы прямо при открытии
/// чата (Apple Guideline 5.1.1(iv): запрос разрешения — только по явному
/// действию пользователя). Если права нет — координаты остаются пустыми, и
/// ассистент работает по названному городу/центру, как и задумано фолбэком.
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

  /// Best-effort: тихо берёт координаты, ЕСЛИ право на геолокацию уже выдано.
  /// Разрешение НЕ запрашивает (никаких системных диалогов). Если координаты
  /// уже есть — ничего не делает. Никогда не бросает.
  static Future<void> ensure() {
    if (has) return Future<void>.value();
    return _inFlight ??= _fetch();
  }

  /// Прежнее имя тихого варианта — оставлено для мест, что зовут его явно
  /// (фоновая сортировка каталога «ближе — выше»). Поведение совпадает с
  /// [ensure]: разрешение не запрашивается.
  static Future<void> ensureQuiet() => ensure();

  static Future<void> _fetch() async {
    final int gen = _generation;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final LocationPermission p = await Geolocator.checkPermission();
      if (p != LocationPermission.always &&
          p != LocationPermission.whileInUse) {
        return; // права ещё нет — НЕ запрашиваем, тихо выходим
      }
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
      // нет геопозиции — не страшно, ассистент работает по названному городу
    } finally {
      if (gen == _generation) _inFlight = null;
    }
  }
}

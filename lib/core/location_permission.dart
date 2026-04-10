import 'package:geolocator/geolocator.dart';

/// Запрашивает разрешение на геолокацию, если оно ещё не выдано.
///
/// Возвращает `true`, если после вызова приложение имеет доступ
/// к местоположению («whileInUse» или «always»). В противном случае
/// возвращает `false` — вызывающая сторона сама решает, показывать ли
/// карту без геолокации.
Future<bool> ensureLocationPermission() async {
  // Сервис геолокации выключен в системе — запрашивать у пользователя
  // разрешения бесполезно, сразу отдаём false.
  final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return false;

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always;
}

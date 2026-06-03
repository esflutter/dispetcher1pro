import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Открывает адрес в картах БЕЗ собственной шторки выбора.
///
/// Android: отдаём `geo:`-URI — операционная система сама показывает
/// системный выбор приложения карт (Яндекс / 2ГИС / Google и т.д.),
/// пользователь выбирает привычное. Это поведение, которого ждёт юзер.
///
/// iOS: системного выбора карт нет — открываем Apple Карты универсальной
/// ссылкой (откроется нативно), при неудаче — веб-карты Google.
Future<void> openAddressInMaps(BuildContext context, String address) async {
  final String query = Uri.encodeComponent(address);

  if (Platform.isAndroid) {
    // geo: → системный chooser приложений карт.
    if (await _tryLaunch(Uri.parse('geo:0,0?q=$query'))) return;
    // Fallback, если geo: по какой-то причине не обработан.
    if (!await _tryLaunch(Uri.parse('https://maps.google.com/?q=$query')) &&
        context.mounted) {
      _showError(context);
    }
    return;
  }

  // iOS и прочее: Apple Карты, затем веб-Google как запасной вариант.
  if (await _tryLaunch(Uri.parse('https://maps.apple.com/?q=$query'))) return;
  if (!await _tryLaunch(Uri.parse('https://maps.google.com/?q=$query')) &&
      context.mounted) {
    _showError(context);
  }
}

/// Пробуем открыть URI как внешнее приложение. launchUrl может бросить
/// PlatformException, если scheme не зарегистрирован — оборачиваем.
Future<bool> _tryLaunch(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

void _showError(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Не удалось открыть карту.')),
  );
}

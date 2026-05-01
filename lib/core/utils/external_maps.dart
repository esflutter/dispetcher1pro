import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Открывает адрес в установленном картографическом приложении.
///
/// **Android**: используется `geo:` URI — стандартная схема, которую
/// перехватывают Яндекс Карты, Google Maps, 2ГИС, MAPS.ME и прочие.
/// Если установлено несколько таких приложений, **система сама показывает
/// chooser** «Открыть с помощью» — собственный bottom-sheet не нужен.
///
/// **iOS**: системного chooser для maps Apple не предоставляет. Поскольку
/// приложение нацелено на рынок РФ, где Apple Maps работает плохо
/// (устаревшие данные, нет нормальной навигации), сначала пытаемся
/// открыть в Яндекс Картах через `yandexmaps://`-deeplink, при их
/// отсутствии — в web-Яндексе (если у юзера всё-таки стоят Я.Карты,
/// они перехватят URL Universal Link'ом; иначе Safari покажет
/// мобильную карту). Apple Maps намеренно не используем.
Future<void> openAddressInMaps(BuildContext context, String address) async {
  final String query = Uri.encodeComponent(address);
  final Uri webFallback = Uri.parse('https://yandex.ru/maps/?text=$query');

  if (Platform.isIOS) {
    // Я.Карты — лидер картографии в РФ; пробуем нативное приложение
    // первым. canLaunchUrl на iOS вернёт true только если схема
    // объявлена в LSApplicationQueriesSchemes (см. Info.plist).
    final Uri yandexApp =
        Uri.parse('yandexmaps://maps.yandex.ru/?text=$query');
    try {
      if (await canLaunchUrl(yandexApp)) {
        final bool ok =
            await launchUrl(yandexApp, mode: LaunchMode.externalApplication);
        if (ok) return;
      }
    } catch (_) {/* fall through to web */}
    try {
      await launchUrl(webFallback, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!context.mounted) return;
      _showError(context);
    }
    return;
  }

  // Android: geo:0,0?q=<address> — стандартный intent для адресов.
  // Координаты 0,0 означают «pin не задан, ищи по тексту запроса»;
  // карта-приложение сделает геокодинг само. Если установлено
  // несколько maps-apps, система покажет chooser.
  final Uri geoUri = Uri.parse('geo:0,0?q=$query');
  try {
    final bool ok =
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
    if (ok) return;
  } catch (_) {/* fall through to web fallback */}
  try {
    await launchUrl(webFallback, mode: LaunchMode.externalApplication);
  } catch (_) {
    if (!context.mounted) return;
    _showError(context);
  }
}

void _showError(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Не удалось открыть карту.')),
  );
}

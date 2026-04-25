import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Открывает адрес в приложении «Яндекс Карты», с фолбэком в
/// мобильный веб. Использует deeplink `yandexmaps://` — если на
/// устройстве не установлено приложение Yandex, откроется web-версия.
Future<void> openAddressInYandexMaps(
  BuildContext context,
  String address,
) async {
  final String query = Uri.encodeComponent(address);
  final Uri appUri = Uri.parse('yandexmaps://maps.yandex.ru/?text=$query');
  final Uri webUri = Uri.parse('https://yandex.ru/maps/?text=$query');
  try {
    final bool launched =
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
    if (launched) return;
  } catch (_) {/* fall through to web */}
  try {
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не удалось открыть карту.')),
    );
  }
}

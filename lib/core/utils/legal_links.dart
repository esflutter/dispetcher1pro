import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dispatcher_1/core/settings/settings_service.dart';

/// Открытие правовых документов (соглашение / политика) из настроек.
///
/// Ссылки лежат в `settings` (админ меняет без пересборки), но до этого
/// нигде в приложении не вызывались — документы были недоступны, хотя на
/// экранах их предлагали «прочитать». Эти хелперы закрывают дыру: на
/// регистрации и пейволлах названия документов становятся рабочими.
Future<void> openTermsUrl(BuildContext context) =>
    _open(context, () => SettingsService.instance.legalTermsUrl(),
        'Соглашение');

Future<void> openPrivacyUrl(BuildContext context) =>
    _open(context, () => SettingsService.instance.legalPrivacyUrl(),
        'Документ');

Future<void> _open(
  BuildContext context,
  Future<String> Function() getUrl,
  String what,
) async {
  String url = '';
  try {
    url = (await getUrl()).trim();
  } catch (_) {/* настройки недоступны — ниже покажем мягкую ошибку */}
  if (!context.mounted) return;
  if (url.isEmpty || !(url.startsWith('http://') || url.startsWith('https://'))) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what временно недоступен. Попробуйте позже.')),
    );
    return;
  }
  final Uri uri = Uri.parse(url);
  // Системная браузерная панель поверх приложения (Custom Tabs /
  // SFSafariViewController): документ открывается «не выходя» из приложения,
  // крестик возвращает обратно. На устройствах без поддержки панели
  // url_launcher сам откатится к доступному способу открытия.
  final bool ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не удалось открыть документ.')),
    );
  }
}

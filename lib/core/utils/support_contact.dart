import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dispatcher_1/core/settings/settings_service.dart';

/// Запасная ссылка на мессенджер поддержки. Основной источник — настройка
/// `support.messenger_url` (её админ задаёт без пересборки приложения); эта
/// константа используется лишь если настройка не прочиталась.
const String kSupportMessengerUrl = '';

/// Открыть мессенджер поддержки. Ссылку берём из настроек (админ задаёт в
/// панели), при сбое — из константы. Пусто — мягкая заглушка, чтобы тап по
/// иконке не выглядел «мёртвым».
Future<void> openSupportMessenger(BuildContext context) async {
  // Берём messenger ДО await — иначе использование context после паузы
  // вызывает предупреждение use_build_context_synchronously.
  final messenger = ScaffoldMessenger.of(context);

  String url = '';
  try {
    url = await SettingsService.instance.supportMessengerUrl();
  } catch (_) {
    url = '';
  }
  if (url.isEmpty) url = kSupportMessengerUrl.trim();
  if (url.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Ссылка на поддержку скоро появится.')),
    );
    return;
  }
  final Uri? uri = Uri.tryParse(url);
  if (uri == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Ссылка на поддержку задана неверно.')),
    );
    return;
  }
  try {
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось открыть мессенджер.')),
      );
    }
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Не удалось открыть мессенджер.')),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ссылка на мессенджер поддержки (МАХ), куда ассистент направляет
/// пользователя за «живым человеком». Пока пусто — впишите сюда ссылку,
/// когда она будет готова, и иконка в профиле начнёт её открывать.
///
/// Пример: 'https://max.ru/dispetcher_support'
const String kSupportMessengerUrl = '';

/// Открыть мессенджер поддержки. Пока ссылка не задана — мягкая заглушка,
/// чтобы тап по иконке не выглядел «мёртвым».
Future<void> openSupportMessenger(BuildContext context) async {
  // Берём messenger ДО await — иначе использование context после паузы
  // вызывает предупреждение use_build_context_synchronously.
  final messenger = ScaffoldMessenger.of(context);

  final String url = kSupportMessengerUrl.trim();
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

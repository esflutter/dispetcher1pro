import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Открывает системный номеронабиратель с подставленным номером.
/// Звонок не запускается автоматически — пользователь подтверждает
/// его уже в приложении телефона. Используется стандартная `tel:`-схема.
///
/// Если номер пустой — ничего не делает. Если платформа не может
/// открыть `tel:`-URL — показывает snackbar через переданный [context].
Future<void> dialPhone(BuildContext context, String phone) async {
  if (phone.trim().isEmpty) return;
  final String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
  final Uri uri = Uri.parse('tel:$cleaned');
  final bool ok = await launchUrl(uri);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Не удалось открыть приложение телефона'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';

/// Открывает адрес в установленном картографическом приложении.
///
/// Раньше на iOS жёстко уходило в Яндекс — у пользователя не было
/// выбора, если он предпочитает 2ГИС, Google или Apple Maps. Теперь
/// показываем bottom sheet с явным списком, и при тапе пытаемся
/// открыть нативный deeplink выбранного приложения; если оно не
/// установлено — прозрачно переходим в веб-версию того же сервиса.
///
/// На Android `geo:`-URI уже даёт системный chooser, но для
/// единообразия UX-а тоже показываем свой sheet — пользователь не
/// должен видеть две разные модалки на двух платформах.
Future<void> openAddressInMaps(BuildContext context, String address) async {
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
    ),
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(height: 8.h),
            Center(
              child: Container(
                width: 36.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'Открыть адрес в',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8.h),
            _MapTile(
              label: 'Яндекс.Карты',
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _openInYandex(context, address);
              },
            ),
            _MapTile(
              label: '2ГИС',
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _openIn2gis(context, address);
              },
            ),
            _MapTile(
              label: 'Google Карты',
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _openInGoogle(context, address);
              },
            ),
            if (Platform.isIOS)
              _MapTile(
                label: 'Apple Карты',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _openInAppleMaps(context, address);
                },
              ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    ),
  );
}

/// Пробуем открыть URI как внешнее приложение. launchUrl на Android
/// может бросить PlatformException, если scheme не зарегистрирован —
/// оборачиваем в try/catch и возвращаем bool.
Future<bool> _tryLaunch(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

Future<void> _openInYandex(BuildContext context, String address) async {
  final String query = Uri.encodeComponent(address);
  final Uri native = Uri.parse('yandexmaps://maps.yandex.ru/?text=$query');
  if (await _tryLaunch(native)) return;
  final Uri web = Uri.parse('https://yandex.ru/maps/?text=$query');
  if (!await _tryLaunch(web) && context.mounted) _showError(context);
}

Future<void> _openIn2gis(BuildContext context, String address) async {
  final String query = Uri.encodeComponent(address);
  // 2ГИС не имеет открытого deeplink на поиск по тексту,
  // используем web с автозапуском в нативе через Universal Link.
  final Uri native = Uri.parse('dgis://2gis.ru/search/$query');
  if (await _tryLaunch(native)) return;
  final Uri web = Uri.parse('https://2gis.ru/search/$query');
  if (!await _tryLaunch(web) && context.mounted) _showError(context);
}

Future<void> _openInGoogle(BuildContext context, String address) async {
  final String query = Uri.encodeComponent(address);
  final Uri native = Platform.isIOS
      ? Uri.parse('comgooglemaps://?q=$query')
      : Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
  if (await _tryLaunch(native)) return;
  // Web-fallback для iOS, если comgooglemaps:// не зарегистрирован.
  if (Platform.isIOS) {
    final Uri web =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (!await _tryLaunch(web) && context.mounted) _showError(context);
  } else if (context.mounted) {
    _showError(context);
  }
}

Future<void> _openInAppleMaps(BuildContext context, String address) async {
  final String query = Uri.encodeComponent(address);
  final Uri native = Uri.parse('maps://?q=$query');
  if (!await _tryLaunch(native) && context.mounted) _showError(context);
}

void _showError(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Не удалось открыть карту.')),
  );
}

/// Строчка в bottom-sheet выбора картографического приложения.
/// Большая зона нажатия (минимум 48dp), текст слева, без иконок —
/// чтобы не зависеть от бренд-логотипов сторонних приложений.
class _MapTile extends StatelessWidget {
  const _MapTile({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16.sp,
              fontWeight: FontWeight.w500,
              height: 1.40,
            ),
          ),
        ),
      ),
    );
  }
}

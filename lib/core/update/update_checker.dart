import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dispatcher_1/core/settings/settings_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

enum _UpdateLevel { none, optional, forced }

/// Проверка обновлений приложения. Сравнивает версию установленного
/// приложения с двумя значениями из серверных настроек:
///   • `app.pro_min_version`    — ниже неё работать нельзя
///     (принудительное обновление, попап без «Позже»);
///   • `app.pro_latest_version` — ниже неё мягко предлагаем обновиться.
///
/// По умолчанию обе настройки «0.0.0» → попап не показывается, пока админ
/// не задаст реальные версии. Любая ошибка/офлайн — тихо пропускаем
/// (не мешаем работе). Магазины зашиты для ЭТОГО приложения (PRO).
class UpdateChecker {
  UpdateChecker._();

  /// Один показ за запуск процесса — чтобы пересоздание shell не дёргало
  /// попап повторно.
  static bool _checkedThisLaunch = false;

  static const String _iosAppId = '6781102906';
  static const String _androidPackage = 'com.dispetcher1.dispetcher_1';

  static String get _storeUrl => Platform.isIOS
      ? 'https://apps.apple.com/app/id$_iosAppId'
      : 'https://play.google.com/store/apps/details?id=$_androidPackage';

  static Future<void> maybePromptOnce(BuildContext context) async {
    if (_checkedThisLaunch) return;
    _checkedThisLaunch = true;
    try {
      final ({String min, String latest}) v =
          await SettingsService.instance.appVersions();
      final PackageInfo info = await PackageInfo.fromPlatform();
      final _UpdateLevel level = _evaluate(info.version, v.min, v.latest);
      if (level == _UpdateLevel.none) return;
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: level == _UpdateLevel.optional,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        builder: (_) => _UpdateDialog(
          forced: level == _UpdateLevel.forced,
          onUpdate: _openStore,
        ),
      );
    } catch (_) {
      // Офлайн / нет настройки / нет package_info — молча пропускаем.
    }
  }

  static Future<void> _openStore() async {
    try {
      await launchUrl(Uri.parse(_storeUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      // Магазин не открылся — попап остаётся, пользователь попробует ещё.
    }
  }

  static _UpdateLevel _evaluate(String current, String min, String latest) {
    if (compareVersions(current, min) < 0) return _UpdateLevel.forced;
    if (compareVersions(current, latest) < 0) return _UpdateLevel.optional;
    return _UpdateLevel.none;
  }
}

/// Сравнивает версии вида «X.Y.Z». Возвращает отрицательное число, если
/// a меньше b; ноль, если равны; положительное, если a больше b.
/// Берёт ядро до «+» (build) и «-» (pre-release); недостающие части — 0,
/// нечисловые — 0. Вынесено отдельной функцией для юнит-тестов.
int compareVersions(String a, String b) {
  final List<int> pa = _versionParts(a);
  final List<int> pb = _versionParts(b);
  final int n = pa.length > pb.length ? pa.length : pb.length;
  for (int i = 0; i < n; i++) {
    final int x = i < pa.length ? pa[i] : 0;
    final int y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

List<int> _versionParts(String v) {
  final String core = v.split('+').first.split('-').first.trim();
  if (core.isEmpty) return const <int>[0];
  return core
      .split('.')
      .map((String s) => int.tryParse(s.trim()) ?? 0)
      .toList();
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.forced, required this.onUpdate});
  final bool forced;
  final Future<void> Function() onUpdate;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Принудительное обновление — диалог нельзя закрыть (ни кнопкой
      // «назад», ни тапом по фону): единственный путь дальше — обновиться.
      canPop: !forced,
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: 16.w),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 20.h),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                forced ? 'Нужно обновить приложение' : 'Доступно обновление',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 10.h),
              Text(
                forced
                    ? 'Эта версия больше не поддерживается. Обновите приложение, чтобы продолжить.'
                    : 'Вышла новая версия с улучшениями. Рекомендуем обновиться.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w400,
                  height: 1.35,
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(height: 20.h),
              PrimaryButton(
                label: 'Обновить',
                onPressed: () async {
                  await onUpdate();
                  // Для мягкого обновления закрываем попап после ухода в
                  // магазин; для принудительного — оставляем открытым.
                  if (!forced && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              if (!forced) ...<Widget>[
                SizedBox(height: 8.h),
                SecondaryButton(
                  label: 'Позже',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

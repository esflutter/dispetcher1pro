import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';

/// Плашка «Нет доступа к интернету» с кнопкой «Обновить».
///
/// Используется глобальным [NetworkStatus]-гуардом, чтобы показывать
/// одно и то же состояние на любом экране приложения.
class NoInternetView extends StatefulWidget {
  const NoInternetView({super.key, required this.onRetry});

  /// Колбэк проверки сети. Пока future не завершится, на месте кнопки
  /// «Обновить» показывается спиннер. Если по итогу сеть всё ещё
  /// недоступна, плашка остаётся, а спиннер пропадает.
  final Future<void> Function() onRetry;

  @override
  State<NoInternetView> createState() => _NoInternetViewState();
}

class _NoInternetViewState extends State<NoInternetView> {
  bool _loading = false;

  Future<void> _handleTap() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      // Минимальная задержка, чтобы спиннер успел показаться, даже если
      // сама проверка возвращается мгновенно.
      await Future.wait<void>(<Future<void>>[
        widget.onRetry(),
        Future<void>.delayed(const Duration(milliseconds: 700)),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.asset(
              'assets/images/catalog/no_internet.webp',
              width: 136.r,
              height: 136.r,
              fit: BoxFit.contain,
            ),
            SizedBox(height: 0.h),
            Text(
              'Нет доступа к интернету',
              style: AppTextStyles.bodyMRegular,
            ),
            SizedBox(height: 19.h),
            GestureDetector(
              onTap: _handleTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 24.w, vertical: 8.h),
                child: SizedBox(
                  height: 28.h,
                  child: Center(
                    child: _loading
                        ? SizedBox(
                            width: 23.r,
                            height: 23.r,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primary),
                            ),
                          )
                        : Text(
                            'Обновить',
                            style: AppTextStyles.h1.copyWith(fontSize: 18.sp),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

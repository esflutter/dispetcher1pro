import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';

/// Источник, выбранный пользователем в [PhotoPickerSheet].
enum PhotoSource { limited, full, denied }

/// Алерт «Приложение запрашивает доступ к Фото» (макет «Алерт галерея»).
class PhotoPickerSheet extends StatelessWidget {
  const PhotoPickerSheet({super.key});

  static Future<PhotoSource?> show(BuildContext context) {
    return showDialog<PhotoSource>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => const PhotoPickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Material(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 16.h),
                child: Text(
                  'Приложение запрашивает доступ к Фото',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMMedium,
                ),
              ),
              const _Sep(),
              _AlertAction(
                label: 'Ограниченный доступ',
                onTap: () =>
                    Navigator.of(context).pop(PhotoSource.limited),
              ),
              const _Sep(),
              _AlertAction(
                label: 'Полный доступ',
                onTap: () => Navigator.of(context).pop(PhotoSource.full),
              ),
              const _Sep(),
              _AlertAction(
                label: 'Не предоставлять',
                onTap: () => Navigator.of(context).pop(PhotoSource.denied),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: AppColors.divider);
}

class _AlertAction extends StatelessWidget {
  const _AlertAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 44.h,
        child: Center(
          child: Text(
            label,
            style: AppTextStyles.body.copyWith(color: AppColors.iosBlue),
          ),
        ),
      ),
    );
  }
}

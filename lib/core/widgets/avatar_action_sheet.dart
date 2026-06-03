import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';

/// Действие, выбранное в шторке аватара.
enum AvatarAction { update, delete }

/// Шторка действий с аватаром: «Обновить фото» / «Удалить фото».
/// Показывается по тапу на аватар, когда фото уже загружено. Возвращает
/// выбранное действие или `null`, если шторку закрыли.
Future<AvatarAction?> showAvatarActionSheet(BuildContext context) {
  return showModalBottomSheet<AvatarAction>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
    ),
    builder: (BuildContext ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(height: 10.h),
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 8.h),
            ListTile(
              leading: Icon(Icons.image_outlined,
                  color: AppColors.textPrimary, size: 24.r),
              title: Text(
                'Обновить фото',
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textPrimary),
              ),
              onTap: () => Navigator.of(ctx).pop(AvatarAction.update),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red, size: 24.r),
              title: Text(
                'Удалить фото',
                style: AppTextStyles.body.copyWith(color: Colors.red),
              ),
              onTap: () => Navigator.of(ctx).pop(AvatarAction.delete),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      );
    },
  );
}

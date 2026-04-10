import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';

/// Карточка категории каталога — фон, иллюстрация (asset) или иконка-fallback,
/// подпись снизу. Совпадает с Figma node 8:2139 (cards 168×112 + подпись 14sp).
class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.title,
    this.background = AppColors.categoryCard,
    this.imageAsset,
    this.imageTight = false,
    this.icon,
    this.onTap,
  });

  final String title;
  final Color background;
  final String? imageAsset;
  /// Если true — картинка без встроенных полей, показываем её
  /// уменьшенной в правом нижнем углу (как старые webp-иллюстрации).
  final bool imageTight;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20.r),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned.fill(
              child: imageAsset != null
                  ? (imageTight
                      ? Align(
                          alignment: Alignment.bottomRight,
                          child: FractionallySizedBox(
                            widthFactor: 0.62,
                            heightFactor: 0.78,
                            child: Padding(
                              padding:
                                  EdgeInsets.only(right: 6.w, bottom: 6.h),
                              child: Image.asset(
                                imageAsset!,
                                fit: BoxFit.contain,
                                alignment: Alignment.bottomRight,
                              ),
                            ),
                          ),
                        )
                      : Image.asset(
                      imageAsset!,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (BuildContext _, Object _, StackTrace? _) => Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: EdgeInsets.only(right: 16.w, bottom: 12.h),
                          child: Icon(
                            icon ?? Icons.image_outlined,
                            size: 56.r,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ))
                  : Center(
                      child: Icon(
                        icon ?? Icons.image_outlined,
                        size: 56.r,
                        color: AppColors.textPrimary,
                      ),
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12.w, 16.h, 12.w, 10.h),
              child: Text(
                title,
                style: AppTextStyles.chip,
                textAlign: TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    this.imageScale = 1.0,
    this.imageOffset = Offset.zero,
    this.icon,
    this.onTap,
  });

  static const double _baseWidthFactor = 0.62;
  static const double _baseHeightFactor = 0.78;

  final String title;
  final Color background;
  final String? imageAsset;
  /// Множитель базовых широты/высоты иллюстрации (1.0 — по умолчанию).
  /// Нужен, чтобы точечно подогнать визуальный вес отдельных ассетов.
  final double imageScale;
  /// Пиксельный сдвиг иллюстрации (px). Применяется через Transform.translate.
  final Offset imageOffset;
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
                  ? Align(
                      alignment: Alignment.bottomRight,
                      child: FractionallySizedBox(
                        widthFactor: _baseWidthFactor * imageScale,
                        heightFactor: _baseHeightFactor * imageScale,
                        child: Transform.translate(
                          offset: imageOffset,
                          child: Padding(
                            padding: EdgeInsets.only(right: 2.w, bottom: 2.h),
                            child: Image.asset(
                              imageAsset!,
                              fit: BoxFit.contain,
                              alignment: Alignment.bottomRight,
                              errorBuilder:
                                  (BuildContext _, Object _, StackTrace? _) =>
                                      Icon(
                                icon ?? Icons.image_outlined,
                                size: 56.r,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
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

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';

/// Крестик закрытия в правом верхнем углу диалога/sheet'а.
///
/// Раньше во всех диалогах стоял `GestureDetector` + `Icon(close_rounded,
/// size: 22.r)` без обёртки в `SizedBox`. Hit-area = размер самой иконки,
/// то есть ~22dp, что заметно меньше Material/Android минимума 44dp.
/// На пальце по такому крестику попасть трудно — особенно на маленьких
/// телефонах. Здесь вынесено в общий виджет: иконка остаётся 22, но
/// прозрачная зона нажатия расширена до 44×44.
class DialogCloseButton extends StatelessWidget {
  const DialogCloseButton({
    super.key,
    required this.onTap,
    this.color,
    this.iconSize,
    this.iconData,
  });

  /// Что вызывать на тап. Обычно — `Navigator.of(context).maybePop()`.
  final VoidCallback onTap;

  /// Цвет иконки. Если не задан — берём `AppColors.textPrimary`.
  /// На светлом фоне диалога это даст естественный тёмный крестик;
  /// на тёмном фоне (paywall с картинкой) передавайте `Colors.white`.
  final Color? color;

  /// Размер самой иконки. По умолчанию 22.r — то же значение, что
  /// было раскидано по 30+ диалогам, для визуальной совместимости.
  final double? iconSize;

  /// Иконка. По умолчанию — `Icons.close_rounded` (то же, что было
  /// в исходных диалогах). Можно подменить на `Icons.close` или
  /// картинку из ассетов через `IconData`.
  final IconData? iconData;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44.r,
      height: 44.r,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(
            iconData ?? Icons.close_rounded,
            size: iconSize ?? 22.r,
            color: color ?? AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

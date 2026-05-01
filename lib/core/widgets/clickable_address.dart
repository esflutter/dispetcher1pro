import 'package:flutter/material.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/utils/external_maps.dart';

/// Виджет «Кликабельный адрес»: подчёркнутый текст, по тапу показывает
/// bottom-sheet с выбором карт (Яндекс Карты / Google Maps / 2ГИС) и
/// открывает выбранное приложение (или web-версию). Обёртка вокруг
/// обычного [Text] с собственным расписанием стилей — можно передать
/// [baseStyle] (например, стиль заголовка/body).
class ClickableAddress extends StatelessWidget {
  const ClickableAddress(
    this.address, {
    super.key,
    this.baseStyle,
    this.maxLines,
  });

  final String address;
  final TextStyle? baseStyle;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = (baseStyle ?? const TextStyle()).copyWith(
      decoration: TextDecoration.underline,
      color: baseStyle?.color ?? AppColors.textPrimary,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openAddressInMaps(context, address),
      child: Text(
        address,
        style: style,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      ),
    );
  }
}

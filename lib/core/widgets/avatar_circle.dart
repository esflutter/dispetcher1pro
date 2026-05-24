import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Круглая аватарка пользователя.
///
/// Если [avatarUrl] непустой — грузит сетевое фото через
/// [CachedNetworkImage] (диск + RAM-кэш, чтобы аватар не перезагружался
/// при каждом rebuild). На ошибке загрузки или при пустом URL —
/// показывает серый круг с дефолтной иконкой человечка (тот же стиль,
/// что на экране регистрации).
class AvatarCircle extends StatelessWidget {
  const AvatarCircle({
    super.key,
    required this.size,
    this.avatarUrl,
  });

  final double size;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final bool hasUrl =
        avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    // Декодим и кэшим уменьшенную копию, а не оригинал. Без cacheWidth
    // картинка 1024×1024 декодируется в RAM на ~4 МБ ради 100×100-кружка.
    // Без maxWidthDiskCache папка `cached_network_image` за полгода
    // активного использования набивается оригиналами по 3–4 МБ каждый.
    final int targetPx = (size * 3).round().clamp(64, 512);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFEAEAEA),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.hardEdge,
      child: hasUrl
          ? CachedNetworkImage(
              imageUrl: avatarUrl!,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 120),
              memCacheWidth: targetPx,
              memCacheHeight: targetPx,
              maxWidthDiskCache: targetPx,
              maxHeightDiskCache: targetPx,
              errorWidget: (_, _, _) => _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() => Image.asset(
        'assets/icons/ui/avatar.webp',
        fit: BoxFit.cover,
      );
}

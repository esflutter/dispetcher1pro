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

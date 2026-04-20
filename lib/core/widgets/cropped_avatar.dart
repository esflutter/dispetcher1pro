import 'dart:io';

import 'package:flutter/material.dart';

import 'package:dispatcher_1/core/utils/photo_source.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';

/// Аватарка с применением кропа из [CropResult].
/// Если [cropResult] == null, берёт [CropResult.saved].
/// Если и он null — показывает фото по центру без кропа.
class CroppedAvatar extends StatelessWidget {
  const CroppedAvatar({
    super.key,
    required this.size,
    this.cropResult,
  });

  final double size;
  final CropResult? cropResult;

  Widget _buildSourceImage(String? imagePath) {
    if (imagePath == null) {
      return Image.asset('assets/icons/ui/avatar.webp', fit: BoxFit.cover);
    }
    return isAssetPath(imagePath)
        ? Image.asset(imagePath, fit: BoxFit.cover)
        : Image.file(File(imagePath), fit: BoxFit.cover);
  }

  @override
  Widget build(BuildContext context) {
    final crop = cropResult ?? CropResult.saved;
    final double displayRadius = size / 2;

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: crop != null
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final double scale = displayRadius / crop.radius;
                  final double tx =
                      displayRadius - crop.center.dx * scale;
                  final double ty =
                      displayRadius - crop.center.dy * scale;
                  return OverflowBox(
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    alignment: Alignment.topLeft,
                    child: Transform(
                      transform: Matrix4(
                        scale, 0, 0, 0, //
                        0, scale, 0, 0, //
                        0, 0, 1, 0, //
                        tx, ty, 0, 1, //
                      ),
                      child: SizedBox(
                        width: crop.screenSize.width,
                        height: crop.screenSize.height,
                        child: _buildSourceImage(crop.imagePath),
                      ),
                    ),
                  );
                },
              )
            : Image.asset(
                'assets/icons/ui/avatar.webp',
                fit: BoxFit.cover,
                width: size,
                height: size,
              ),
      ),
    );
  }
}

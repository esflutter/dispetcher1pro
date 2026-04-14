import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/widgets/primary_button.dart';

class CropResult {
  final Offset center;
  final double radius;
  final Size screenSize;

  CropResult(this.center, this.radius, this.screenSize);

  /// Глобальное хранилище последнего результата кропа (до появления бэкенда).
  static CropResult? saved;

  /// Имя пользователя, введённое при регистрации.
  static String userName = 'Александр Иванов';

  /// Телефон пользователя, введённый при регистрации.
  static String userPhone = '+7 999 123-45-67';
}

class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({super.key});

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  Offset _center = Offset.zero;
  double _radius = 0;
  double _baseRadius = 0;
  Size _imageAreaSize = Size.zero;
  bool _initialized = false;

  void _ensureInit(Size areaSize) {
    if (!_initialized && areaSize.width > 0 && areaSize.height > 0) {
      _imageAreaSize = areaSize;
      _center = Offset(areaSize.width / 2, areaSize.height / 2);
      _radius = areaSize.width * 0.48;
      _initialized = true;
    }
  }

  void _onDone() {
    Navigator.of(context).pop(CropResult(_center, _radius, _imageAreaSize));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final double topInset = MediaQuery.of(context).padding.top + 40.h;
    final double bottomPanelHeight = size.height * 0.24;
    final double imageBottomInset = bottomPanelHeight - 24.r;
    final Size imageAreaSize = Size(size.width, size.height - topInset - imageBottomInset);
    _ensureInit(imageAreaSize);
    _imageAreaSize = imageAreaSize;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. Статичное фото — full bleed под верхней панелью
          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            bottom: imageBottomInset,
            child: Image.asset(
              'assets/images/user1.png',
              fit: BoxFit.cover,
            ),
          ),

          // 2. Двигающаяся маска + жесты в области фото
          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            bottom: imageBottomInset,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) {
                _baseRadius = _radius;
              },
              onScaleUpdate: (details) {
                setState(() {
                  final double maxR = imageAreaSize.shortestSide / 2;
                  _radius = (_baseRadius * details.scale).clamp(50.0, maxR);
                  _center += details.focalPointDelta;
                  _center = Offset(
                    _center.dx.clamp(_radius, imageAreaSize.width - _radius),
                    _center.dy.clamp(_radius, imageAreaSize.height - _radius),
                  );
                });
              },
              child: CustomPaint(
                painter: _CircleMaskPainter(
                  overlayColor: Colors.black.withValues(alpha: 0.35),
                  center: _center,
                  radius: _radius,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),

          // 4. Верхняя панель (Назад) — на белом фоне
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: EdgeInsets.zero,
                child: IconButton(
                  icon: Image.asset('assets/icons/ui/back.webp', width: 24.r, height: 24.r),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),

          // 5. Нижняя панель (Готово) — белая, без скругления
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              height: bottomPanelHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
              ),
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, bottomPanelHeight * 0.48),
              alignment: Alignment.bottomCenter,
              child: PrimaryButton(
                label: 'Готово',
                enabled: true,
                onPressed: _onDone,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleMaskPainter extends CustomPainter {
  _CircleMaskPainter({
    required this.overlayColor,
    required this.center,
    required this.radius,
  });

  final Color overlayColor;
  final Offset center;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Path backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final Path circlePath = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    final Path maskPath = Path.combine(PathOperation.difference, backgroundPath, circlePath);

    final Paint paint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(maskPath, paint);
  }

  @override
  bool shouldRepaint(covariant _CircleMaskPainter oldDelegate) {
    return oldDelegate.center != center || oldDelegate.radius != radius;
  }
}

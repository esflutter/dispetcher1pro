import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// «Впекание» выбранной в кроп-экране области в сам файл аватара.
///
/// Раньше кроп жил только как параметры круга в памяти автора, а в хранилище
/// уходило исходное фото целиком — поэтому обрезку видел только автор и только
/// до перезапуска, а все остальные получали фото без зума/сдвига. Здесь мы
/// один раз вырезаем выбранную область в квадратный файл, и его уже грузим в
/// хранилище: тогда аватар одинаков у всех и не зависит от размера экрана.

/// Прямоугольник вырезки в координатах ИСХОДНОГО изображения, соответствующий
/// выбранному кругу (центр/радиус заданы в координатах области показа, где фото
/// вписано по правилу cover — ровно как в кроп-экране и в превью-аватаре).
///
/// Чистая функция, без ввода-вывода — покрыта юнит-тестами.
Rect avatarCropRect({
  required Size image,
  required Offset center,
  required double radius,
  required Size area,
}) {
  final double iw = image.width;
  final double ih = image.height;
  // Cover-вписывание исходника в область показа: фото масштабируется так,
  // чтобы покрыть область целиком, и центрируется.
  final double coverScale = math.max(area.width / iw, area.height / ih);
  final double offX = (area.width - iw * coverScale) / 2;
  final double offY = (area.height - ih * coverScale) / 2;
  // Центр и радиус круга в координатах исходного изображения.
  final double srcCx = (center.dx - offX) / coverScale;
  final double srcCy = (center.dy - offY) / coverScale;
  final double srcR = radius / coverScale;
  // Квадрат вокруг круга, но не больше самого изображения и в его пределах.
  final double side = (srcR * 2).clamp(1.0, math.min(iw, ih));
  final double left = (srcCx - side / 2).clamp(0.0, iw - side);
  final double top = (srcCy - side / 2).clamp(0.0, ih - side);
  return Rect.fromLTWH(left, top, side, side);
}

/// Рендерит обрезанный по выбранному кругу квадратный аватар во временный
/// PNG-файл. Дальше его сжимает и грузит [StorageService.uploadAvatar].
/// Вызывающий должен удалить файл после загрузки.
Future<File> renderCroppedAvatar({
  required String sourcePath,
  required Offset center,
  required double radius,
  required Size area,
  int outSize = 1024,
}) async {
  final Uint8List bytes = await File(sourcePath).readAsBytes();
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image src = frame.image;
  try {
    final Rect srcRect = avatarCropRect(
      image: Size(src.width.toDouble(), src.height.toDouble()),
      center: center,
      radius: radius,
      area: area,
    );
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Rect dst =
        Rect.fromLTWH(0, 0, outSize.toDouble(), outSize.toDouble());
    // Аватар везде показывается кругом, а файл лежит в ПУБЛИЧНОМ бакете.
    // Обрезаем по кругу, чтобы в файле была только видимая область, а углы
    // (≈пятая часть площади с окружением вокруг лица) не были доступны по
    // прямой ссылке.
    canvas.clipPath(Path()..addOval(dst));
    canvas.drawImageRect(
      src,
      srcRect,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    final ui.Image out = await recorder.endRecording().toImage(outSize, outSize);
    try {
      final ByteData? png = await out.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw StateError('avatar crop: toByteData returned null');
      }
      final File file = File(
        '${Directory.systemTemp.path}/avatar_'
        '${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return file;
    } finally {
      out.dispose();
    }
  } finally {
    src.dispose();
    codec.dispose();
  }
}

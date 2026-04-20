import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Утилиты для работы с фото: пикер с устройства и универсальный
/// [ImageProvider] для путей, которые могут быть либо ассетом
/// (`assets/...`), либо реальным файлом на устройстве.

/// Единый инстанс пикера.
final ImagePicker _picker = ImagePicker();

/// Re-entrance guard: пока открыт системный пикер, повторные вызовы
/// игнорируются. Без этого пользователь, тапнув «Добавить фото» несколько
/// раз подряд на медленном устройстве, ловил бы параллельные окна/каскад
/// снэкбаров.
bool _pickInProgress = false;

/// Коды ошибок от image_picker, которые соответствуют отказу системы
/// в доступе к галерее/камере. Вытаскиваем их в константы, чтобы одно
/// и то же сопоставление «код → сообщение» работало в обоих пикерах.
const Set<String> _deniedCodes = <String>{
  'photo_access_denied',
  'camera_access_denied',
  'permission_denied',
};

void _showDeniedSnack(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Нет доступа к галерее. Разрешите его в настройках, '
        'чтобы прикрепить фото.',
      ),
      duration: Duration(seconds: 3),
    ),
  );
}

/// Выбрать одно изображение из галереи. Ограничиваем размер и
/// качество — чтобы не таскать по памяти и сети оригиналы по
/// десяткам мегабайт.
///
/// Если передан [context] — при отказе системы в доступе к галерее
/// пикер сам покажет snackbar «Нет доступа к галерее…». Без контекста
/// просто вернёт `null`, и отказ неотличим от отмены пользователя.
Future<String?> pickImageFromGallery({BuildContext? context}) async {
  if (_pickInProgress) return null;
  _pickInProgress = true;
  try {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    return file?.path;
  } on PlatformException catch (e) {
    if (_deniedCodes.contains(e.code) &&
        context != null &&
        context.mounted) {
      _showDeniedSnack(context);
    }
    return null;
  } finally {
    _pickInProgress = false;
  }
}

/// Выбрать несколько изображений из галереи. Нативный пикер покажет
/// мультивыбор. Возвращает все выбранные пути — вызывающий код сам
/// решает, что делать с лишними (лимит `[limit]` честно соблюдается
/// далеко не во всех галереях, например на Android <13 или в
/// вендорских).
///
/// Поведение при отказе в доступе — как у [pickImageFromGallery].
Future<List<String>> pickMultipleImagesFromGallery({
  int? limit,
  BuildContext? context,
}) async {
  if (limit != null && limit <= 0) return const <String>[];
  if (_pickInProgress) return const <String>[];
  _pickInProgress = true;
  try {
    final List<XFile> files = await _picker.pickMultiImage(
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
      limit: limit,
    );
    return files.map((XFile f) => f.path).toList();
  } on PlatformException catch (e) {
    if (_deniedCodes.contains(e.code) &&
        context != null &&
        context.mounted) {
      _showDeniedSnack(context);
    }
    return const <String>[];
  } finally {
    _pickInProgress = false;
  }
}

/// True, если путь указывает на ассет приложения, а не файл.
bool isAssetPath(String path) => path.startsWith('assets/');

/// Отдаёт нужный [ImageProvider] для картинки. Для ассетов —
/// [AssetImage], для файлов — [FileImage]. Используется в виджетах,
/// которые должны показывать и моковые ассеты, и реально
/// загруженные пользователем фото.
ImageProvider photoProvider(String path) =>
    isAssetPath(path) ? AssetImage(path) : FileImage(File(path));

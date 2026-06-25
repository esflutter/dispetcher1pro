import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/storage/storage_service.dart';

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
        'Не удалось добавить фото без доступа к галерее.',
      ),
      duration: Duration(seconds: 3),
    ),
  );
}

/// Снэкбар «Файл слишком большой, максимум N МБ». Показываем сразу при
/// пике, не дожидаясь попытки upload — иначе пользователь узнает о
/// проблеме только при «Создать заказ» через 5 секунд после нажатия.
void _showTooLargeSnack(BuildContext context, double actualMb) {
  final int maxMb = StorageService.maxFileBytes ~/ (1024 * 1024);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Фото ${actualMb.toStringAsFixed(1)} МБ — слишком большое, '
        'максимум $maxMb МБ.',
      ),
      duration: const Duration(seconds: 3),
    ),
  );
}

/// Возвращает путь, если файл укладывается в лимит размера. Иначе —
/// показывает снэкбар (если есть [context]) и возвращает null. Использует
/// тот же лимит, что StorageService применяет на upload — лучше отсечь
/// здесь, чем дать пользователю наполнить форму и сорваться на публикации.
String? _filterBySizeOrWarn(String path, BuildContext? context) {
  final int bytes = File(path).lengthSync();
  if (bytes <= StorageService.maxFileBytes) return path;
  if (context != null && context.mounted) {
    _showTooLargeSnack(context, bytes / (1024 * 1024));
  }
  return null;
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
      maxWidth: StorageService.maxImageDimension.toDouble(),
      maxHeight: StorageService.maxImageDimension.toDouble(),
      imageQuality: 85,
    );
    if (file == null) return null;
    // Внутри `_filterBySizeOrWarn` сделаем `context.mounted` перед showSnackBar.
    // ignore: use_build_context_synchronously
    return _filterBySizeOrWarn(file.path, context);
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
/// Слишком большие файлы (>20 МБ) отсекаются с предупреждением — и
/// пользователь сразу видит, что «5 фото из 7 добавлены, 2 слишком
/// большие», а не молча теряет их при публикации.
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
      maxWidth: StorageService.maxImageDimension.toDouble(),
      maxHeight: StorageService.maxImageDimension.toDouble(),
      imageQuality: 85,
      limit: limit,
    );
    final List<String> ok = <String>[];
    int rejected = 0;
    for (final XFile f in files) {
      final int bytes = File(f.path).lengthSync();
      if (bytes > StorageService.maxFileBytes) {
        rejected++;
      } else {
        ok.add(f.path);
      }
    }
    if (rejected > 0 && context != null && context.mounted) {
      final int maxMb = StorageService.maxFileBytes ~/ (1024 * 1024);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rejected == 1
                ? '1 фото слишком большое, максимум $maxMb МБ.'
                : '$rejected фото слишком большие, максимум $maxMb МБ.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
    return ok;
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

/// True, если путь — это HTTP(S) URL (например, фото в storage Supabase).
bool isNetworkPath(String path) =>
    path.startsWith('http://') || path.startsWith('https://');

/// True, если строка похожа на путь в приватном бакете `order-photos`
/// (`<user_id>/<order_id>/<file>.webp`). Локальные пути — абсолютные
/// (`/data/user/...`, `C:\...`); пути storage относительные и не имеют
/// схемы. Эту эвристику используем, чтобы при отображении превратить
/// относительный путь в signed URL вместо попытки открыть его как файл.
bool isStoragePath(String path) {
  if (isAssetPath(path) || isNetworkPath(path)) return false;
  if (path.startsWith('/') || path.startsWith(r'\')) return false;
  if (path.length >= 3 && path[1] == ':') return false; // C:\... на Windows
  return path.contains('/');
}

/// Отдаёт нужный [ImageProvider] для картинки в зависимости от
/// источника:
/// - `assets/...`           → [AssetImage]
/// - `http(s)://...`        → [NetworkImage] (фото в storage Supabase)
/// - всё остальное          → [FileImage] (только что выбранный с устройства)
///
/// Используется в виджетах, которые должны показывать и ассеты,
/// и реальные фото с устройства, и URL'ы из БД.
ImageProvider photoProvider(String path) {
  if (isAssetPath(path)) return AssetImage(path);
  if (isNetworkPath(path)) return NetworkImage(path);
  return FileImage(File(path));
}

/// Универсальный [Image] для путей трёх типов (asset/http/file). Без
/// этого виджеты с фото услуг (где путь может быть и локальным файлом
/// при свежем выборе, и https URL после загрузки в storage) ловили
/// FileSystemException на `Image.file(File('https://...'))`.
///
/// Для путей приватного бакета (`<uid>/<order>/<file>.webp`) используйте
/// [SignedStorageImage] — `imageFromPath` подсунет такому пути
/// `Image.file`, что упадёт.
Widget imageFromPath(
  String path, {
  BoxFit? fit,
  double? width,
  double? height,
  int? cacheWidth,
  int? cacheHeight,
}) {
  if (isAssetPath(path)) {
    return Image.asset(path,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight);
  }
  if (isNetworkPath(path)) {
    return Image.network(path,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight);
  }
  return Image.file(File(path),
      fit: fit,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight);
}

/// Кэш signed-URL для путей в приватных бакетах. Подпись живёт 1 час,
/// храним 50 минут (с запасом), чтобы не пересоздавать URL при каждом
/// rebuild и не словить «истёкший токен» прямо во время отображения.
class _SignedUrlCache {
  /// Лимит записей. Без него кэш растёт неограниченно при пролистывании
  /// больших лент с фото — десятки тысяч записей в RAM за сессию.
  /// При достижении лимита вычищаем половину «старых» записей
  /// (по возрасту подписи).
  static const int _maxEntries = 500;

  static final Map<String, _Entry> _entries = <String, _Entry>{};

  static Future<String?> resolve(String bucket, String path) async {
    final String key = '$bucket/$path';
    final _Entry? cached = _entries[key];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.url;
    }
    try {
      final String url = await Supabase.instance.client.storage
          .from(bucket)
          .createSignedUrl(path, 3600);
      _entries[key] =
          _Entry(url, DateTime.now().add(const Duration(minutes: 50)));
      if (_entries.length > _maxEntries) {
        _evictHalf();
      }
      return url;
    } catch (_) {
      return null;
    }
  }

  static void _evictHalf() {
    final List<MapEntry<String, _Entry>> sorted = _entries.entries.toList()
      ..sort((a, b) => a.value.expiresAt.compareTo(b.value.expiresAt));
    final int toRemove = sorted.length ~/ 2;
    for (int i = 0; i < toRemove; i++) {
      _entries.remove(sorted[i].key);
    }
  }

  /// Полная очистка. Вызывается при выходе из аккаунта — без этого
  /// подписанный URL прежнего пользователя (валидный 50 минут) мог
  /// случайно достаться следующему юзеру при коллизии storage-path
  /// (типичный пример — общий аватар-плейсхолдер).
  static void clearAll() {
    _entries.clear();
  }
}

/// Публичный вход в кэш signed-URL. Используется при logout, чтобы
/// сбросить локальные ссылки на чужие приватные файлы.
void clearSignedUrlCache() => _SignedUrlCache.clearAll();

class _Entry {
  _Entry(this.url, this.expiresAt);
  final String url;
  final DateTime expiresAt;
}

/// Отображает изображение из приватного бакета Supabase Storage по
/// относительному пути. Сам запрашивает signed URL, кэширует его и
/// рендерит через [Image.network]. Пока URL не получен — серый
/// плейсхолдер, при ошибке — иконка.
class SignedStorageImage extends StatelessWidget {
  const SignedStorageImage({
    super.key,
    required this.bucket,
    required this.path,
    this.fit,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
  });

  final String bucket;
  final String path;
  final BoxFit? fit;
  final double? width;
  final double? height;
  // Размер декодирования в физических пикселях. Для миниатюр в сетках
  // задаём небольшой — иначе фото из бакета (до 2560px) разворачивается
  // в RAM целиком ради плашки 70–90px. Для полноэкранной галереи не
  // передаём — там нужен полный размер под зум.
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _SignedUrlCache.resolve(bucket, path),
      builder: (BuildContext ctx, AsyncSnapshot<String?> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            width: width,
            height: height,
            color: const Color(0xFFEDEDED),
          );
        }
        final String? url = snap.data;
        if (url == null) {
          return Container(
            width: width,
            height: height,
            color: const Color(0xFFEDEDED),
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined,
                color: Color(0xFFB0B0B0)),
          );
        }
        return Image.network(url,
            fit: fit,
            width: width,
            height: height,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight);
      },
    );
  }
}

/// Универсальная картинка для путей всех типов: asset / http / local file /
/// storage path в приватном бакете. Если путь похож на storage-путь, идёт
/// через [SignedStorageImage] и `bucket` обязателен — иначе
/// в худшем случае молча упадёт `Image.file` на относительный путь.
Widget photoSmartImage(
  String path, {
  String? bucket,
  BoxFit? fit,
  double? width,
  double? height,
  int? cacheWidth,
  int? cacheHeight,
}) {
  if (isAssetPath(path)) {
    return Image.asset(path,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight);
  }
  if (isNetworkPath(path)) {
    return Image.network(path,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight);
  }
  if (bucket != null && isStoragePath(path)) {
    return SignedStorageImage(
      bucket: bucket,
      path: path,
      fit: fit,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
  }
  return Image.file(File(path),
      fit: fit,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight);
}

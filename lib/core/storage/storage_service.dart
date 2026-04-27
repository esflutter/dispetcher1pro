import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Бросается, когда пользователь пытается загрузить файл больше
/// [StorageService.maxFileBytes]. UI ловит и показывает снэкбар
/// «Файл слишком большой, максимум 20 МБ».
class FileTooLargeException implements Exception {
  const FileTooLargeException({
    required this.actualBytes,
    required this.maxBytes,
  });

  final int actualBytes;
  final int maxBytes;

  /// Размер в МБ с одним знаком после запятой — для подстановки в текст.
  double get actualMb => actualBytes / (1024 * 1024);
  double get maxMb => maxBytes / (1024 * 1024);

  @override
  String toString() =>
      'FileTooLargeException(${actualMb.toStringAsFixed(1)} MB > '
      '${maxMb.toStringAsFixed(0)} MB)';
}

/// Загрузка файлов в Supabase Storage. Бакеты заведены в миграции 005:
/// - `avatars` (public) — аватары профилей
/// - `service-photos` (public) — фото услуг исполнителя
/// - `order-photos` (private, под RLS) — фото заказа (видят только стороны)
///
/// Public-бакеты: путь `<user_id>/<uuid>.webp` — RLS проверяет
/// `(storage.foldername(name))[1] = auth.uid()`.
/// `order-photos`: путь `<user_id>/<order_id>/<uuid>.webp` — RLS на SELECT
/// для исполнителя проверяет `foldername[2] = order_id`, чтобы исполнитель
/// с accepted-мэтчем по конкретному заказу видел только его фото.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  /// Максимальный размер исходного файла перед сжатием — 20 МБ. Защита
  /// от storage-флуда: без лимита злоумышленник с пропатченным клиентом
  /// (или подменённым image_picker) мог бы залить 200-мегабайтные файлы
  /// в публичные бакеты и за час забить storage-квоту Beget VPS.
  ///
  /// Современные смартфоны с 50-мегапиксельной камерой выдают JPEG
  /// размером 8–15 МБ — 20 МБ покрывает с запасом.
  /// Public, чтобы UI-слой (photo_source.dart) использовал ту же цифру
  /// при ранней проверке после image_picker.
  static const int maxFileBytes = 20 * 1024 * 1024;

  /// Длинная сторона результата `_compress` и параметра maxWidth/maxHeight
  /// у image_picker. Минимум 2500 (явно озвученное требование), берём
  /// 2560 как стандарт QHD — это покрывает дисплеи большинства мобильных
  /// и десктоп-мониторов. На детализацию фото объекта (где стоит/что
  /// копаем) этого достаточно: по 2560 пикселей можно прочитать номера
  /// машин.
  static const int maxImageDimension = 2560;

  SupabaseClient get _client => Supabase.instance.client;

  /// Загружает файл в бакет `avatars` и возвращает публичный URL.
  /// Старый аватар удаляется (old path сохранён в `profiles.avatar_url`).
  Future<String> uploadAvatar(File file) =>
      _uploadToPublicBucket('avatars', file);

  /// Загружает фото услуги (до 8 штук на услугу). Возвращает публичный URL.
  Future<String> uploadServicePhoto(File file) =>
      _uploadToPublicBucket('service-photos', file);

  /// Загружает фото заказа. Бакет приватный — URL вернёт signed URL на
  /// 1 час; клиент пересохраняет в `orders.photos` сам путь.
  /// Требует уже созданный `orderId`: RLS на чтение для исполнителя
  /// проверяет `foldername[2] = order_id`.
  Future<String> uploadOrderPhoto(File file, {required String orderId}) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    _ensureUnderMaxSize(file);
    final File compressed = await _compress(file);
    final String fileName = '${DateTime.now().microsecondsSinceEpoch}.webp';
    final String path = '${user.id}/$orderId/$fileName';
    await _client.storage.from('order-photos').upload(path, compressed);
    return path;
  }

  /// Бросает [FileTooLargeException] если файл больше [maxFileBytes].
  /// Проверяем до сжатия — даже сжатие 100-мегабайтного файла занимает
  /// ощутимое время и память, его нет смысла даже пытаться.
  void _ensureUnderMaxSize(File file) {
    final int bytes = file.lengthSync();
    if (bytes > maxFileBytes) {
      throw FileTooLargeException(
        actualBytes: bytes,
        maxBytes: maxFileBytes,
      );
    }
  }

  /// Ресайзит и конвертирует фото в webp перед upload. Длинная сторона
  /// ограничена [maxImageDimension] — параметры minWidth/minHeight
  /// в `flutter_image_compress` действуют как **верхняя граница** обеих
  /// сторон с сохранением пропорций (название параметра историческое
  /// и сбивает с толку). 50-мегапиксельный кадр 8160×6120 после сжатия
  /// станет 2560×1920 ≈ 250 КБ webp.
  ///
  /// При неудаче (некоторые форматы платформа не сжимает) возвращает
  /// исходный файл — лучше залить как есть, чем сорвать создание заказа.
  Future<File> _compress(File source) async {
    try {
      final String target =
          '${source.path}.${DateTime.now().microsecondsSinceEpoch}.webp';
      final XFile? out = await FlutterImageCompress.compressAndGetFile(
        source.absolute.path,
        target,
        format: CompressFormat.webp,
        quality: 85,
        minWidth: maxImageDimension,
        minHeight: maxImageDimension,
      );
      if (out == null) return source;
      return File(out.path);
    } catch (_) {
      return source;
    }
  }

  /// Возвращает signed URL для приватного файла (1 час).
  Future<String> getSignedUrl(String bucket, String path,
      {int expiresInSec = 3600}) async {
    return _client.storage.from(bucket).createSignedUrl(path, expiresInSec);
  }

  Future<String> _uploadToPublicBucket(String bucket, File file) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    _ensureUnderMaxSize(file);
    final File compressed = await _compress(file);
    final String fileName = '${DateTime.now().microsecondsSinceEpoch}.webp';
    final String path = '${user.id}/$fileName';
    await _client.storage.from(bucket).upload(path, compressed);
    return _client.storage.from(bucket).getPublicUrl(path);
  }
}

import 'dart:io';
import 'dart:math';

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
    final String fileName = '${_uniqueId()}.webp';
    final String path = '${user.id}/$orderId/$fileName';
    // Явный contentType — без него self-hosted Supabase Storage иногда
    // выставляет application/octet-stream, и bucket с allowed_mime_types
    // (image/jpeg|png|webp) reject'ит загрузку.
    await _client.storage.from('order-photos').upload(
          path,
          compressed,
          fileOptions: const FileOptions(contentType: 'image/webp'),
        );
    return path;
  }

  /// Загружает фото документа для верификации в приватный бакет
  /// `assistant-attachments`. Возвращает ПУТЬ (не URL): его записываем в
  /// verification_documents, а админ смотрит файл через Supabase Studio
  /// (приватный бакет, только владелец + service_role).
  /// Путь: `<user_id>/verification/<uuid>.webp` — RLS на INSERT проверяет
  /// первый сегмент = auth.uid().
  Future<String> uploadVerificationDocument(File file) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    _ensureUnderMaxSize(file);
    final File compressed = await _compress(file);
    final String fileName = '${_uniqueId()}.webp';
    final String path = '${user.id}/verification/$fileName';
    await _client.storage.from('assistant-attachments').upload(
          path,
          compressed,
          fileOptions: const FileOptions(contentType: 'image/webp'),
        );
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
  /// HEIC/HEIF из iOS-галереи обрабатывается особо: webp-компрессор у
  /// нативных плагинов нередко падает на этих контейнерах. Сначала
  /// пробуем JPEG (он гарантированно поддерживается), и только если
  /// HEIC оригинал — никогда не возвращаем его «как есть»: сервер
  /// отвергает HEIC с ошибкой mime, и юзер видит мутный «не удалось
  /// загрузить» без понимания почему.
  ///
  /// При неудаче на не-HEIC форматах возвращаем исходный файл — лучше
  /// залить как есть, чем сорвать создание заказа.
  Future<File> _compress(File source) async {
    final String ext = source.path.toLowerCase();
    final bool isHeic = ext.endsWith('.heic') || ext.endsWith('.heif');
    try {
      final CompressFormat fmt =
          isHeic ? CompressFormat.jpeg : CompressFormat.webp;
      final String suffix = isHeic ? 'jpg' : 'webp';
      final String target =
          '${source.path}.${DateTime.now().microsecondsSinceEpoch}.$suffix';
      final XFile? out = await FlutterImageCompress.compressAndGetFile(
        source.absolute.path,
        target,
        format: fmt,
        quality: 85,
        minWidth: maxImageDimension,
        minHeight: maxImageDimension,
      );
      if (out != null) return File(out.path);
    } catch (_) {/* ниже — fallback */}
    // Если первая попытка не удалась И исходник HEIC — пробуем ещё
    // раз с JPEG форматом явно (на случай если первый Try был webp по
    // ошибке) и если снова никак — бросаем явное исключение вместо
    // возврата HEIC оригинала: пусть UI покажет «не удалось обработать
    // фото», а не сервер отдаст «invalid mime type» позже.
    if (isHeic) {
      try {
        final String target =
            '${source.path}.${DateTime.now().microsecondsSinceEpoch}.jpg';
        final XFile? out = await FlutterImageCompress.compressAndGetFile(
          source.absolute.path,
          target,
          format: CompressFormat.jpeg,
          quality: 85,
          minWidth: maxImageDimension,
          minHeight: maxImageDimension,
        );
        if (out != null) return File(out.path);
      } catch (_) {/* ниже */}
      throw const FormatException(
        'Не удалось обработать HEIC-фото. Попробуйте сохранить в галерее '
        'как JPEG и повторить.',
      );
    }
    return source;
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
    final String fileName = '${_uniqueId()}.webp';
    final String path = '${user.id}/$fileName';
    // Явный contentType — см. uploadOrderPhoto.
    await _client.storage.from(bucket).upload(
          path,
          compressed,
          fileOptions: const FileOptions(contentType: 'image/webp'),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  /// Удаляет файл аватара из публичного бакета `avatars` по его public URL.
  /// Тихо игнорирует ошибки (файл мог быть уже удалён/перезаписан).
  Future<void> deleteAvatarByUrl(String publicUrl) async {
    final String? path = _publicBucketPath(publicUrl, 'avatars');
    if (path == null) return;
    try {
      await _client.storage.from('avatars').remove(<String>[path]);
    } catch (_) {/* уже удалён — не критично */}
  }

  /// Путь внутри бакета из public URL вида
  /// `.../storage/v1/object/public/<bucket>/<path>`.
  String? _publicBucketPath(String url, String bucket) {
    final String marker = '/object/public/$bucket/';
    final int i = url.indexOf(marker);
    if (i < 0) return null;
    final String path = url.substring(i + marker.length);
    return path.isEmpty ? null : Uri.decodeFull(path);
  }

  /// Уникальный ID файла — micros + 6 hex-символов случайных. Раньше брали
  /// просто `microsecondsSinceEpoch`, но при двух последовательных
  /// загрузках в одну микросекунду (тапы по галерее на быстром девайсе)
  /// файлы получали один path и второй upload «затирал» первый в storage.
  static final Random _rng = Random.secure();
  static String _uniqueId() {
    final int micros = DateTime.now().microsecondsSinceEpoch;
    final int rnd = _rng.nextInt(0xFFFFFF);
    return '$micros-${rnd.toRadixString(16).padLeft(6, '0')}';
  }
}

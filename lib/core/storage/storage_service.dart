import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    final File compressed = await _compress(file);
    final String fileName = '${DateTime.now().microsecondsSinceEpoch}.webp';
    final String path = '${user.id}/$orderId/$fileName';
    await _client.storage.from('order-photos').upload(path, compressed);
    return path;
  }

  /// Ресайзит и конвертирует фото в webp перед upload. Это сильно режет
  /// трафик: 5-мегапиксельное JPG ≈ 1.5 МБ → webp 1280px ≈ 200 КБ.
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
        minWidth: 1280,
        minHeight: 1280,
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
    final File compressed = await _compress(file);
    final String fileName = '${DateTime.now().microsecondsSinceEpoch}.webp';
    final String path = '${user.id}/$fileName';
    await _client.storage.from(bucket).upload(path, compressed);
    return _client.storage.from(bucket).getPublicUrl(path);
  }
}

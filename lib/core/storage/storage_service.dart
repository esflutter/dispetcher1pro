import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Загрузка файлов в Supabase Storage. Бакеты заведены в миграции 005:
/// - `avatars` (public) — аватары профилей
/// - `service-photos` (public) — фото услуг исполнителя
/// - `order-photos` (private, под RLS) — фото заказа (видят только стороны)
///
/// Все пути формируются по шаблону `<bucket>/<user_id>/<uuid>.<ext>`,
/// что соответствует RLS-политике `(storage.foldername(name))[1] = auth.uid()`.
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
  /// 24 часа; клиент пересохраняет в `orders.photos` этот URL (или path
  /// для повторной подписи на чтении).
  Future<String> uploadOrderPhoto(File file) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    final String ext = _extOf(file.path);
    final String fileName = '${DateTime.now().microsecondsSinceEpoch}$ext';
    final String path = '${user.id}/$fileName';
    await _client.storage.from('order-photos').upload(path, file);
    // Возвращаем сам путь — клиент при отображении запрашивает signed URL.
    return path;
  }

  /// Возвращает signed URL для приватного файла (1 час).
  Future<String> getSignedUrl(String bucket, String path,
      {int expiresInSec = 3600}) async {
    return _client.storage.from(bucket).createSignedUrl(path, expiresInSec);
  }

  String _extOf(String filePath) {
    final int dot = filePath.lastIndexOf('.');
    if (dot < 0) return '';
    return filePath.substring(dot).toLowerCase();
  }

  Future<String> _uploadToPublicBucket(String bucket, File file) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    final String ext = _extOf(file.path);
    final String fileName = '${DateTime.now().microsecondsSinceEpoch}$ext';
    final String path = '${user.id}/$fileName';
    await _client.storage.from(bucket).upload(path, file);
    return _client.storage.from(bucket).getPublicUrl(path);
  }
}

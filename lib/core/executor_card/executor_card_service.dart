import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/profile/profile_service.dart';

/// Чтение/запись моей публичной карточки исполнителя
/// (`public.executor_cards` + расширения `profiles`: about, legal_status,
/// experience_years). Одна строка на пользователя.
class ExecutorCardService {
  ExecutorCardService._();
  static final ExecutorCardService instance = ExecutorCardService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<MyExecutorCard?> loadMine() async {
    final User? user = _client.auth.currentUser;
    if (user == null) return null;
    final Map<String, dynamic>? ec = await _client
        .from('executor_cards')
        .select(
          'location_address, location_lat, location_lng, radius_km, '
          'is_published, saved_at, updated_at',
        )
        .eq('user_id', user.id)
        .maybeSingle();
    final Map<String, dynamic>? p = await _client
        .from('profiles')
        .select('about, legal_status, experience_years')
        .eq('id', user.id)
        .maybeSingle();
    if (ec == null && p == null) return null;
    return MyExecutorCard(
      locationAddress: ec?['location_address'] as String?,
      locationLat: (ec?['location_lat'] as num?)?.toDouble(),
      locationLng: (ec?['location_lng'] as num?)?.toDouble(),
      radiusKm: ec?['radius_km'] as int?,
      isPublished: (ec?['is_published'] as bool?) ?? false,
      savedAt: ec?['saved_at'] == null
          ? null
          : DateTime.parse(ec!['saved_at'] as String).toLocal(),
      about: p?['about'] as String?,
      legalStatus: p?['legal_status'] as String?,
      experienceYears: p?['experience_years'] as int?,
    );
  }

  /// UPSERT в executor_cards + UPDATE profiles. Публиковать карточку
  /// (`is_published=true`) можно только когда заполнен радиус — БД CHECK.
  ///
  /// Поля карточки опциональные; если их не передали (null), они НЕ
  /// записываются в БД — иначе UPSERT молча затирал бы ранее сохранённые
  /// `location_*`/`radius_km`/`is_published` при сохранении только
  /// «о себе» или статуса. Поле `isPublished` тоже nullable, чтобы
  /// «снять с публикации» оставалось явным действием — вызывающий код
  /// передаёт `false`/`true` только когда меняет публичность карточки.
  ///
  /// Чтобы UPSERT мог сработать впервые (когда строки в БД ещё нет),
  /// мы предварительно подгружаем существующую запись и подменяем
  /// отсутствующие поля её значениями. Если строки нет — используем
  /// безопасные дефолты.
  Future<void> upsert({
    String? locationAddress,
    double? locationLat,
    double? locationLng,
    int? radiusKm,
    bool? isPublished,
    String? legalStatus,
    int? experienceYears,
  }) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    final Map<String, dynamic>? existing = await _client
        .from('executor_cards')
        .select(
          'location_address, location_lat, location_lng, radius_km, is_published',
        )
        .eq('user_id', user.id)
        .maybeSingle();
    await _client.from('executor_cards').upsert(<String, dynamic>{
      'user_id': user.id,
      'location_address':
          locationAddress ?? existing?['location_address'],
      'location_lat':
          locationLat ?? (existing?['location_lat'] as num?)?.toDouble(),
      'location_lng':
          locationLng ?? (existing?['location_lng'] as num?)?.toDouble(),
      'radius_km': radiusKm ?? existing?['radius_km'],
      'is_published':
          isPublished ?? (existing?['is_published'] as bool?) ?? false,
      // Любой upsert карточки = факт сохранения. Этот флаг гасит
      // empty-state в ExecutorCardScreen независимо от радиуса.
      'saved_at': DateTime.now().toUtc().toIso8601String(),
    });
    // Статус и опыт всегда приходят из формы (null = пользователь очистил
    // поле), поэтому пишем их безусловно. «О себе» из формы убрано — поле
    // больше НЕ трогаем здесь, чтобы случайно не затереть сохранённый текст.
    await _client.from('profiles').update(<String, dynamic>{
      'legal_status': legalStatus,
      'experience_years': experienceYears,
    }).eq('id', user.id);
    // Любой upsert карточки/правка about/опыта в profile-плоскости —
    // повод обновить шапку профиля (имя/avatar/about), которую слушают
    // ProfileScreen и ExecutorCardScreen через ProfileService.changeBeacon.
    ProfileService.changeBeacon.value++;
  }
}

class MyExecutorCard {
  const MyExecutorCard({
    required this.locationAddress,
    required this.locationLat,
    required this.locationLng,
    required this.radiusKm,
    required this.isPublished,
    required this.savedAt,
    required this.about,
    required this.legalStatus,
    required this.experienceYears,
  });

  final String? locationAddress;
  final double? locationLat;
  final double? locationLng;
  final int? radiusKm; // 10 / 20 / 50
  final bool isPublished;
  /// Момент первого сохранения карточки. UI снимает empty-state по
  /// этому полю — а не по `isPublished`, иначе после сохранения без
  /// радиуса (radius_km IS NULL → is_published=false по CHECK)
  /// карточка считалась бы несозданной и юзер попадал бы в «Создать».
  final DateTime? savedAt;
  final String? about;
  final String? legalStatus;
  final int? experienceYears;
}

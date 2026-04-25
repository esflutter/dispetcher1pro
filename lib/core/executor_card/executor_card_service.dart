import 'package:supabase_flutter/supabase_flutter.dart';

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
          'is_published, updated_at',
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
      about: p?['about'] as String?,
      legalStatus: p?['legal_status'] as String?,
      experienceYears: p?['experience_years'] as int?,
    );
  }

  /// UPSERT в executor_cards + UPDATE profiles. Публиковать карточку
  /// (`is_published=true`) можно только когда заполнен радиус — БД CHECK.
  Future<void> upsert({
    String? locationAddress,
    double? locationLat,
    double? locationLng,
    int? radiusKm,
    bool isPublished = false,
    String? about,
    String? legalStatus,
    int? experienceYears,
  }) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    await _client.from('executor_cards').upsert(<String, dynamic>{
      'user_id': user.id,
      'location_address': locationAddress,
      'location_lat': locationLat,
      'location_lng': locationLng,
      'radius_km': radiusKm,
      'is_published': isPublished,
    });
    final Map<String, dynamic> profilePatch = <String, dynamic>{
      'about': ?about,
      'legal_status': ?legalStatus,
      'experience_years': ?experienceYears,
    };
    if (profilePatch.isNotEmpty) {
      await _client.from('profiles').update(profilePatch).eq('id', user.id);
    }
  }
}

class MyExecutorCard {
  const MyExecutorCard({
    required this.locationAddress,
    required this.locationLat,
    required this.locationLng,
    required this.radiusKm,
    required this.isPublished,
    required this.about,
    required this.legalStatus,
    required this.experienceYears,
  });

  final String? locationAddress;
  final double? locationLat;
  final double? locationLng;
  final int? radiusKm; // 10 / 20 / 50
  final bool isPublished;
  final String? about;
  final String? legalStatus;
  final int? experienceYears;
}

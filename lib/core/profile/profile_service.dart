import 'package:supabase_flutter/supabase_flutter.dart';

/// Чтение/запись моего профиля (`public.profiles` + `profiles_private`).
/// Публичная часть (имя/аватар/about/рейтинги) читается одним запросом,
/// приватная (телефон/email/дата рождения) — отдельным, чтобы при
/// ограниченном доступе можно было гибко обрабатывать ошибку.
class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<MyProfile?> loadMine() async {
    final User? user = _client.auth.currentUser;
    if (user == null) return null;
    final Map<String, dynamic>? r = await _client
        .from('profiles')
        .select(
          'id, name, avatar_url, about, legal_status, experience_years, '
          'rating_as_executor, review_count_as_executor, '
          'rating_as_customer, review_count_as_customer, '
          'is_executor, is_customer, blocked_until, '
          'verification_status, agreement_accepted_at, terms_version',
        )
        .eq('id', user.id)
        .maybeSingle();
    if (r == null) return null;
    return MyProfile.fromRow(r);
  }

  Future<MyPrivate?> loadMyPrivate() async {
    final User? user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final Map<String, dynamic>? r = await _client
          .from('profiles_private')
          .select('phone, email, date_of_birth, '
              'subscription_paid_until, subscription_auto_renew')
          .eq('id', user.id)
          .maybeSingle();
      if (r == null) return null;
      return MyPrivate.fromRow(r);
    } on PostgrestException {
      return null;
    }
  }

  /// UPDATE `profiles` — имя/аватар/about/юр. статус/опыт.
  Future<void> update({
    String? name,
    String? avatarUrl,
    String? about,
    String? legalStatus,
    int? experienceYears,
  }) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    final Map<String, dynamic> payload = <String, dynamic>{
      'name': ?name,
      'avatar_url': ?avatarUrl,
      'about': ?about,
      'legal_status': ?legalStatus,
      'experience_years': ?experienceYears,
    };
    if (payload.isEmpty) return;
    await _client.from('profiles').update(payload).eq('id', user.id);
  }

  /// UPDATE `profiles_private` — email.
  Future<void> updatePrivateEmail(String email) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    await _client
        .from('profiles_private')
        .update(<String, dynamic>{'email': email.isEmpty ? null : email})
        .eq('id', user.id);
  }
}

class MyProfile {
  const MyProfile({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.about,
    required this.legalStatus,
    required this.experienceYears,
    required this.ratingAsExecutor,
    required this.reviewCountAsExecutor,
    required this.ratingAsCustomer,
    required this.reviewCountAsCustomer,
    required this.isExecutor,
    required this.isCustomer,
    required this.blockedUntil,
    required this.verificationStatus,
    required this.agreementAcceptedAt,
    required this.termsVersion,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String? about;
  final String? legalStatus;
  final int? experienceYears;
  final double ratingAsExecutor;
  final int reviewCountAsExecutor;
  final double ratingAsCustomer;
  final int reviewCountAsCustomer;
  final bool isExecutor;
  final bool isCustomer;
  final DateTime? blockedUntil;
  /// 'none' / 'pending' / 'approved' / 'rejected'
  final String verificationStatus;
  final DateTime? agreementAcceptedAt;
  final String? termsVersion;

  factory MyProfile.fromRow(Map<String, dynamic> r) => MyProfile(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? 'Пользователь',
        avatarUrl: r['avatar_url'] as String?,
        about: r['about'] as String?,
        legalStatus: r['legal_status'] as String?,
        experienceYears: r['experience_years'] as int?,
        ratingAsExecutor: _d(r['rating_as_executor']),
        reviewCountAsExecutor:
            (r['review_count_as_executor'] as int?) ?? 0,
        ratingAsCustomer: _d(r['rating_as_customer']),
        reviewCountAsCustomer:
            (r['review_count_as_customer'] as int?) ?? 0,
        isExecutor: (r['is_executor'] as bool?) ?? false,
        isCustomer: (r['is_customer'] as bool?) ?? true,
        blockedUntil: r['blocked_until'] == null
            ? null
            : DateTime.parse(r['blocked_until'] as String),
        verificationStatus:
            (r['verification_status'] as String?) ?? 'none',
        agreementAcceptedAt: r['agreement_accepted_at'] == null
            ? null
            : DateTime.parse(r['agreement_accepted_at'] as String),
        termsVersion: r['terms_version'] as String?,
      );
}

class MyPrivate {
  const MyPrivate({
    required this.phone,
    required this.email,
    required this.dateOfBirth,
    required this.subscriptionPaidUntil,
    required this.subscriptionAutoRenew,
  });
  final String? phone;
  final String? email;
  final DateTime? dateOfBirth;
  final DateTime? subscriptionPaidUntil;
  final bool subscriptionAutoRenew;

  factory MyPrivate.fromRow(Map<String, dynamic> r) => MyPrivate(
        phone: r['phone'] as String?,
        email: r['email'] as String?,
        dateOfBirth: r['date_of_birth'] == null
            ? null
            : DateTime.parse(r['date_of_birth'] as String),
        subscriptionPaidUntil: r['subscription_paid_until'] == null
            ? null
            : DateTime.parse(r['subscription_paid_until'] as String),
        subscriptionAutoRenew:
            (r['subscription_auto_renew'] as bool?) ?? false,
      );
}

double _d(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Чтение/запись моего профиля (`public.profiles` + `profiles_private`).
/// Публичная часть (имя/аватар/about/рейтинги) читается одним запросом,
/// приватная (телефон/email/дата рождения) — отдельным, чтобы при
/// ограниченном доступе можно было гибко обрабатывать ошибку.
class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  /// Счётчик «профиль изменился». Инкрементится после любого успешного
  /// update/updatePrivateEmail/updateSubscription. Экраны слушают и
  /// сами дёргают loadMine/loadMyPrivate, чтобы UI не залипал на старых
  /// данных после правок в дочерних экранах.
  static final ValueNotifier<int> changeBeacon = ValueNotifier<int>(0);

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
              'subscription_paid_until, subscription_trial_until, '
              'subscription_auto_renew, subscription_trial_used, '
              'subscription_payment_method_id, verification_reject_reason')
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
    changeBeacon.value++;
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
    changeBeacon.value++;
  }

  /// UPDATE `profiles_private.subscription_auto_renew` — тумблер
  /// «Авто-продление» в настройках подписки. Клиент может сам менять
  /// этот флаг (это его собственный выбор отписаться). А вот дату
  /// `subscription_paid_until` клиент НЕ должен ставить — её пишет
  /// серверная Edge Function `payment-return` после успешной оплаты в
  /// YooKassa. Серверный триггер `profiles_private_protect_sensitive`
  /// блокирует попытку клиента изменить любые subscription-поля кроме
  /// `auto_renew`.
  Future<void> updateSubscriptionAutoRenew(bool autoRenew) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    await _client
        .from('profiles_private')
        .update(<String, dynamic>{'subscription_auto_renew': autoRenew})
        .eq('id', user.id);
    changeBeacon.value++;
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
            : DateTime.parse(r['blocked_until'] as String).toLocal(),
        verificationStatus:
            (r['verification_status'] as String?) ?? 'none',
        agreementAcceptedAt: r['agreement_accepted_at'] == null
            ? null
            : DateTime.parse(r['agreement_accepted_at'] as String).toLocal(),
        termsVersion: r['terms_version'] as String?,
      );
}

class MyPrivate {
  const MyPrivate({
    required this.phone,
    required this.email,
    required this.dateOfBirth,
    required this.subscriptionPaidUntil,
    required this.subscriptionTrialUntil,
    required this.subscriptionAutoRenew,
    required this.subscriptionTrialUsed,
    required this.subscriptionPaymentMethodId,
    required this.verificationRejectReason,
  });
  final String? phone;
  final String? email;
  final DateTime? dateOfBirth;
  final DateTime? subscriptionPaidUntil;

  /// Конец триала. Если в будущем — юзер сейчас на бесплатном пробном
  /// периоде; если в прошлом или null — обычная платная подписка
  /// (или без подписки). Поле отделено от `paid_until`, чтобы UI мог
  /// различать «N дней триала осталось» и «следующее списание …».
  final DateTime? subscriptionTrialUntil;
  final bool subscriptionAutoRenew;

  /// Триал был использован — повторно его не дать. Управляется
  /// триггером `apply_payment_success` при первой активации
  /// подписки/привязке карты с `activate_trial=1`.
  final bool subscriptionTrialUsed;

  /// id привязанной карты для авто-продления подписки. Cron
  /// `subscription_charge_due` использует его для off-session-charge.
  /// `null` — карта не привязана, авто-продление невозможно.
  final String? subscriptionPaymentMethodId;

  /// Текстовая причина отказа модерацией. `null` — нет отказа или отказ
  /// без причины. Показывается на экране карточки исполнителя при
  /// `verification_status = rejected`.
  final String? verificationRejectReason;

  /// Подписка активна сейчас (включая триал) — paid_until ещё в будущем.
  bool get subscriptionActive {
    final DateTime? until = subscriptionPaidUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  /// Юзер сейчас на бесплатном триале — `trial_until` ещё в будущем.
  /// Это явный признак, не зависящий от `trial_used` (который
  /// ставится в true сразу при активации и больше не меняется).
  bool get subscriptionInTrial {
    final DateTime? until = subscriptionTrialUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  factory MyPrivate.fromRow(Map<String, dynamic> r) => MyPrivate(
        phone: r['phone'] as String?,
        email: r['email'] as String?,
        dateOfBirth: r['date_of_birth'] == null
            ? null
            : DateTime.parse(r['date_of_birth'] as String).toLocal(),
        subscriptionPaidUntil: r['subscription_paid_until'] == null
            ? null
            : DateTime.parse(r['subscription_paid_until'] as String).toLocal(),
        subscriptionTrialUntil: r['subscription_trial_until'] == null
            ? null
            : DateTime.parse(r['subscription_trial_until'] as String).toLocal(),
        subscriptionAutoRenew:
            (r['subscription_auto_renew'] as bool?) ?? false,
        subscriptionTrialUsed:
            (r['subscription_trial_used'] as bool?) ?? false,
        subscriptionPaymentMethodId:
            r['subscription_payment_method_id'] as String?,
        verificationRejectReason: r['verification_reject_reason'] as String?,
      );
}

double _d(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

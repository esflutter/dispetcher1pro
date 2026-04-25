import 'package:supabase_flutter/supabase_flutter.dart';

/// Тонкая обёртка над Supabase Auth + чтением/записью в `public.profiles`.
/// Знает только про телефон в E.164 — все преобразования из UI-формата
/// делаются вызывающим кодом (см. `phone_format.dart`).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;
  GoTrueClient get _auth => _client.auth;

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => _auth.currentSession != null;

  /// Отправляет OTP на номер в E.164 (+7XXXXXXXXXX).
  /// В dev-режиме с настроенным `GOTRUE_SMS_TEST_OTP` реального SMS не
  /// будет — код задан в переменной окружения GoTrue.
  Future<void> sendOtp(String e164) async {
    await _auth.signInWithOtp(phone: e164);
  }

  /// Проверяет код OTP. При успехе возвращает состояние профиля: есть ли
  /// завершённая регистрация (name + agreement_accepted_at) или надо
  /// показать экран регистрации.
  ///
  /// Бросает [AuthException] при неверном/просроченном коде.
  Future<VerifyResult> verify({
    required String e164,
    required String code,
  }) async {
    final AuthResponse resp = await _auth.verifyOTP(
      phone: e164,
      token: code,
      type: OtpType.sms,
    );
    final User? user = resp.user;
    if (user == null) {
      throw const AuthException('Пустой пользователь после verifyOTP');
    }
    final Map<String, dynamic>? profile = await _client
        .from('profiles')
        .select('name, avatar_url, agreement_accepted_at')
        .eq('id', user.id)
        .maybeSingle();
    final bool registered = profile != null &&
        profile['agreement_accepted_at'] != null;
    return VerifyResult(
      userId: user.id,
      needsRegistration: !registered,
      name: profile?['name'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
    );
  }

  /// Завершает регистрацию — UPDATE `public.profiles`. Строка уже создана
  /// триггером `handle_new_auth_user` при verifyOTP; здесь обновляем имя,
  /// ссылку на аватар и фиксируем согласие с офертой.
  Future<void> completeRegistration({
    required String name,
    String? avatarUrl,
    String termsVersion = '1.0',
  }) async {
    final User? user = currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    await _client.from('profiles').update({
      'name': name,
      'avatar_url': ?avatarUrl,
      'agreement_accepted_at': DateTime.now().toUtc().toIso8601String(),
      'terms_version': termsVersion,
    }).eq('id', user.id);
  }

  Future<void> signOut() => _auth.signOut();
}

class VerifyResult {
  const VerifyResult({
    required this.userId,
    required this.needsRegistration,
    this.name,
    this.avatarUrl,
  });

  final String userId;
  final bool needsRegistration;
  final String? name;
  final String? avatarUrl;
}

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/auth/otp_device_limit.dart';
import 'package:dispatcher_1/core/realtime/realtime_service.dart';

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
    // Суточный лимит запросов с ЭТОГО устройства (см. OtpDeviceLimit) —
    // против ввода чужих номеров пачками. Маркер ловит authErrorToRu.
    if (!await OtpDeviceLimit.allowed()) {
      throw const AuthException('otp_device_daily_limit');
    }
    await _auth.signInWithOtp(phone: e164);
    await OtpDeviceLimit.record();
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
    // Пересоздаём realtime после signIn. Раньше делали только start()
    // — он идемпотентен и не подменял токен в уже поднятом WebSocket:
    // если канал был открыт на холодном старте под анон-сессией (см.
    // main.dart), он так и оставался анонимным до перезапуска
    // приложения. С точки зрения RLS realtime-payload может не дойти
    // до клиента, который сейчас уже залогинен.
    await RealtimeService.instance.stop();
    RealtimeService.instance.start();
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

/// Если ошибка — «SMS на этот номер уже отправляли, повторно можно через
/// N секунд» (анти-спам частоты GoTrue), возвращает N. Иначе null.
/// Нужна экрану ввода номера: такой отказ означает, что код УЖЕ улетел
/// пользователю меньше минуты назад (повторное нажатие, возврат назад),
/// и правильная реакция — не держать его на номере с сообщением про
/// «новый код», а вести на экран ввода кода: пусть вводит полученный.
int? otpRetryAfterSeconds(Object error) {
  final String raw = error is AuthException ? error.message : error.toString();
  final String lower = raw.toLowerCase();
  if (!lower.contains('security purposes') &&
      !lower.contains('only request this')) {
    return null;
  }
  final Match? m = RegExp(r'(\d+)\s*second').firstMatch(lower);
  final int sec = m != null ? (int.tryParse(m.group(1)!) ?? 0) : 0;
  return sec > 0 ? sec : 60;
}

/// Переводит технические ошибки авторизации в человекочитаемый русский
/// текст. Supabase/GoTrue отдаёт сообщения на английском (ограничение
/// частоты запросов кода, неверный код, сетевые сбои) — показывать их
/// пользователю как есть нельзя. Незнакомые ошибки сворачиваем в общий
/// русский фолбэк, чтобы английский текст не утёк на экран.
String authErrorToRu(Object error) {
  final String raw = error is AuthException ? error.message : error.toString();
  final String lower = raw.toLowerCase();

  // Нет сети / DNS / VPN.
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('clientexception') ||
      lower.contains('connection refused') ||
      lower.contains('connection closed') ||
      lower.contains('errno = 7')) {
    return 'Нет соединения с сервером. Проверьте интернет или отключите VPN.';
  }

  // Суточный лимит запросов кода с этого устройства (OtpDeviceLimit).
  if (lower.contains('otp_device_daily_limit')) {
    return 'С этого устройства запрошено слишком много кодов за сутки. '
        'Попробуйте позже.';
  }

  // Часовой потолок нашего SMS-шлюза: «too many codes for this number».
  // Общий фолбэк тут вреден — он приглашает жать ещё, а лимит часовой.
  if (lower.contains('too many codes')) {
    return 'Превышен лимит кодов для этого номера. Попробуйте через час.';
  }

  // Глобальный часовой потолок шлюза («sms hourly cap reached») — сервис
  // в целом исчерпал лимит отправок; повторное нажатие не поможет.
  if (lower.contains('hourly cap')) {
    return 'Сервис перегружен, SMS временно не отправляются. Попробуйте позже.';
  }

  // Ограничение частоты: "For security purposes, you can only request this
  // after N seconds" / "once every N seconds". Достаём число и склоняем.
  if (lower.contains('security purposes') ||
      lower.contains('rate limit') ||
      lower.contains('too many requests') ||
      lower.contains('only request this')) {
    final Match? m = RegExp(r'(\d+)\s*second').firstMatch(lower);
    final int sec = m != null ? (int.tryParse(m.group(1)!) ?? 0) : 0;
    if (sec > 0) {
      return 'Запросить новый код можно через ${pluralSecondsRu(sec)}.';
    }
    return 'Слишком частые запросы. Подождите немного и попробуйте снова.';
  }

  // Неверный или просроченный код.
  if (lower.contains('expired')) {
    return 'Срок действия кода истёк. Запросите новый.';
  }
  if (lower.contains('invalid') &&
      (lower.contains('otp') ||
          lower.contains('token') ||
          lower.contains('code'))) {
    return 'Неверный код. Проверьте и введите снова.';
  }

  // Незнакомая ошибка — без сырого английского текста.
  return 'Не удалось отправить код. Попробуйте ещё раз.';
}

/// Склонение слова «секунда» по числу: 21 секунду, 22 секунды, 25 секунд.
String pluralSecondsRu(int count) {
  final int r10 = count % 10;
  final int r100 = count % 100;
  final String word;
  if (r100 >= 11 && r100 <= 14) {
    word = 'секунд';
  } else if (r10 == 1) {
    word = 'секунду';
  } else if (r10 >= 2 && r10 <= 4) {
    word = 'секунды';
  } else {
    word = 'секунд';
  }
  return '$count $word';
}

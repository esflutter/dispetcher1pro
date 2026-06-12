import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Аналитика использования (Firebase Analytics).
///
/// Включается из main() только после успешного Firebase.initializeApp() —
/// на устройствах без сервисов Google (Huawei) остаётся выключенной, и все
/// вызовы превращаются в no-op. Каждый вызов дополнительно защищён от
/// исключений: сбой аналитики никогда не должен ломать пользовательский
/// сценарий.
class AppAnalytics {
  AppAnalytics._();

  static FirebaseAnalytics? _analytics;

  /// Зовётся из main() после успешной инициализации Firebase.
  static void enable() {
    try {
      _analytics = FirebaseAnalytics.instance;
    } catch (e) {
      if (kDebugMode) debugPrint('[analytics] недоступна: $e');
    }
  }

  /// Бизнес-событие с понятным именем (registration_complete,
  /// order_created…). Параметры — только строки и числа.
  static void log(String name, [Map<String, Object>? params]) {
    final FirebaseAnalytics? a = _analytics;
    if (a == null) return;
    unawaited(
      a.logEvent(name: name, parameters: params).then(
        (_) {},
        onError: (Object e) {
          if (kDebugMode) debugPrint('[analytics] $name: $e');
        },
      ),
    );
  }

  /// Просмотр экрана. Принимает location роутера; динамические сегменты
  /// (числовые id, uuid) заменяются на «:id», чтобы один и тот же экран
  /// не рассыпался в отчётах на тысячи разных названий.
  static void screen(String location) {
    final FirebaseAnalytics? a = _analytics;
    if (a == null) return;
    final String path = location.split('?').first;
    final String name = path
        .split('/')
        .map((String s) => _isDynamicSegment(s) ? ':id' : s)
        .join('/');
    unawaited(
      a.logScreenView(screenName: name.isEmpty ? '/' : name).then(
        (_) {},
        onError: (Object e) {
          if (kDebugMode) debugPrint('[analytics] screen: $e');
        },
      ),
    );
  }

  static bool _isDynamicSegment(String s) {
    if (s.isEmpty) return false;
    if (RegExp(r'^\d+$').hasMatch(s)) return true;
    // UUID и похожие длинные шестнадцатеричные идентификаторы.
    return RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}$').hasMatch(s);
  }
}

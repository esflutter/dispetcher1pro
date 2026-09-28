import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Страховка от белого экрана на iPhone (версии 1.0.2–1.0.3).
///
/// Причина была такая: Flutter при сборке сам переводил iOS-часть на новую
/// схему запуска (UIScene), библиотека пушей в ней не отвечала на
/// getInitialMessage, а приложение ждало этот ответ до показа интерфейса.
/// Тесты проверяют, что все три защиты на месте.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('автоматический перевод iOS на UIScene выключен в pubspec.yaml', () {
    final String pubspec = _read('pubspec.yaml');
    expect(
      RegExp(r'^  config:\n(?:    .*\n)*?    enable-uiscene-migration: false$',
              multiLine: true)
          .hasMatch(pubspec),
      isTrue,
    );
  });

  test('в iOS-проекте нет UIScene-манифеста', () {
    expect(_read('ios/Runner/Info.plist').contains('UIApplicationSceneManifest'),
        isFalse);
  });

  test('облачная сборка: Xcode 26.x, перевод выключен, сборка проверяется', () {
    final String yaml = _read('codemagic.yaml');
    // Положительные проверки по НЕзакомментированным строкам: удаление строки,
    // «latest» с комментарием или Xcode 27 должны ронять тест.
    expect(
      RegExp(r'^[ ]+xcode:[ ]*"?26\.[0-9x]+(\.[0-9]+)?"?[ ]*(#.*)?$', multiLine: true)
          .hasMatch(yaml),
      isTrue,
      reason: 'Xcode должен быть закреплён на 26.x, пока UIScene выключен',
    );
    expect(
      RegExp(r'^[ ]+FLUTTER_UISCENE_MIGRATION:[ ]*"false"', multiLine: true)
          .hasMatch(yaml),
      isTrue,
    );
    expect(
      RegExp(r'^[ ]+if /usr/libexec/PlistBuddy -c "Print :UIApplicationSceneManifest"',
              multiLine: true)
          .hasMatch(yaml),
      isTrue,
    );
    expect(
      RegExp(r'^[ ]+test -n "\$SUPABASE_URL" \|\|', multiLine: true).hasMatch(yaml),
      isTrue,
    );
  });

  test('iOS: запрос микрофона включён в Podfile', () {
    expect(
      RegExp(r"^[ ]+defs << 'PERMISSION_MICROPHONE=1'", multiLine: true)
          .hasMatch(_read('ios/Podfile')),
      isTrue,
    );
  });

  test('ожидание ответа «открыто из пуша» ограничено по времени', () {
    final String handler = _read('lib/core/push/push_handler.dart');
    expect(RegExp(r'getInitialMessage\(\)\s*\.timeout\(').hasMatch(handler), isTrue);
    final String main = _read('lib/main.dart');
    expect(RegExp(r'PushHandler\.instance\.initialize\(\)\s*\.timeout\(').hasMatch(main),
        isTrue);
  });
}

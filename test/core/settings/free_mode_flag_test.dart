import 'package:flutter_test/flutter_test.dart';

import 'package:dispatcher_1/core/settings/settings_service.dart';

/// Флаг бесплатного режима (`billing.free_mode`) приходит из таблицы настроек
/// в трёх разных видах, и все три встречаются на живом сервере:
///   - числом 1/0 — так пишет переключатель в админ-панели;
///   - булевым true/false — так пишут миграции;
///   - строкой — так значение может прийти через REST.
/// Ошибка разбора здесь означает либо заслонку оплаты там, где платить не
/// нужно, либо бесплатный доступ после возврата подписки. Поэтому проверяем
/// все формы явно, включая мусор.
void main() {
  group('parseFreeModeFlag — режим ВКЛЮЧЁН', () {
    test('булево true', () => expect(parseFreeModeFlag(true), isTrue));
    test('число 1 (так пишет админ-панель)',
        () => expect(parseFreeModeFlag(1), isTrue));
    test('любое ненулевое число', () {
      expect(parseFreeModeFlag(2), isTrue);
      expect(parseFreeModeFlag(-1), isTrue);
      expect(parseFreeModeFlag(0.5), isTrue);
    });
    test('строка "true" в любом регистре', () {
      expect(parseFreeModeFlag('true'), isTrue);
      expect(parseFreeModeFlag('TRUE'), isTrue);
      expect(parseFreeModeFlag('True'), isTrue);
    });
    test('строка "1"', () => expect(parseFreeModeFlag('1'), isTrue));
    test('строка с пробелами по краям', () {
      expect(parseFreeModeFlag('  true  '), isTrue);
      expect(parseFreeModeFlag(' 1 '), isTrue);
    });
  });

  group('parseFreeModeFlag — режим ВЫКЛЮЧЕН', () {
    test('булево false', () => expect(parseFreeModeFlag(false), isFalse));
    test('число 0', () => expect(parseFreeModeFlag(0), isFalse));
    test('строка "false"', () => expect(parseFreeModeFlag('false'), isFalse));
    test('строка "0"', () => expect(parseFreeModeFlag('0'), isFalse));
  });

  group('parseFreeModeFlag — безопасный дефолт на непонятном значении', () {
    test('null — ключа нет в настройках',
        () => expect(parseFreeModeFlag(null), isFalse));
    test('пустая строка', () => expect(parseFreeModeFlag(''), isFalse));
    test('произвольный текст', () {
      expect(parseFreeModeFlag('да'), isFalse);
      expect(parseFreeModeFlag('yes'), isFalse);
      expect(parseFreeModeFlag('вкл'), isFalse);
    });
    test('список и словарь', () {
      expect(parseFreeModeFlag(<String>['true']), isFalse);
      expect(parseFreeModeFlag(<String, Object>{'value': true}), isFalse);
    });
  });
}

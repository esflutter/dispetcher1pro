import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dispatcher_1/core/settings/settings_service.dart';

/// Переключатель «График работы» (`schedule.enabled`) из админ-панели.
///
/// Флаг приходит из таблицы настроек в разных видах: админ-панель пишет
/// числом 1/0, миграции — булевым, через REST может прийти строка. Разбор
/// обязан совпадать с серверным (SQL `schedule_enabled()`), иначе приложение
/// спрячет график, а сервер будет считать его включённым, или наоборот.
/// По умолчанию график ВКЛЮЧЁН — так приложение ведёт себя как раньше.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseScheduleEnabledFlag — включён', () {
    test('булево true', () => expect(parseScheduleEnabledFlag(true), isTrue));
    test('число 1 (так пишет админ-панель)',
        () => expect(parseScheduleEnabledFlag(1), isTrue));
    test('любое ненулевое число, в том числе 2', () {
      expect(parseScheduleEnabledFlag(2), isTrue);
      expect(parseScheduleEnabledFlag(-1), isTrue);
      expect(parseScheduleEnabledFlag(0.5), isTrue);
    });
    test('строки «включено»', () {
      expect(parseScheduleEnabledFlag('1'), isTrue);
      expect(parseScheduleEnabledFlag('true'), isTrue);
      expect(parseScheduleEnabledFlag('TRUE'), isTrue);
      expect(parseScheduleEnabledFlag('t'), isTrue);
      expect(parseScheduleEnabledFlag('yes'), isTrue);
      expect(parseScheduleEnabledFlag('On'), isTrue);
      expect(parseScheduleEnabledFlag('  1  '), isTrue);
    });
  });

  group('parseScheduleEnabledFlag — выключен', () {
    test('булево false',
        () => expect(parseScheduleEnabledFlag(false), isFalse));
    test('число 0 (так пишет админ-панель)', () {
      expect(parseScheduleEnabledFlag(0), isFalse);
      expect(parseScheduleEnabledFlag(0.0), isFalse);
    });
    test('строки «выключено»', () {
      expect(parseScheduleEnabledFlag('0'), isFalse);
      expect(parseScheduleEnabledFlag('false'), isFalse);
      expect(parseScheduleEnabledFlag('False'), isFalse);
      expect(parseScheduleEnabledFlag('f'), isFalse);
      expect(parseScheduleEnabledFlag('no'), isFalse);
      expect(parseScheduleEnabledFlag('OFF'), isFalse);
      expect(parseScheduleEnabledFlag(' 0 '), isFalse);
    });
  });

  group('parseScheduleEnabledFlag — непонятное значение = включён', () {
    test('null — ключа нет в настройках',
        () => expect(parseScheduleEnabledFlag(null), isTrue));
    test('пустая строка и мусор', () {
      expect(parseScheduleEnabledFlag(''), isTrue);
      expect(parseScheduleEnabledFlag('да'), isTrue);
      expect(parseScheduleEnabledFlag('выкл'), isTrue);
      expect(parseScheduleEnabledFlag('2'), isTrue);
    });
    test('список и словарь', () {
      expect(parseScheduleEnabledFlag(<String>['0']), isTrue);
      expect(parseScheduleEnabledFlag(<String, Object>{'value': false}),
          isTrue);
    });
  });

  group('parseSettingsFlag — общий разбор', () {
    test('непонятное значение берёт переданный дефолт', () {
      expect(parseSettingsFlag(null, fallback: false), isFalse);
      expect(parseSettingsFlag('abc', fallback: false), isFalse);
      expect(parseSettingsFlag('abc', fallback: true), isTrue);
    });
    test('явное значение дефолт не трогает', () {
      expect(parseSettingsFlag('yes', fallback: false), isTrue);
      expect(parseSettingsFlag(0, fallback: true), isFalse);
    });
    test('строка "0" — выключено, как на сервере (раньше для '
        'unmarked_day_available давала «включено»)', () {
      expect(parseSettingsFlag('0', fallback: true), isFalse);
    });
  });

  group('resolveSettingsFlag — приоритет сервер → устройство → дефолт', () {
    test('значение с сервера важнее запомненного на устройстве', () {
      expect(resolveSettingsFlag(server: 0, device: true, fallback: true),
          isFalse);
      expect(resolveSettingsFlag(server: 1, device: false, fallback: true),
          isTrue);
    });
    test('непонятное значение с сервера — дефолт, как на сервере', () {
      expect(
          resolveSettingsFlag(server: 'abc', device: false, fallback: true),
          isTrue);
    });
    test('сервера нет — запомненное на устройстве', () {
      expect(resolveSettingsFlag(server: null, device: false, fallback: true),
          isFalse);
    });
    test('нет ничего — дефолт', () {
      expect(resolveSettingsFlag(server: null, device: null, fallback: true),
          isTrue);
    });
  });

  group('SettingsService.scheduleEnabledCached', () {
    final SettingsService s = SettingsService.instance;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      s.debugReset();
    });

    Future<bool?> storedOnDevice() async {
      // Запись на устройство идёт в фоне — даём ей завершиться.
      await Future<void>.delayed(Duration.zero);
      final SharedPreferences p = await SharedPreferences.getInstance();
      return p.getBool('schedule_enabled_v1');
    }

    test('свежий запуск без сети и без запомненного — включён', () {
      expect(s.scheduleEnabledCached, isTrue);
    });

    test('сервер выключил — выключен и запомнено на устройстве', () async {
      s.debugApplyLoaded(<String, dynamic>{'schedule.enabled': 0});
      expect(s.scheduleEnabledCached, isFalse);
      expect(await storedOnDevice(), isFalse);
    });

    test('ключа на сервере нет — включён (как до переключателя)', () async {
      s.debugApplyLoaded(<String, dynamic>{'billing.free_mode': 1});
      expect(s.scheduleEnabledCached, isTrue);
      expect(await storedOnDevice(), isTrue);
    });

    test('холодный старт без сети берёт запомненное на устройстве', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'schedule_enabled_v1': false});
      // Прогрев: поднимает запомненное до сети; сама загрузка в тесте
      // падает (сервера нет) — остаёмся на запомненном.
      await s.warmup();
      expect(s.scheduleEnabledCached, isFalse);
    });

    test('свежий ответ сервера перекрывает запомненное', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'schedule_enabled_v1': false});
      await s.warmup();
      expect(s.scheduleEnabledCached, isFalse);
      s.debugApplyLoaded(<String, dynamic>{'schedule.enabled': 1});
      expect(s.scheduleEnabledCached, isTrue);
      expect(await storedOnDevice(), isTrue);
    });

    test('асинхронный геттер отдаёт то же значение', () async {
      s.debugApplyLoaded(<String, dynamic>{'schedule.enabled': '0'});
      expect(await s.scheduleEnabled(), isFalse);
    });

    test('сигнал обновления меняется при каждой загрузке, даже без '
        'изменений', () {
      final int before = s.revision.value;
      s.debugApplyLoaded(<String, dynamic>{'schedule.enabled': 1});
      s.debugApplyLoaded(<String, dynamic>{'schedule.enabled': 1});
      expect(s.revision.value, before + 2);
    });

    test('подъём запомненного с устройства тоже подаёт сигнал', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'schedule_enabled_v1': false});
      final int before = s.revision.value;
      await s.warmup();
      expect(s.revision.value, greaterThan(before));
    });
  });

  group('SettingsService.unmarkedDayAvailable — общий разбор', () {
    final SettingsService s = SettingsService.instance;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      s.debugReset();
    });

    test('строка "0" — день без отметки нерабочий', () async {
      s.debugApplyLoaded(
          <String, dynamic>{'schedule.unmarked_day_available': '0'});
      expect(await s.unmarkedDayAvailable(), isFalse);
    });

    test('булево false (как на проде)', () async {
      s.debugApplyLoaded(
          <String, dynamic>{'schedule.unmarked_day_available': false});
      expect(await s.unmarkedDayAvailable(), isFalse);
    });

    test('нет ключа — как раньше, рабочий', () async {
      s.debugApplyLoaded(<String, dynamic>{});
      expect(await s.unmarkedDayAvailable(), isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dispatcher_1/core/ai/ai_navigation.dart';
import 'package:dispatcher_1/core/schedule/schedule_prompt_prefs.dart';
import 'package:dispatcher_1/core/settings/settings_service.dart';
import 'package:dispatcher_1/features/executor_card/executor_card_screen.dart';
import 'package:dispatcher_1/features/schedule/widgets/schedule_alerts.dart';

/// Разовый попап «Заполните график работы» и переключатель графика в
/// админ-панели. Главный подвох: отметка «пора показать» хранится на
/// устройстве и переживает перезапуск. Если при выключенном графике её
/// просто не трогать, после включения графика (через месяцы) попап внезапно
/// всплывёт у давних пользователей. Поэтому при выключенном графике сигнал
/// гасится, а отметка «показан» не ставится.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String pendingKey = 'schedule_prompt_pending_v1';
  const String seenKey = 'schedule_prompt_seen_v1';

  Future<SharedPreferences> prefsAfterBackgroundWrites() async {
    // Часть записей идёт в фоне — даём им завершиться.
    await Future<void>.delayed(Duration.zero);
    return SharedPreferences.getInstance();
  }

  setUp(() {
    SettingsService.instance.debugReset();
    SchedulePromptPrefs.pending = false;
    ExecutorCardState.cardCreated = true;
  });

  group('график выключен', () {
    test('попап не показывается, сигнал погашен везде, «показан» не '
        'ставится', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{pendingKey: true});
      SettingsService.instance
          .debugApplyLoaded(<String, dynamic>{'schedule.enabled': 0});
      SchedulePromptPrefs.pending = true;

      expect(await ScheduleAlerts.claimFillSchedulePrompt(), isFalse);

      final SharedPreferences p = await prefsAfterBackgroundWrites();
      expect(SchedulePromptPrefs.pending, isFalse);
      expect(p.getBool(pendingKey), isNull);
      expect(p.getBool(seenKey), isNull);
    });

    test('сигнал гасится, даже если карточка ещё не создана', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{pendingKey: true});
      SettingsService.instance
          .debugApplyLoaded(<String, dynamic>{'schedule.enabled': false});
      ExecutorCardState.cardCreated = false;

      expect(await ScheduleAlerts.claimFillSchedulePrompt(), isFalse);

      final SharedPreferences p = await prefsAfterBackgroundWrites();
      expect(p.getBool(pendingKey), isNull);
      expect(p.getBool(seenKey), isNull);
    });

    test('после включения старый сигнал не всплывает', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{pendingKey: true});
      SettingsService.instance
          .debugApplyLoaded(<String, dynamic>{'schedule.enabled': 0});
      await ScheduleAlerts.claimFillSchedulePrompt();

      SettingsService.instance
          .debugApplyLoaded(<String, dynamic>{'schedule.enabled': 1});
      expect(await ScheduleAlerts.claimFillSchedulePrompt(), isFalse);
    });
  });

  group('график включён — как раньше', () {
    test('сигнал поднят, карточка есть — показываем один раз', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{pendingKey: true});
      SettingsService.instance
          .debugApplyLoaded(<String, dynamic>{'schedule.enabled': 1});

      expect(await ScheduleAlerts.claimFillSchedulePrompt(), isTrue);

      final SharedPreferences p = await prefsAfterBackgroundWrites();
      expect(p.getBool(seenKey), isTrue);
      expect(p.getBool(pendingKey), isNull);
      // Второй раз — уже нет.
      expect(await ScheduleAlerts.claimFillSchedulePrompt(), isFalse);
    });

    test('ключа на сервере нет — график считается включённым', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SettingsService.instance.debugApplyLoaded(<String, dynamic>{});
      SchedulePromptPrefs.pending = true;

      expect(await ScheduleAlerts.claimFillSchedulePrompt(), isTrue);
    });

    test('карточки нет — ждём её, сигнал не трогаем', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{pendingKey: true});
      SettingsService.instance
          .debugApplyLoaded(<String, dynamic>{'schedule.enabled': 1});
      SchedulePromptPrefs.pending = true;
      ExecutorCardState.cardCreated = false;

      expect(await ScheduleAlerts.claimFillSchedulePrompt(), isFalse);

      final SharedPreferences p = await prefsAfterBackgroundWrites();
      expect(SchedulePromptPrefs.pending, isTrue);
      expect(p.getBool(pendingKey), isTrue);
    });

    test('уже показывали — не показываем, сигнал гасим', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{pendingKey: true, seenKey: true});
      SettingsService.instance
          .debugApplyLoaded(<String, dynamic>{'schedule.enabled': 1});

      expect(await ScheduleAlerts.claimFillSchedulePrompt(), isFalse);

      final SharedPreferences p = await prefsAfterBackgroundWrites();
      expect(p.getBool(pendingKey), isNull);
    });

    test('сигнала нет — ничего не делаем', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SettingsService.instance
          .debugApplyLoaded(<String, dynamic>{'schedule.enabled': 1});

      expect(await ScheduleAlerts.claimFillSchedulePrompt(), isFalse);

      final SharedPreferences p = await prefsAfterBackgroundWrites();
      expect(p.getBool(seenKey), isNull);
    });
  });

  group('кнопка ассистента «Открыть график»', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('график выключен — переход в график недоступен, остальные есть', () {
      SettingsService.instance
          .debugApplyLoaded(<String, dynamic>{'schedule.enabled': 0});
      expect(isAssistantActionAvailable('open_schedule'), isFalse);
      expect(isAssistantActionAvailable('open_services'), isTrue);
      expect(isAssistantActionAvailable('open_catalog'), isTrue);
    });

    test('график включён — переход доступен', () {
      SettingsService.instance
          .debugApplyLoaded(<String, dynamic>{'schedule.enabled': 1});
      expect(isAssistantActionAvailable('open_schedule'), isTrue);
    });
  });
}

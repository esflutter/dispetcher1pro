import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/catalog/catalog_service.dart';
import 'core/config/env.dart';
import 'core/realtime/realtime_service.dart';
import 'core/settings/settings_service.dart';
import 'core/theme/system_bar_style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // В release-сборке без `--dart-define` ключей приложение раньше
  // молча запускалось «в моки» — пользователь получал сломанные
  // авторизацию/storage без объяснения. Падаем на старте, чтобы баг
  // увидели сразу, а не после первого запроса в БД.
  if (kReleaseMode) {
    Env.assertConfigured();
  }
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  // Edge-to-edge: на Android 15+ (API 35+) свойства типа
  // `systemNavigationBarColor` игнорируются, и без edge-to-edge система
  // показывает дефолтный чёрный фон под кнопками навигации — видимая
  // тёмная полоса. С edge-to-edge область под нав-баром раскрашивается
  // цветом `Scaffold.backgroundColor`, а SafeArea даёт корректные
  // отступы для контента.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(dispatcherSystemBarStyle());

  if (Env.hasSupabaseConfig) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      debug: false,
    );
    // Прогрев справочников (техника + категории работ) и глобальных
    // настроек (цены подписки/слота, лимиты). Меняются редко, после
    // первого SELECT живут в памяти; экраны фильтра/каталога/создания
    // услуги/оплаты рисуются мгновенно с готовыми значениями.
    // Не блокируем старт приложения — fire-and-forget.
    unawaited(CatalogService.instance.warmup());
    unawaited(SettingsService.instance.warmup());
    // Поднимаем realtime-подписки ТОЛЬКО если есть восстановленная
    // сессия. Раньше start() звался безусловно — на холодном старте
    // без юзера канал открывался под анон-токеном, и RLS-payload не
    // приходил даже после успешного signIn (start() идемпотентен и
    // не пересоздавал каналы). Теперь канал поднимается либо здесь
    // (с уже валидным JWT), либо в auth_service.verify() после signIn.
    if (Supabase.instance.client.auth.currentSession != null) {
      RealtimeService.instance.start();
    }
    // Глобальный listener событий авторизации Supabase. Без него
    // истёкший / отозванный токен не приводил ни к чему — экран мог
    // продолжать показывать «свои данные» пустыми. Сейчас на каждый
    // signedOut поднимаем realtime/storage-кэши, чтобы следующая
    // авторизация шла с чистого состояния.
    Supabase.instance.client.auth.onAuthStateChange
        .listen((AuthState event) async {
      if (event.event == AuthChangeEvent.signedOut) {
        await RealtimeService.instance.stop();
      }
    });
  }

  runApp(const DispatcherApp());
}

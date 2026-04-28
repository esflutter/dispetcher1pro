import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/catalog/catalog_service.dart';
import 'core/config/env.dart';
import 'core/settings/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // В release-сборке без `--dart-define` ключей приложение раньше
  // молча запускалось «в моки» — пользователь получал сломанные
  // авторизацию/storage без объяснения. Падаем на старте, чтобы баг
  // увидели сразу, а не после первого запроса в БД.
  if (kReleaseMode) {
    Env.assertConfigured();
  }
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

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
  }

  runApp(const DispatcherApp());
}

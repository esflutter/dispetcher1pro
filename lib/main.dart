import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/catalog/catalog_service.dart';
import 'core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    // Прогрев справочников (техника + категории работ). 14 + 9 строк,
    // меняются раз в год — после первого SELECT всё живёт в памяти,
    // экраны фильтра/каталога/создания услуги рисуются мгновенно.
    // Не блокируем старт приложения — fire-and-forget.
    unawaited(CatalogService.instance.warmup());
  }

  runApp(const DispatcherApp());
}

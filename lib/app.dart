import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/deep_links.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';

class DispatcherApp extends StatefulWidget {
  const DispatcherApp({super.key});

  @override
  State<DispatcherApp> createState() => _DispatcherAppState();
}

class _DispatcherAppState extends State<DispatcherApp> {
  @override
  void initState() {
    super.initState();
    // Подключаем слушатель deep links для возврата из YooKassa
    // (`dispatcher1pro://payment/result?id=...`).
    // ignore: discarded_futures
    DeepLinks.instance.start().catchError((Object e) {
      debugPrint('[DispatcherApp] DeepLinks.start failed: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    // Базовый размер фрейма Figma — 375 × 812 (iPhone X).
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: false,
      builder: (context, child) {
        return MaterialApp.router(
          title: 'Диспетчер №1 PRO',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: appRouter,
          locale: const Locale('ru', 'RU'),
          supportedLocales: const <Locale>[Locale('ru', 'RU')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        );
      },
    );
  }
}

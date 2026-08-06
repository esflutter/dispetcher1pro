import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/analytics/app_analytics.dart';
import 'core/catalog/catalog_service.dart';
import 'core/config/env.dart';
import 'core/config/firebase_options_ios.dart';
import 'core/push/push_handler.dart';
import 'core/push/push_service.dart';
import 'core/auth/auth_reset.dart';
import 'core/realtime/realtime_service.dart';
import 'core/router.dart';
import 'core/settings/settings_service.dart';
import 'features/shell/main_shell.dart';
import 'features/support/chat_screen.dart';
import 'core/theme/system_bar_style.dart';

/// Обработчик пушей в фоне / при закрытом приложении.
///
/// КРИТИЧНО: `@pragma('vm:entry-point')` нужен в release-сборке. Без него
/// AOT-компилятор Dart вырезает функцию как «неиспользуемую» — нативный
/// FCM SDK не находит handler, и пуши в фоне молча не доходят. Баг
/// проявляется только в release, debug всё показывает корректно.
///
/// Сама функция почти ничего не делает: FCM-SDK покажет системный баннер
/// автоматически (notification-payload), нам остаётся только запустить
/// Firebase в этом изоляте — handler выполняется не в основном изоляте
/// приложения, контекст пуст.
/// На iOS запускаем Firebase с ЯВНЫМИ параметрами: файл настроек не попадает
/// внутрь iOS-сборки (не подключён к Xcode-проекту), и без этого запуск падал,
/// а приложение молча оставалось без пушей. На Android — `null`, то есть
/// прежнее поведение: настройки берутся из своего файла в проекте.
FirebaseOptions? get _firebaseOptions =>
    defaultTargetPlatform == TargetPlatform.iOS ? kFirebaseOptionsIos : null;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // try/catch обязателен: на Huawei/устройствах без GMS Firebase.initializeApp
  // падает с PlatformException, изолят молча умирает и пуш не доходит.
  // Тяжёлую работу не нужно — FCM SDK сам показывает системный баннер.
  try {
    await Firebase.initializeApp(options: _firebaseOptions);
  } catch (e) {
    if (kDebugMode) debugPrint('[bg-push] Firebase init failed: $e');
  }
}

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

  // Firebase инициализируется ДО Supabase, чтобы background-handler
  // FCM, при срабатывании в режиме «приложение убито», мог корректно
  // поднять Firebase в своём изоляте. Под try/catch — без сервисов
  // Google (Huawei, Apple Silicon без Rosetta) Firebase падает, но
  // остальная часть приложения должна продолжать работать.
  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(options: _firebaseOptions);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await PushHandler.instance.initialize();
    PushService.instance.initTokenRefreshListener();
    firebaseReady = true;
    // Аналитика включается только при живом Firebase: на устройствах
    // без сервисов Google все её вызовы остаются no-op.
    AppAnalytics.enable();
  } catch (e) {
    if (kDebugMode) debugPrint('[main] Firebase init failed: $e');
  }

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
      // Прогрев выше шёл под анон-ролью; есть сессия — перечитываем настройки
      // под токеном пользователя, чтобы получить authenticated-only ключи
      // (токен карт). Fire-and-forget.
      unawaited(SettingsService.instance.reload());
    }
    // Глобальный listener событий авторизации Supabase. Без него
    // истёкший / отозванный токен не приводил ни к чему — экран мог
    // продолжать показывать «свои данные» пустыми. Сейчас на каждый
    // signedOut поднимаем realtime/storage-кэши, чтобы следующая
    // авторизация шла с чистого состояния.
    Supabase.instance.client.auth.onAuthStateChange
        .listen((AuthState event) async {
      if (event.event == AuthChangeEvent.signedIn) {
        // Вошли — перечитываем настройки под токеном пользователя, чтобы
        // получить authenticated-only ключи (токен карт map.mapbox_token).
        unawaited(SettingsService.instance.reload());
        // Вход/регистрация (в т.ч. из гостевого режима). Гость мог общаться с
        // ассистентом — его переписка живёт в статической ленте чата и в
        // гостевой серверной сессии (по device_id). При входе чистим их, чтобы
        // они НЕ «прилипли» к только что вошедшему аккаунту: новый юзер
        // начинает ассистента с чистого приветствия (resetHistory дёргает и
        // AiClient.resetSessions — память + сохранённые id, дальше своя история
        // подтянется из БД). На холодном старте уже-вошедшего юзера приходит
        // initialSession (не signedIn), поэтому лишнего сброса при перезапуске
        // не будет. Паритет с приложением заказчика.
        ChatScreen.resetHistory();
        // Гость мог стоять на вкладке «Заказы»/«Профиль» (заглушка). Активная
        // вкладка живёт в статическом сторе и переживает пересоздание shell —
        // после входа возвращаем на каталог.
        MainShell.selectedTab.value = 0;
      }
      if (event.event == AuthChangeEvent.signedOut) {
        await RealtimeService.instance.stop();
        // Принудительный разлогин (токен истёк/отозван, аккаунт удалён с
        // другого устройства): уводим на экран входа с пояснением. Раньше
        // пользователь оставался на текущем экране, который молча пустел.
        // Ручной «Выйти» тоже проходит здесь — он и так ведёт на /auth/phone,
        // повторный go на тот же маршрут безвреден.
        final String loc =
            appRouter.routerDelegate.currentConfiguration.uri.toString();
        if (!loc.startsWith('/auth') && !loc.startsWith('/onboarding') && loc != '/') {
          appRouter.go('/auth/phone');
          final BuildContext? ctx =
              appRouter.routerDelegate.navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text('Сессия завершена — войдите заново.'),
              ),
            );
          }
        }

        // Чистим переписку ассистента и идентификаторы сессий — иначе
        // следующий юзер на этом устройстве увидит чужие сообщения.
        ChatScreen.resetHistory();
        // ПОЛНЫЙ сброс статических сторов (профиль, заказы, услуги, фильтры,
        // верификация/подписка): раньше при принудительном разлогине они
        // переживали смену пользователя — юзер Б видел данные юзера А.
        clearAllLocalState();
        // Push-токен инвалидируется в signOut()/deleteAccount() ДО закрытия
        // сессии (пока запрос к БД ещё авторизован). Здесь, после signedOut,
        // сессия уже мертва и RLS отклонил бы update — поэтому не дублируем.
      }
    });

    // Холодный старт с уже валидной сессией: зарегистрировать FCM-токен.
    // У registerForCurrentUser свой дедуп — повторный вызов из
    // post_login_bootstrap (после OTP) не задвоит регистрацию.
    if (firebaseReady &&
        Supabase.instance.client.auth.currentSession != null) {
      unawaited(PushService.instance.registerForCurrentUser());
    }
  }

  // Просмотры экранов для аналитики: роутер уведомляет о каждой смене
  // маршрута (включая переключение вкладок и переход с пуша).
  appRouter.routerDelegate.addListener(() {
    AppAnalytics.screen(
      appRouter.routerDelegate.currentConfiguration.uri.toString(),
    );
  });

  runApp(const DispatcherApp());
}

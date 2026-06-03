import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/catalog/catalog_service.dart';
import 'core/config/env.dart';
import 'core/push/push_handler.dart';
import 'core/push/push_service.dart';
import 'core/realtime/realtime_service.dart';
import 'core/settings/settings_service.dart';
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
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // try/catch обязателен: на Huawei/устройствах без GMS Firebase.initializeApp
  // падает с PlatformException, изолят молча умирает и пуш не доходит.
  // Тяжёлую работу не нужно — FCM SDK сам показывает системный баннер.
  try {
    await Firebase.initializeApp();
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
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await PushHandler.instance.initialize();
    PushService.instance.initTokenRefreshListener();
    firebaseReady = true;
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
        // Чистим переписку ассистента и идентификаторы сессий — иначе
        // следующий юзер на этом устройстве увидит чужие сообщения.
        ChatScreen.resetHistory();
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

  runApp(const DispatcherApp());
}

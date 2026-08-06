import 'package:firebase_core/firebase_core.dart';

/// Параметры Firebase для iOS, заданные ЯВНО в коде.
///
/// Зачем это нужно. На Android Firebase поднимается сам: файл настроек
/// `google-services.json` лежит в проекте, и его подкладывает Gradle-плагин.
/// На iOS так не получилось: файл `GoogleService-Info.plist` создаётся
/// скриптом сборки на диске, но НЕ подключён к Xcode-проекту, а Xcode кладёт
/// внутрь приложения только то, что явно добавлено в проект. В результате на
/// iOS запуск Firebase падал, ошибка гасилась общим `catch`, и приложение
/// работало вообще без Firebase: пуш-токен не запрашивался никогда.
/// Симптом на проде — десятки android-токенов и ни одного ios.
///
/// Явные параметры снимают зависимость от того, попал файл в сборку или нет.
/// Значения взяты из `GoogleService-Info (исполнитель iOS).plist` в папке
/// передачи проекта; это НЕ секреты — они и так лежат внутри любой
/// опубликованной сборки, доступ к данным ограничивают правила Firebase.
///
/// Android намеренно НЕ трогаем: там всё работает через свой файл настроек,
/// и подмена параметров из кода только создала бы риск на живой платформе.
const FirebaseOptions kFirebaseOptionsIos = FirebaseOptions(
  apiKey: 'AIzaSyBsex8A8gKVT-OZhT1-VfK4qJFbqBcKlNQ',
  appId: '1:389437917871:ios:183bd9650105684dd5a25a',
  messagingSenderId: '389437917871',
  projectId: 'dispetcher-8c871',
  storageBucket: 'dispetcher-8c871.firebasestorage.app',
  iosBundleId: 'com.dispatcher1.pro',
);

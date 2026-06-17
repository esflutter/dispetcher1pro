# Диспетчер №1 PRO — приложение исполнителя

Flutter-приложение для исполнителя биржи спецтехники. Работает с общей Supabase-БД совместно с приложением заказчика (`../dispetcher`).

## Стек

- Flutter **3.41.7** / Dart 3.10+ (CI iOS собирается на этой версии — см. `codemagic.yaml`; локально собирать на ней же)
- Supabase (Auth, Storage, PostgREST, Edge Functions) — self-hosted на Beget
- SMS-авторизация: GoTrue Send-SMS Hook → Edge Function → **RedSMS**
- Платежи: YooKassa (подписка + платные слоты услуг). Конкретные суммы и лимиты НЕ зашиты в код — хранятся в таблице `settings` на сервере
- Карта: Mapbox (основная, токен `MAPBOX_TOKEN`) с фолбэком на OpenFreeMap + flutter_map (vector tiles)
- Адреса: DaData Suggest API
- Навигация: go_router
- Адаптив: flutter_screenutil (целевой Pixel 9, 1080×2424)

## Запуск

Ключи передаются через `--dart-define`:

| Переменная | Где взять | Обязательность |
|------------|-----------|----------------|
| `SUPABASE_URL` | URL self-hosted Supabase, например `https://jokaynapesbem.beget.app` | обязательна |
| `SUPABASE_ANON_KEY` | Публичный anon-JWT из Supabase Studio → Settings → API | обязательна |
| `DADATA_API_KEY` | Token (не Secret!) из dadata.ru → Профиль → API-ключи | опциональна (без неё подсказки адресов пустые) |
| `MAPBOX_TOKEN` | Публичный `pk.…` токен из аккаунта Mapbox | опциональна (без неё карта уходит на запасной OpenFreeMap) |

### Debug-сборка

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://jokaynapesbem.beget.app \
  --dart-define=SUPABASE_ANON_KEY=<anon_jwt> \
  --dart-define=DADATA_API_KEY=<dadata_token> \
  --dart-define=MAPBOX_TOKEN=<pk_token>
```

### Release-сборка

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://jokaynapesbem.beget.app \
  --dart-define=SUPABASE_ANON_KEY=<anon_jwt> \
  --dart-define=DADATA_API_KEY=<dadata_token> \
  --dart-define=MAPBOX_TOKEN=<pk_token>
```

В release без `SUPABASE_URL` и `SUPABASE_ANON_KEY` приложение упадёт на старте с явной ошибкой (см. `Env.assertConfigured()` в `lib/core/config/env.dart`).

`DADATA_API_KEY` и `MAPBOX_TOKEN` опциональны: без DaData подсказки адресов вернут пустой список; без Mapbox карта работает на запасном OpenFreeMap. Остальное продолжит работать. Готовые значения для прод-сборки — в `run_prod.bat` (передаётся отдельно, в `.gitignore`).

### VSCode launch.json

Удобно положить дев-ключи в `.vscode/launch.json`:

```json
{
  "configurations": [
    {
      "name": "executor (dev)",
      "request": "launch",
      "type": "dart",
      "toolArgs": [
        "--dart-define=SUPABASE_URL=https://jokaynapesbem.beget.app",
        "--dart-define=SUPABASE_ANON_KEY=<anon_jwt>",
        "--dart-define=DADATA_API_KEY=<dadata_token>",
        "--dart-define=MAPBOX_TOKEN=<pk_token>"
      ]
    }
  ]
}
```

`launch.json` уже в `.gitignore` — секреты не попадут в репозиторий.

## Тестовые номера для SMS

В Supabase в `GOTRUE_SMS_TEST_OTP` прописаны тестовые номера (заказчик + исполнители; список синхронизирован с `seed_executors.sql`). На них SMS не уходит — код фиксированный, см. конфиг GoTrue. Для нетестовых номеров отправка идёт через **RedSMS** (переменные `REDSMS_*`; `REDSMS_TEST_MODE` держим включённым до подключения зарегистрированного имени отправителя).

## Структура

- `lib/core/` — сервисы (Auth, Catalog, Payments, Profile, Storage, Settings, DaData)
- `lib/features/` — экраны (auth, onboarding, shell, catalog, orders, services, schedule, profile, executor_card, subscription, support)
- `supabase/` (в корне репо вне приложений) — миграции и Edge Functions

## Полезные команды

```bash
flutter analyze                  # статический анализ
flutter pub outdated             # проверить обновления зависимостей
flutter test                     # запустить тесты (когда появятся)
flutter clean && flutter pub get # сбросить кэш сборки
```

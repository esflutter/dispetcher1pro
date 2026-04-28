# Диспетчер №1 PRO — приложение исполнителя

Flutter-приложение для исполнителя биржи спецтехники. Работает с общей Supabase-БД совместно с приложением заказчика (`../dispetcher`).

## Стек

- Flutter 3.10+ / Dart 3.10+
- Supabase (Auth, Storage, PostgREST, Edge Functions) — self-hosted на Beget
- SMS-авторизация: GoTrue Send-SMS Hook → Edge Function → sms.ru
- Платежи: YooKassa (подписка 490₽/мес + слоты услуг 99₽)
- Карта: OpenFreeMap + flutter_map (vector tiles)
- Адреса: DaData Suggest API
- Навигация: go_router
- Адаптив: flutter_screenutil (целевой Pixel 9, 1080×2424)

## Запуск

Нужны три ключа, передаются через `--dart-define`:

| Переменная | Где взять |
|------------|-----------|
| `SUPABASE_URL` | URL self-hosted Supabase, например `https://jokaynapesbem.beget.app` |
| `SUPABASE_ANON_KEY` | Публичный anon-JWT из Supabase Studio → Settings → API |
| `DADATA_API_KEY` | Token (не Secret!) из dadata.ru → Профиль → API-ключи |

### Debug-сборка

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://jokaynapesbem.beget.app \
  --dart-define=SUPABASE_ANON_KEY=<anon_jwt> \
  --dart-define=DADATA_API_KEY=<dadata_token>
```

### Release-сборка

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://jokaynapesbem.beget.app \
  --dart-define=SUPABASE_ANON_KEY=<anon_jwt> \
  --dart-define=DADATA_API_KEY=<dadata_token>
```

В release без `SUPABASE_URL` и `SUPABASE_ANON_KEY` приложение упадёт на старте с явной ошибкой (см. `Env.assertConfigured()` в `lib/core/config/env.dart`).

`DADATA_API_KEY` опционален: без него подсказки адресов вернут пустой список, но всё остальное продолжит работать.

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
        "--dart-define=DADATA_API_KEY=<dadata_token>"
      ]
    }
  ]
}
```

`launch.json` уже в `.gitignore` — секреты не попадут в репозиторий.

## Тестовые номера для SMS

В Supabase в `GOTRUE_SMS_TEST_OTP` прописан 31 тестовый номер (1 заказчик + 30 исполнителей). На них SMS не уходит — код фиксированный, см. конфиг GoTrue. Для нетестовых номеров отправка идёт через sms.ru (в TEST_MODE до подключения зарегистрированного отправителя).

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

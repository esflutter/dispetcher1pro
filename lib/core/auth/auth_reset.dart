import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/push/push_service.dart';
import 'package:dispatcher_1/core/realtime/realtime_service.dart';
import 'package:dispatcher_1/core/utils/photo_source.dart' show clearSignedUrlCache;
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/executor_card/executor_card_screen.dart';
import 'package:dispatcher_1/features/orders/order_detail_screen.dart';
import 'package:dispatcher_1/features/profile/account_block.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';
import 'package:dispatcher_1/features/services/my_services_screen.dart';
import 'package:dispatcher_1/features/shell/main_shell.dart';
import 'package:dispatcher_1/features/support/chat_screen.dart';
import 'package:dispatcher_1/features/support/widgets/chat_bubble.dart' show PublishedDraftRegistry;

/// Выход из аккаунта. Закрываем сессию Supabase (иначе RLS будет
/// пропускать запросы как от прошлого пользователя) и чистим все
/// статические сторы. При повторном входе профиль/услуги/заказы
/// подтянутся из БД заново.
Future<void> signOut() async {
  // Сначала останавливаем realtime — иначе подписки продолжат держать
  // WebSocket-соединение от имени прошлого юзера. Делаем до signOut,
  // чтобы Supabase сам не успел кинуть auth-error в наш callback.
  await RealtimeService.instance.stop();
  // Инвалидируем push-токен ПОКА сессия жива. Если сделать это после
  // signOut (как раньше — в listener onAuthStateChange), запрос к БД уйдёт
  // без авторизации, RLS его отклонит, и токен останется привязан к
  // вышедшему пользователю — следующий человек на устройстве получал бы
  // его пуши. clearForCurrentUser сам безопасен, даже если Firebase не готов.
  await PushService.instance.clearForCurrentUser();
  try {
    await Supabase.instance.client.auth.signOut();
  } catch (_) {/* всё равно чистим локально */}
  _clearAll();
}

/// Удаление аккаунта. Закрываем сессию Supabase и делаем тот же сброс
/// всех сторов, что и при выходе. Сами данные удаляются на сервере
/// отдельным RPC, который дёргает экран профиля до вызова этой функции.
Future<void> deleteAccount() async {
  await RealtimeService.instance.stop();
  // То же, что в signOut: снимаем push-токен до закрытия сессии.
  await PushService.instance.clearForCurrentUser();
  try {
    await Supabase.instance.client.auth.signOut();
  } catch (_) {/* всё равно чистим локально */}
  _clearAll();
}

/// Полная очистка всех глобальных статических хранилищ. Каждый новый
/// «стор» с пользовательскими данными обязан чиститься здесь — иначе
/// на устройстве у следующего пользователя останутся старые данные.
void _clearAll() {
  // Профиль: имя/телефон/почта/аватар.
  CropResult.clearAuthData();

  // Блокировка аккаунта и история отзывов о пользователе.
  AccountBlock.forceLift();
  ReviewsData.resetToDefault();

  // Статус верификации и подписка.
  VerificationStatus.clearAuthData();

  // Карточка исполнителя.
  ExecutorCardData.clear();
  ExecutorCardScreen.cardCreated = false;

  // Услуги исполнителя.
  ServiceData.clear();

  // Заказы исполнителя локально не кэшируются — экран дёргает
  // listMine() из БД при каждом showtime, ничего сбрасывать не нужно.
  // Но локальная метка «уже оставил отзыв» (по orderNumber) живёт в
  // static Set, и без этого сброса следующий пользователь на том же
  // устройстве не увидел бы кнопку отзыва на заказах с совпадающим
  // display_number.
  MyOrderDetailScreen.resetReviewedOrders();

  // История чата с ассистентом — иначе у следующего пользователя
  // на устройстве осталась бы переписка предыдущего.
  ChatScreen.resetHistory();

  // Реестр опубликованных черновиков ассистента (кнопка «Создать»). Без
  // сброса следующий пользователь, попросив собрать идентичный черновик,
  // увидел бы кнопку заблокированной с текстом «уже опубликовано».
  PublishedDraftRegistry.clear();

  // Применённые фильтры каталога.
  AppliedFilter.clear();

  // Активная вкладка нижней навигации.
  MainShell.selectedTab.value = 0;

  // Кэш подписанных URL приватных файлов. Подпись валидна 50 минут —
  // без сброса следующий юзер на устройстве теоретически мог получить
  // живой URL от чужой записи storage (типично при коллизии путей,
  // например общий placeholder-аватар).
  clearSignedUrlCache();
}

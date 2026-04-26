import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/executor_card/executor_card_screen.dart';
import 'package:dispatcher_1/features/profile/account_block.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';
import 'package:dispatcher_1/features/services/my_services_screen.dart';
import 'package:dispatcher_1/features/shell/main_shell.dart';
import 'package:dispatcher_1/features/support/chat_screen.dart';

/// Выход из аккаунта. Закрываем сессию Supabase (иначе RLS будет
/// пропускать запросы как от прошлого пользователя) и чистим все
/// статические сторы. При повторном входе профиль/услуги/заказы
/// подтянутся из БД заново.
Future<void> signOut() async {
  try {
    await Supabase.instance.client.auth.signOut();
  } catch (_) {/* всё равно чистим локально */}
  _clearAll();
}

/// Удаление аккаунта. Закрываем сессию Supabase и делаем тот же сброс
/// всех сторов, что и при выходе. Сами данные удаляются на сервере
/// отдельным RPC, который дёргает экран профиля до вызова этой функции.
Future<void> deleteAccount() async {
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

  // История чата с ассистентом — иначе у следующего пользователя
  // на устройстве осталась бы переписка предыдущего.
  ChatScreen.resetHistory();

  // Применённые фильтры каталога.
  AppliedFilter.clear();

  // Активная вкладка нижней навигации.
  MainShell.selectedTab.value = 0;
}

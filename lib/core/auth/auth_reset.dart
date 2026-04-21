import 'package:dispatcher_1/core/auth/session_cache.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/executor_card/executor_card_screen.dart';
import 'package:dispatcher_1/features/orders/my_orders_screen.dart';
import 'package:dispatcher_1/features/profile/account_block.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';
import 'package:dispatcher_1/features/services/my_services_screen.dart';
import 'package:dispatcher_1/features/shell/main_shell.dart';

/// Выход из аккаунта. Снимок пользовательских данных по текущему номеру
/// кладём в [SessionCache] — чтобы при повторном входе с тем же номером
/// регистрация не требовалась и всё восстановилось. Потом чистим все
/// статические сторы, чтобы экран `/auth/phone` не показывал остатки.
void signOut() {
  SessionCache.save(CropResult.userPhone);
  _clearAll();
}

/// Удаление аккаунта. Снимок из кэша выбрасываем — повторный вход по
/// тому же номеру начинается с регистрации «с нуля». Потом тот же
/// сброс всех сторов, что и при выходе.
void deleteAccount() {
  SessionCache.drop(CropResult.userPhone);
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

  // Заказы (новые/принятые/отклонённые).
  MyOrdersStore.clear();

  // Применённые фильтры каталога.
  AppliedFilter.clear();

  // Активная вкладка нижней навигации.
  MainShell.selectedTab.value = 0;
}

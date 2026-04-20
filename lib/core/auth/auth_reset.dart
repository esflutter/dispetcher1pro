import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/executor_card/executor_card_screen.dart';
import 'package:dispatcher_1/features/profile/account_block.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';
import 'package:dispatcher_1/features/services/my_services_screen.dart';
import 'package:dispatcher_1/features/shell/main_shell.dart';

/// Единая точка очистки всех глобальных статических хранилищ при
/// выходе из аккаунта или удалении аккаунта. До того как в приложение
/// прикрутят настоящий бэкенд, все «пользовательские» данные хранятся
/// в статических полях классов — и без явного сброса они переживают
/// переход на `/auth/phone` и появляются у следующего, кто
/// зарегистрируется на этом устройстве.
///
/// Добавляя новый статический «стор» с пользовательскими данными,
/// дополняй эту функцию — иначе регрессия.
void resetForLogout() {
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

  // Применённые фильтры каталога.
  AppliedFilter.clear();

  // Активная вкладка нижней навигации.
  MainShell.selectedTab.value = 0;
}

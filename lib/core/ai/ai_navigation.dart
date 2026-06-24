// =====================================================================
// ai_navigation.dart — единая точка открытия чата с ассистентом.
//
// Раньше каждое место в UI делало context.push('/assistant/chat') —
// если юзер тапал FAB ассистента дважды подряд, в стеке появлялся
// второй экран чата поверх первого. Хуже: на самом /assistant/chat
// тап по «второму» FAB (если он откуда-то проникал в дерево) тоже
// клал ещё один чат.
//
// Этот helper:
//   - если уже на /assistant/chat — ничего не делает;
//   - если /assistant/chat есть в стеке ниже — pop'ает до него;
//   - иначе — push'ит свежий.
// =====================================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/auth/guest_gate.dart';
import 'package:dispatcher_1/core/utils/support_contact.dart';
import 'package:dispatcher_1/features/shell/main_shell.dart';

const String _kAssistantChat = '/assistant/chat';

/// Открыть чат с ассистентом без дубликатов.
/// [extra] — необязательный объект, передаётся как state.extra.
Future<void> openAssistantChat(
  BuildContext context, {
  Object? extra,
}) async {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;

  final String current = router.routerDelegate.currentConfiguration.fullPath;
  if (current == _kAssistantChat) {
    // Уже на чате — не пушим повторно. Если был передан extra с initial-
    // intent (например, verify_documents) — игнорируем, юзер уже видит чат.
    return;
  }

  // GoRouter не предоставляет API "есть ли путь в стеке". Используем
  // Navigator.popUntil с проверкой по routeSettings — для GoRoute
  // settings.name == path, а fullPath проверяем через current стек.
  // На практике пользователь либо на корневом табе (current ≠ /assistant/chat
  // → push), либо уже в стек запушен chat (current == /assistant/chat → ничего).
  // Кейса "чат глубоко в стеке, но текущий другой" в нашем UI не бывает,
  // так что просто пушим.
  await router.push(_kAssistantChat, extra: extra);
}

/// Перейти в раздел приложения по ключу действия от ассистента — это
/// обработчик кнопки «Перейти» под ответом. Ключи приходят с сервера
/// (см. _shared/navSuggest.ts). Корневые вкладки открываем переключением
/// таба (а не push'ем второй копии), остальное — push'ем поверх чата.
/// Неизвестный ключ — ничего не делаем (молча, без краша).
void navigateAssistantAction(BuildContext context, String action) {
  // Гость: разделы аккаунта (услуги/подписка/график/карточка/документы/отзывы/
  // мои заказы/способы оплаты) доступны только после входа. Вместо «тупого»
  // перехода в экран для вошедших показываем приглашение войти. Каталог
  // (просмотр заказов) и поддержка (внешний мессенджер) — без входа.
  if (isGuest && action != 'open_catalog' && action != 'contact_support') {
    showGuestAuthPrompt(context, message: 'Этот раздел доступен после входа.');
    return;
  }
  switch (action) {
    case 'open_cards':
      context.push('/subscription/cards');
    case 'open_subscription':
      context.push('/subscription/manage');
    case 'open_executor_card':
    case 'start_verification':
      // Карточка исполнителя — отсюда же запускается отправка документов.
      context.push('/executor-card');
    case 'open_services':
      context.push('/services');
    case 'open_schedule':
      context.push('/schedule');
    case 'open_reviews':
      context.push('/profile/reviews');
    case 'open_my_orders':
      MainShell.selectedTab.value = 1;
      context.go('/shell');
    case 'open_catalog':
      MainShell.selectedTab.value = 0;
      context.go('/shell');
    case 'contact_support':
      // Живой человек — открываем мессенджер поддержки прямо из чата.
      // Быстрее, чем вести в «Профиль» и искать там иконку. Пока ссылка
      // не задана (kSupportMessengerUrl) — показывается мягкая заглушка.
      openSupportMessenger(context);
    default:
      break;
  }
}

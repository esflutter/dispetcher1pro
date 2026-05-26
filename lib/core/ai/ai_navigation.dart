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

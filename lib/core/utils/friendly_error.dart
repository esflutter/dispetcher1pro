import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Переводит «сырое» исключение в понятный пользователю текст.
///
/// До этого в снэкбары попадали серверные коды («subscription_inactive»,
/// «account_blocked») и английские сетевые исключения (SocketException…) —
/// аудит жизненных состояний показал десяток таких мест. Теперь все они
/// зовут этот хелпер: известные коды переводятся, сеть/таймаут/сессия
/// получают свои объяснения, остальное — нейтральный текст без жаргона.
String friendlyError(Object e, {String fallback = 'Не удалось выполнить. Попробуйте ещё раз.'}) {
  final String raw = e.toString();

  // Гонка статусов (FSM-триггер в БД): «опоздал» — другая сторона уже
  // отозвала/выбрала/отменила. Раньше это падало в generic «попробуйте ещё
  // раз», хотя повтор не поможет никогда.
  if (raw.contains('Нельзя изменить финальный статус') ||
      raw.contains('Недопустимый переход') ||
      raw.contains('Нельзя принять мэтч')) {
    return 'Действие уже неактуально — ситуация по заказу изменилась. Обновите список.';
  }

  // Известные серверные коды бизнес-замков (триггеры в БД).
  if (raw.contains('account_blocked')) {
    return 'Профиль заблокирован — действие недоступно. Подробности в «Профиле»; если это ошибка, напишите в поддержку.';
  }
  if (raw.contains('subscription_inactive')) {
    return 'Подписка исполнителя неактивна. Продлить её можно в «Профиль → Подписка и оплата».';
  }
  if (raw.contains('executor_not_verified')) {
    return 'Исполнитель ещё не прошёл верификацию — выбрать его пока нельзя.';
  }
  if (raw.contains('executor_blocked')) {
    return 'Этот исполнитель заблокирован — выберите, пожалуйста, другого.';
  }
  if (raw.contains('card_not_published')) {
    return 'Карточка исполнителя снята с публикации — выберите другого исполнителя.';
  }
  if (raw.contains('daily_limit') || raw.contains('Лимит заказов')) {
    return 'Лимит заказов на сегодня исчерпан. Новый заказ можно создать завтра.';
  }

  // Сессия умерла (токен истёк / аккаунт удалён).
  if (e is AuthException || raw.contains('JWT') || raw.contains('Нет активной сессии')) {
    return 'Сессия истекла — войдите в приложение заново.';
  }

  // Сеть и таймауты.
  if (e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      raw.contains('SocketException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('Connection') ||
      raw.contains('ClientException')) {
    return 'Нет соединения с сервером. Проверьте интернет и попробуйте снова.';
  }

  return fallback;
}

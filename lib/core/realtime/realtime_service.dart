import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/my_orders/my_orders_service.dart';
import 'package:dispatcher_1/features/profile/account_block.dart' show ReviewsData;

/// Глобальный фоновой подписчик на Supabase Realtime. Запускается один
/// раз при старте приложения (см. `main.dart`); слушает изменения трёх
/// ключевых таблиц и оповещает уже существующие `ValueNotifier`-маяки.
///
/// Раньше realtime не использовался нигде в коде — экраны полагались
/// на ручной `_refresh()` через notifier-маяки, которые двигались только
/// от собственных действий пользователя. Из-за этого:
///   - заказчик не видел, что исполнитель откликнулся, пока сам не
///     открывал/закрывал экран;
///   - исполнитель не видел, что заказчик принял или отклонил его
///     отклик;
///   - новый отзыв не дёргал рейтинг и список отзывов получателя.
///
/// Тут централизованно подписываемся на `orders`, `order_matches` и
/// `reviews` (включены в `supabase_realtime` publication на стороне БД)
/// и при любом INSERT/UPDATE/DELETE бампим соответствующий маяк. Экраны,
/// подписанные на эти маяки, перерисовываются автоматически.
class RealtimeService {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();

  /// Маяк ленты заказов в каталоге. До этого его не было — лента
  /// перетягивалась только при тапе по фильтру или возврате на экран.
  /// Теперь любое изменение в таблице `orders` бампит этот ValueNotifier,
  /// и `order_feed_screen` подписан на него.
  static final ValueNotifier<int> ordersFeedBeacon = ValueNotifier<int>(0);

  RealtimeChannel? _ordersChan;
  RealtimeChannel? _matchesChan;
  RealtimeChannel? _reviewsChan;
  bool _started = false;

  /// Включить подписки. Вызывается из `main.dart` ОДИН раз после
  /// `Supabase.initialize`. Повторные вызовы игнорируются.
  ///
  /// Подписки висят до конца жизни процесса — мобильное приложение
  /// обычно живёт пока пользователь его не закроет, и потеря-восстановление
  /// сетевого соединения обрабатывается самим Supabase SDK прозрачно.
  void start() {
    if (_started) return;
    _started = true;
    final SupabaseClient client = Supabase.instance.client;

    _ordersChan = client
        .channel('public:orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (PostgresChangePayload _) {
            ordersFeedBeacon.value = ordersFeedBeacon.value + 1;
          },
        )
        .subscribe();

    _matchesChan = client
        .channel('public:order_matches')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_matches',
          callback: (PostgresChangePayload _) {
            // У `MyOrdersService` уже есть глобальный маяк, на который
            // подписан экран «Мои заказы». Используем его, чтобы не
            // плодить дубли notifier'ов под одну и ту же сущность.
            MyOrdersService.bumpChangeBeacon();
            // Лента в каталоге тоже зависит от order_matches: пометка
            // «вы уже откликнулись» формируется из этой таблицы.
            ordersFeedBeacon.value = ordersFeedBeacon.value + 1;
          },
        )
        .subscribe();

    _reviewsChan = client
        .channel('public:reviews')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reviews',
          callback: (PostgresChangePayload _) {
            // ReviewsData.revision — существующий маяк для экрана
            // отзывов и плашки рейтинга в профиле. Дёргаем его.
            ReviewsData.revision.value = ReviewsData.revision.value + 1;
          },
        )
        .subscribe();
  }

  /// Полная отписка. Зовётся при выходе из аккаунта — иначе подписки
  /// держат соединения для уже не авторизованного клиента.
  Future<void> stop() async {
    final SupabaseClient client = Supabase.instance.client;
    for (final RealtimeChannel? ch in <RealtimeChannel?>[
      _ordersChan,
      _matchesChan,
      _reviewsChan,
    ]) {
      if (ch != null) {
        try {
          await client.removeChannel(ch);
        } catch (_) {/* не блокируем logout, соединение само закроется */}
      }
    }
    _ordersChan = null;
    _matchesChan = null;
    _reviewsChan = null;
    _started = false;
  }
}

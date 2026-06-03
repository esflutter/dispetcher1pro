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
/// `reviews` (включены в `supabase_realtime` publication на стороне БД).
///
/// Два приёма против лишней нагрузки:
///   1) Дебаунс — всплеск событий во всей базе склеивается в один
///      перезапрос, а не в десяток.
///   2) Фильтр по своим данным — для `order_matches` исполнителю важны
///      только отклики, где он сам исполнитель (и в «Моих заказах», и
///      для пометки «вы откликнулись» в ленте). Чужие отклики пропускаем.
class RealtimeService {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();

  /// Маяк ленты заказов в каталоге. До этого его не было — лента
  /// перетягивалась только при тапе по фильтру или возврате на экран.
  static final ValueNotifier<int> ordersFeedBeacon = ValueNotifier<int>(0);

  RealtimeChannel? _ordersChan;
  RealtimeChannel? _matchesChan;
  RealtimeChannel? _reviewsChan;
  bool _started = false;

  // Окно склейки всплеска событий. 600 мс незаметно для пользователя, но
  // превращает «пачку» чужих изменений в один перезапрос.
  static const Duration _debounceWindow = Duration(milliseconds: 600);
  Timer? _ordersDebounce;
  Timer? _matchesDebounce;
  Timer? _reviewsDebounce;

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
            // Лента каталога показывает чужие заказы — фильтровать по
            // «своему» id тут нечего, но дебаунс гасит частоту.
            _scheduleOrders();
          },
        )
        .subscribe();

    _matchesChan = client
        .channel('public:order_matches')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_matches',
          callback: (PostgresChangePayload payload) {
            final String? me = client.auth.currentUser?.id;
            final String? exec = _recordField(payload, 'executor_id');
            // Исполнителю важны только отклики, где он — исполнитель.
            // Чужие отклики не трогают ни «Мои заказы», ни его пометку
            // «вы откликнулись» в ленте. Если id определить не удалось —
            // обновим на всякий случай (дебаунс склеит всплеск).
            if (me != null && exec != null && exec != me) return;
            _scheduleMatches();
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
            _scheduleReviews();
          },
        )
        .subscribe();
  }

  void _scheduleOrders() {
    _ordersDebounce?.cancel();
    _ordersDebounce = Timer(_debounceWindow, () {
      ordersFeedBeacon.value = ordersFeedBeacon.value + 1;
    });
  }

  void _scheduleMatches() {
    _matchesDebounce?.cancel();
    _matchesDebounce = Timer(_debounceWindow, () {
      // У `MyOrdersService` уже есть глобальный маяк, на который подписан
      // экран «Мои заказы». Лента в каталоге тоже зависит от order_matches
      // (пометка «вы уже откликнулись»).
      MyOrdersService.bumpChangeBeacon();
      ordersFeedBeacon.value = ordersFeedBeacon.value + 1;
    });
  }

  void _scheduleReviews() {
    _reviewsDebounce?.cancel();
    _reviewsDebounce = Timer(_debounceWindow, () {
      ReviewsData.revision.value = ReviewsData.revision.value + 1;
    });
  }

  /// Достаёт значение поля из изменённой строки. Для INSERT берём из
  /// `newRecord`, для DELETE — из `oldRecord` (оба — Map, пустой `{}`,
  /// если данных нет).
  static String? _recordField(PostgresChangePayload p, String field) {
    final dynamic nv = p.newRecord[field];
    if (nv != null) return nv.toString();
    final dynamic ov = p.oldRecord[field];
    return ov?.toString();
  }

  /// Полная отписка. Зовётся при выходе из аккаунта — иначе подписки
  /// держат соединения для уже не авторизованного клиента.
  Future<void> stop() async {
    _ordersDebounce?.cancel();
    _matchesDebounce?.cancel();
    _reviewsDebounce?.cancel();
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

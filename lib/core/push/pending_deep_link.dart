import 'package:flutter/foundation.dart';

/// Глобальный буфер deep-link «открыть конкретный заказ».
///
/// Поток:
///  1. Юзер тапает пуш (новый отклик / отзыв / accept). PushHandler
///     читает `order_id` из payload и кладёт сюда.
///  2. PushHandler переводит router на `/shell` и переключает таб
///     «Мои заказы».
///  3. MyOrdersScreen слушает `pendingOrderDeepLink` и при появлении
///     значения находит запись в своём store, открывает экран деталей,
///     сбрасывает значение обратно в `null`.
///
/// Этот ValueNotifier нужен потому, что у нас Detail-экран принимает
/// готовый объект (OrderDraft + executor info + статус и т.п.), а не
/// идентификатор. Поднимать всё это по id из роутера было бы кратно
/// сложнее — а реальный pending-store с теми же данными у нас уже
/// загружен, надо только указать MyOrdersScreen «открой вот этот».
final ValueNotifier<String?> pendingOrderDeepLink =
    ValueNotifier<String?>(null);

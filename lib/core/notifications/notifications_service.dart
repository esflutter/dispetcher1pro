import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Запись из таблицы `public.notifications`.
@immutable
class InboxNotification {
  const InboxNotification({
    required this.id,
    required this.eventKind,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
    this.readAt,
    this.route,
  });

  final String id;
  final String eventKind;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? route;

  bool get isUnread => readAt == null;

  factory InboxNotification.fromRow(Map<String, dynamic> row) {
    final Map<String, dynamic> data = row['data'] is Map<String, dynamic>
        ? (row['data'] as Map<String, dynamic>)
        : <String, dynamic>{};
    return InboxNotification(
      id: row['id'] as String,
      eventKind: row['event_kind'] as String? ?? '',
      title: row['title'] as String? ?? '',
      body: row['body'] as String? ?? '',
      data: data,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      readAt: row['read_at'] != null
          ? DateTime.parse(row['read_at'] as String).toLocal()
          : null,
      route: data['route'] is String ? data['route'] as String : null,
    );
  }
}

/// Загрузка списка уведомлений из БД + realtime-подписка + RPC mark-read.
///
/// Realtime-подписка нужна, чтобы бейдж непрочитанных и сам список
/// обновлялись без рефетча: пришёл новый пуш → realtime событие → UI
/// перерисовывается мгновенно (даже до того как FCM доставит баннер).
class NotificationsService {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();

  SupabaseClient get _client => Supabase.instance.client;

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  RealtimeChannel? _channel;
  bool _started = false;

  /// Подписаться на изменения своих уведомлений + посчитать непрочитанные.
  /// Вызывается после OTP-логина и при старте с валидной сессией.
  void start() {
    if (_started) return;
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    _started = true;

    // Пересчитываем счётчик непрочитанных при любом изменении.
    _channel = _client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (PostgresChangePayload payload) {
            // На любое изменение в notifications текущего юзера —
            // перечитываем счётчик. Дешевле чем поддерживать локальный
            // мап и реагировать на каждое событие отдельно.
            unawaited(refreshUnreadCount());
          },
        )
        .subscribe();

    unawaited(refreshUnreadCount());
  }

  Future<void> stop() async {
    _started = false;
    final RealtimeChannel? ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await _client.removeChannel(ch);
      } catch (e) {
        if (kDebugMode) debugPrint('[notifications] removeChannel: $e');
      }
    }
    unreadCount.value = 0;
  }

  Future<void> refreshUnreadCount() async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) {
      unreadCount.value = 0;
      return;
    }
    try {
      final dynamic c = await _client
          .from('notifications')
          .count(CountOption.exact)
          .eq('user_id', userId)
          .filter('read_at', 'is', null);
      if (c is int) {
        unreadCount.value = c;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[notifications] refreshUnread failed: $e');
    }
  }

  /// Список уведомлений от свежих к старым с пагинацией.
  Future<List<InboxNotification>> fetchPage({
    int limit = 50,
    DateTime? before,
  }) async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) return <InboxNotification>[];

    PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _client
        .from('notifications')
        .select('id, event_kind, title, body, data, created_at, read_at')
        .eq('user_id', userId);

    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }

    final List<Map<String, dynamic>> rows =
        await query.order('created_at', ascending: false).limit(limit);

    return rows.map(InboxNotification.fromRow).toList(growable: false);
  }

  /// Пометить одно уведомление прочитанным (RPC, проверяет ownership).
  Future<void> markRead(String notificationId) async {
    try {
      await _client.rpc('mark_notification_read', params: <String, dynamic>{
        'p_notification_id': notificationId,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[notifications] markRead failed: $e');
    }
  }

  /// Пометить все непрочитанные текущего юзера как read.
  Future<int> markAllRead() async {
    try {
      final dynamic v =
          await _client.rpc('mark_all_notifications_read');
      if (v is int) return v;
    } catch (e) {
      if (kDebugMode) debugPrint('[notifications] markAllRead failed: $e');
    }
    return 0;
  }
}

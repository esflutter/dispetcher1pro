import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/notifications_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Экран «Уведомления» — in-app inbox всех пушей и системных сообщений.
///
/// Список приходит из таблицы `notifications`, RLS показывает только
/// записи текущего юзера. Realtime-подписка в [NotificationsService]
/// обновляет бейдж непрочитанных мгновенно.
class NotificationsInboxScreen extends StatefulWidget {
  const NotificationsInboxScreen({super.key});

  @override
  State<NotificationsInboxScreen> createState() =>
      _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen> {
  List<InboxNotification> _items = const <InboxNotification>[];
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final List<InboxNotification> items =
          await NotificationsService.instance.fetchPage(limit: 100);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      // Сразу же обновим счётчик: возможно, юзер открыл inbox с
      // непрочитанными, но потом markAll/markRead сменит state.
      await NotificationsService.instance.refreshUnreadCount();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _markAllRead() async {
    final int n = await NotificationsService.instance.markAllRead();
    if (!mounted) return;
    if (n > 0) {
      // Перерисовать список с read_at у всех записей.
      setState(() {
        _items = _items
            .map((InboxNotification e) => InboxNotification(
                  id: e.id,
                  eventKind: e.eventKind,
                  title: e.title,
                  body: e.body,
                  data: e.data,
                  createdAt: e.createdAt,
                  readAt: e.readAt ?? DateTime.now(),
                  route: e.route,
                ))
            .toList(growable: false);
      });
      await NotificationsService.instance.refreshUnreadCount();
    }
  }

  Future<void> _onTap(InboxNotification n) async {
    // Помечаем прочитанным сразу же — не ждём результата RPC.
    if (n.isUnread) {
      unawaited(NotificationsService.instance.markRead(n.id));
      setState(() {
        _items = _items
            .map((InboxNotification e) => e.id == n.id
                ? InboxNotification(
                    id: e.id,
                    eventKind: e.eventKind,
                    title: e.title,
                    body: e.body,
                    data: e.data,
                    createdAt: e.createdAt,
                    readAt: DateTime.now(),
                    route: e.route,
                  )
                : e)
            .toList(growable: false);
      });
    }

    final String? route = n.route;
    if (route != null && route.isNotEmpty) {
      if (!mounted) return;
      try {
        context.push(route);
      } catch (_) {
        // Маршрут не валиден — оставляем юзера на inbox, тихо игнорируем.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Уведомления'),
        actions: <Widget>[
          ValueListenableBuilder<int>(
            valueListenable: NotificationsService.instance.unreadCount,
            builder: (BuildContext context, int unread, Widget? _) {
              return TextButton(
                onPressed: unread > 0 ? _markAllRead : null,
                child: const Text('Прочитать все'),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasError) {
      return ListView(
        // ListView нужен, иначе RefreshIndicator не зацепится за пустоту.
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          SizedBox(height: 160.h),
          Center(
            child: Text(
              'Не удалось загрузить уведомления',
              style: AppTextStyles.body,
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          SizedBox(height: 160.h),
          Center(
            child: Text('Здесь будут уведомления', style: AppTextStyles.body),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      itemCount: _items.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 1,
        color: AppColors.divider,
      ),
      itemBuilder: (BuildContext _, int index) {
        final InboxNotification n = _items[index];
        return InkWell(
          onTap: () => _onTap(n),
          child: Container(
            color: n.isUnread
                ? AppColors.primary.withValues(alpha: 0.05)
                : Colors.transparent,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 8.r,
                  height: 8.r,
                  margin: EdgeInsets.only(top: 6.h, right: 10.w),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: n.isUnread
                        ? AppColors.primary
                        : Colors.transparent,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        n.title,
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(n.body, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
                      SizedBox(height: 6.h),
                      Text(
                        _formatRelativeTime(n.createdAt),
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _formatRelativeTime(DateTime t) {
    final Duration diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин назад';
    if (diff.inDays < 1) return '${diff.inHours} ч назад';
    if (diff.inDays < 7) return '${diff.inDays} дн назад';
    final List<String> months = <String>[
      'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ];
    return '${t.day} ${months[t.month - 1]}';
  }
}


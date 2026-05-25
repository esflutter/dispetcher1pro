import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/profile/profile_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Экран настроек пуш-уведомлений.
///
/// Два тумблера:
///  - «Все уведомления» (`push_enabled`) — мастер-выключатель. OFF → ни
///    один пуш не дойдёт до устройства.
///  - «Новые заказы рядом» (`push_new_orders`) — только для исполнителя.
///    OFF → не получаешь спам, когда в твоём радиусе появляется заказ под
///    твои услуги. Не влияет на пуши про твои собственные отклики/заказы.
class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  bool _loading = true;
  bool _pushEnabled = true;
  bool _pushNewOrders = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final MyPrivate? p = await ProfileService.instance.loadMyPrivate();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _pushEnabled = p?.pushEnabled ?? true;
      _pushNewOrders = p?.pushNewOrders ?? true;
    });
  }

  Future<void> _setMaster(bool v) async {
    setState(() => _pushEnabled = v);
    try {
      await ProfileService.instance.updatePushSettings(pushEnabled: v);
    } catch (_) {
      if (!mounted) return;
      // Откат состояния, если запись в БД не прошла.
      setState(() => _pushEnabled = !v);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить настройку')),
      );
    }
  }

  Future<void> _setNewOrders(bool v) async {
    setState(() => _pushNewOrders = v);
    try {
      await ProfileService.instance.updatePushSettings(pushNewOrders: v);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pushNewOrders = !v);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить настройку')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Уведомления')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: <Widget>[
                SizedBox(height: 12.h),
                _RowSwitch(
                  title: 'Все уведомления',
                  subtitle:
                      'Если выключить — приложение перестанет присылать '
                      'любые пуши на это устройство',
                  value: _pushEnabled,
                  onChanged: _setMaster,
                ),
                Divider(height: 1, color: AppColors.divider),
                _RowSwitch(
                  title: 'Новые заказы рядом',
                  subtitle:
                      'Пуши о свежих заказах в вашем радиусе под виды '
                      'спецтехники из ваших услуг',
                  value: _pushNewOrders,
                  // Если общий тумблер выключен — этот тоже неактивен.
                  enabled: _pushEnabled,
                  onChanged: _setNewOrders,
                ),
              ],
            ),
    );
  }
}

class _RowSwitch extends StatelessWidget {
  const _RowSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w500,
                  color: enabled ? null : AppColors.textSecondary,
                )),
                SizedBox(height: 4.h),
                Text(
                  subtitle,
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          Switch(
            value: value && enabled,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

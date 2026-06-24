import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/payments/payment_service.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/subscription_paywall.dart';
import 'package:dispatcher_1/core/widgets/dialog_close_button.dart';
import 'package:dispatcher_1/features/schedule/schedule_screen.dart' show ScheduleToggle;

/// Экран «Подписка и оплата».
///
/// Состояния:
///   • active   — `paid_until > now()` && `auto_renew=true`. Тумблер ON.
///                Если `trial_until > now()` — пишем «Бесплатный период
///                до DD месяца», иначе «Оплачено до DD месяца».
///   • paused   — `paid_until > now()` && `auto_renew=false`. Тумблер OFF,
///                «Подписка приостановлена · Оплачено до DD месяца».
///   • inactive — `paid_until <= now()` (или null). Тумблер OFF, текст
///                без суммы и дат (чтобы не путать юзера сравнением «до».
///                По тапу на тумблер открывается paywall).
class SubscriptionManageScreen extends StatefulWidget {
  const SubscriptionManageScreen({super.key});

  @override
  State<SubscriptionManageScreen> createState() =>
      _SubscriptionManageScreenState();
}

class _SubscriptionManageScreenState extends State<SubscriptionManageScreen> {
  late Future<MyPrivate?> _future;
  bool _busy = false;

  /// Показывать ли кнопку «Способы оплаты»: показываем если у юзера есть
  /// хотя бы одна привязанная карта ИЛИ был хоть один успешный платёж (даже
  /// если карта не сохранилась — например, оплачивал через YooMoney).
  /// Любая ошибка чтения трактуется как «не показывать», чтобы юзер
  /// не упёрся в пустой экран.
  bool _showCardsButton = false;

  @override
  void initState() {
    super.initState();
    _future = ProfileService.instance.loadMyPrivate();
    _loadPaymentMethodsAccess();
  }

  Future<void> _loadPaymentMethodsAccess() async {
    try {
      final List<dynamic> cards =
          await PaymentService.instance.listCards();
      if (!mounted) return;
      if (cards.isNotEmpty) {
        setState(() => _showCardsButton = true);
        return;
      }
      final bool hadPayment =
          await PaymentService.instance.hasAnySucceededPayment();
      if (!mounted) return;
      setState(() => _showCardsButton = hadPayment);
    } catch (_) {
      if (!mounted) return;
      setState(() => _showCardsButton = false);
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = ProfileService.instance.loadMyPrivate();
    });
    _loadPaymentMethodsAccess();
  }

  Future<void> _openCards() async {
    await context.push<void>('/subscription/cards');
    if (mounted) await _loadPaymentMethodsAccess();
  }

  Future<void> _onToggle(BuildContext context, MyPrivate? priv, bool value) async {
    if (_busy) return;
    final _State state = _resolveState(priv);
    if (state == _State.active && !value) {
      // Active → OFF: подтверждаем и выключаем авто-продление. Подписка
      // остаётся валидной до paid_until, но cron-списания не будет.
      final bool? ok = await _showDisableDialog(context);
      if (ok != true) return;
      setState(() => _busy = true);
      try {
        await ProfileService.instance.updateSubscriptionAutoRenew(false);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      _refresh();
      return;
    }
    if (state == _State.paused && value) {
      // Paused → ON: возвращаем авто-продление. Карта всё ещё привязана
      // (paid_until > now()), доплачивать не нужно.
      setState(() => _busy = true);
      try {
        await ProfileService.instance.updateSubscriptionAutoRenew(true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      _refresh();
      return;
    }
    if (state == _State.inactive && value) {
      // Inactive → ON: подписки/карты нет (или истёк paid_until). Везём
      // в paywall (триал-биндинг card_binding с activate_trial=true).
      // После успешной оплаты Webhook поднимет paid_until + auto_renew,
      // вернёмся сюда — refresh подтянет состояние.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SubscriptionPaywall(),
        ),
      );
      _refresh();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Подписка и оплата'),
      body: SafeArea(
        top: false,
        child: FutureBuilder<MyPrivate?>(
          future: _future,
          builder: (BuildContext context, AsyncSnapshot<MyPrivate?> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final MyPrivate? priv = snap.data;
            final _State state = _resolveState(priv);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenH,
                    vertical: 14.h,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text('Подписка', style: AppTextStyles.button),
                      ),
                      Opacity(
                        opacity: _busy ? 0.5 : 1.0,
                        child: IgnorePointer(
                          ignoring: _busy,
                          child: ScheduleToggle(
                            value: state == _State.active,
                            onChanged: (bool v) => _onToggle(context, priv, v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1.h, color: AppColors.divider),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    AppSpacing.md,
                    AppSpacing.screenH,
                    0,
                  ),
                  child: _StatusBlock(state: state, priv: priv),
                ),
                const Spacer(),
                if (_showCardsButton)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.screenH,
                      AppSpacing.sm,
                      AppSpacing.screenH,
                      AppSpacing.md,
                    ),
                    child: PrimaryButton(
                      label: 'Способы оплаты',
                      onPressed: _openCards,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _State { active, paused, inactive }

_State _resolveState(MyPrivate? priv) {
  final bool active = priv?.subscriptionActive ?? false;
  final bool autoRenew = priv?.subscriptionAutoRenew ?? false;
  if (!active) return _State.inactive;
  if (!autoRenew) return _State.paused;
  return _State.active;
}

/// Заголовок + подпись под ним. Без цветной плашки. В подпись зашиваем
/// дату оплаченного периода (где она есть и осмысленна) — чтобы юзер
/// сразу понимал, до когда у него доступ.
class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.state, required this.priv});
  final _State state;
  final MyPrivate? priv;

  @override
  Widget build(BuildContext context) {
    final DateTime? paidUntil = priv?.subscriptionPaidUntil;
    final bool isTrial = priv?.subscriptionInTrial ?? false;

    final String title;
    final String subtitle;
    switch (state) {
      case _State.active:
        title = 'Подписка активна';
        if (isTrial && paidUntil != null) {
          subtitle = 'Бесплатный период до ${_fmt(paidUntil)}';
        } else if (paidUntil != null) {
          subtitle = 'Оплачено до ${_fmt(paidUntil)}';
        } else {
          subtitle = 'Доступ к каталогу открыт';
        }
        break;
      case _State.paused:
        title = 'Подписка приостановлена';
        subtitle = paidUntil == null
            ? 'Авто-продление выключено'
            : 'Оплачено до ${_fmt(paidUntil)}';
        break;
      case _State.inactive:
        title = 'Подписка неактивна';
        subtitle = 'Оплатите подписку, чтобы откликаться на заказы '
            'и заказчики видели ваш профиль';
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: AppTextStyles.h3Medium),
        SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
        ),
      ],
    );
  }

  static const List<String> _months = <String>[
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  String _fmt(DateTime d) {
    final DateTime local = d.toLocal();
    return '${local.day} ${_months[local.month - 1]}';
  }
}

/// Диалог подтверждения отключения авто-продления. По кнопкам и
/// подписям повторяет дизайн из Figma (X в правом верхнем углу,
/// заголовок titleL, тело body/textSecondary, оранжевая primary
/// «Отключить» и текстовая «Отмена»).
Future<bool?> _showDisableDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext ctx) => Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
      ),
      insetPadding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: DialogCloseButton(
                onTap: () => Navigator.of(ctx).pop(false),
                color: AppColors.textSecondary,
                iconSize: 22.r,
              ),
            ),
            Text(
              'Отключить подписку?',
              style: AppTextStyles.titleL,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppSpacing.xs),
            Text(
              'Автопродление отключится, повторных списаний не будет. '
              'Доступ к заказам и показ ваших услуг в каталоге сохранятся '
              'до конца оплаченного периода.',
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Отключить',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Отмена',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

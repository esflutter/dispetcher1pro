import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/payments/payment_service.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/subscription_paywall.dart';
import 'package:dispatcher_1/features/subscription/widgets/brand_badge.dart';

/// Экран «Информация о подписке» — единственная точка управления
/// подпиской: статус, способ оплаты, тумблер авто-продления, кнопки
/// «Возобновить» / «Сменить карту» / «Подключить подписку».
///
/// Состояния:
///   A — Триал активен (paid_until > now() && !trial_used? — нет,
///       trial_used уже выставлен после активации; различаем по тому,
///       что у юзера ещё ни одного успешного списания не было —
///       упрощённо: в state A считаем, если есть payment_method_id и
///       paid_until активен, но субподобия истории платежей нет).
///       Для UI разница только в подписи «Бесплатный пробный период».
///   B — Подписка активна (paid_until > now(), auto_renew=true).
///   C — Активна, но авто-продление отключено (auto_renew=false).
///   D — Истекла (paid_until <= now() или null).
///
/// На простом MVP различие A vs B зависит только от того, успело ли
/// уже произойти cron-списание. Нам это знать дорого (нужно SELECT
/// в payments). Решение: показываем «Бесплатный пробный период», если
/// `paid_until` в пределах первых 30 дней с момента триал-активации,
/// иначе обычное «Подписка активна». Точное отличие — на следующих
/// итерациях, MVP-версия логики достаточна.
class SubscriptionManageScreen extends StatefulWidget {
  const SubscriptionManageScreen({super.key});

  @override
  State<SubscriptionManageScreen> createState() =>
      _SubscriptionManageScreenState();
}

class _SubscriptionManageScreenState extends State<SubscriptionManageScreen> {
  late Future<_ManageData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ManageData> _load() async {
    final MyPrivate? priv = await ProfileService.instance.loadMyPrivate();
    SavedCard? card;
    if (priv?.subscriptionPaymentMethodId != null) {
      try {
        final List<SavedCard> cards =
            await PaymentService.instance.listCards();
        for (final SavedCard c in cards) {
          if (c.id == priv!.subscriptionPaymentMethodId) {
            card = c;
            break;
          }
        }
      } catch (_) {/* silent */}
    }
    return _ManageData(priv: priv, card: card);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Подписка'),
      body: FutureBuilder<_ManageData>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<_ManageData> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return _ErrorView(onRetry: _refresh);
          }
          return _ManageBody(data: snap.data!, onChanged: _refresh);
        },
      ),
    );
  }
}

class _ManageData {
  const _ManageData({required this.priv, required this.card});
  final MyPrivate? priv;
  final SavedCard? card;
}

class _ManageBody extends StatelessWidget {
  const _ManageBody({required this.data, required this.onChanged});
  final _ManageData data;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final MyPrivate? priv = data.priv;
    final DateTime? until = priv?.subscriptionPaidUntil;
    final bool active = priv?.subscriptionActive ?? false;
    final bool autoRenew = priv?.subscriptionAutoRenew ?? false;
    // Триал = `trial_until > now()`. Поле — отдельный таймстемп,
    // ставится при первой активации (apply_payment_success) на 30 дней
    // вперёд. После окончания триала остаётся в прошлом и больше не
    // обновляется — обычные cron-продления работают только с
    // `paid_until`. Подробнее см. `subscription_audit_fixes`.
    final bool isTrial = priv?.subscriptionInTrial ?? false;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Статусная карточка.
          _StatusCard(
            active: active,
            autoRenew: autoRenew,
            until: until,
            isTrial: isTrial,
          ),
          SizedBox(height: 16.h),

          // Способ оплаты — только если есть привязанная карта.
          if (data.card != null) ...<Widget>[
            _PaymentMethodSection(card: data.card!, onChanged: onChanged),
            SizedBox(height: 16.h),
          ],

          // Тумблер авто-продления.
          if (priv != null) ...<Widget>[
            _AutoRenewToggle(
              autoRenew: autoRenew,
              hasCard: priv.subscriptionPaymentMethodId != null,
              paidUntil: until,
              onChanged: onChanged,
            ),
            SizedBox(height: 16.h),
          ],

          // Кнопка действия.
          if (!active) _ActionButton(priv: priv, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.active,
    required this.autoRenew,
    required this.until,
    required this.isTrial,
  });
  final bool active;
  final bool autoRenew;
  final DateTime? until;
  final bool isTrial;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String subtitle;
    final Color bg;
    final Color fg;

    if (active && isTrial && until != null) {
      // Состояние A — триал. Считаем дни от `paid_until` (он же конец
      // триала на этом этапе), а не от now: `paidUntil - today` =
      // целые сутки. inDays округляет вниз; чтобы юзер не видел «0
      // дней» в последние сутки — берём ceil-аналог через прибавление
      // 1 если есть остаток.
      final Duration diff = until!.difference(DateTime.now());
      final int daysLeft = diff.inHours <= 24
          ? 1
          : (diff.inHours / 24).ceil();
      title = 'Бесплатный пробный период';
      subtitle = 'Осталось $daysLeft ${_pluralDays(daysLeft)} · '
          'затем 1 000 ₽/месяц';
      bg = AppColors.primaryTint;
      fg = AppColors.primary;
    } else if (active && autoRenew && until != null) {
      // Состояние B — активна с авто-продлением.
      title = 'Подписка активна';
      subtitle = 'Следующее списание ${_fmt(until!)} · 1 000 ₽';
      bg = AppColors.statusPillSuccessBg;
      fg = AppColors.statusPillSuccessFg;
    } else if (active && !autoRenew && until != null) {
      // Состояние C — активна, но авто-продление отключено.
      title = 'Подписка активна до ${_fmt(until!)}';
      subtitle = 'После — доступ к каталогу пропадёт.\n'
          'Включите авто-продление, чтобы не потерять.';
      bg = AppColors.primaryTint;
      fg = AppColors.primary;
    } else {
      // Состояние D — истекла.
      title = 'Подписка не активна';
      subtitle = 'Вас нет в каталоге исполнителей.';
      bg = AppColors.surfaceVariant;
      fg = AppColors.textSecondary;
    }

    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: AppTextStyles.titleS.copyWith(color: fg),
          ),
          SizedBox(height: 6.h),
          Text(
            subtitle,
            style: AppTextStyles.bodyMRegular.copyWith(color: fg),
          ),
        ],
      ),
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

  String _pluralDays(int n) {
    final int mod10 = n % 10;
    final int mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'дней';
    if (mod10 == 1) return 'день';
    if (mod10 >= 2 && mod10 <= 4) return 'дня';
    return 'дней';
  }
}

class _PaymentMethodSection extends StatelessWidget {
  const _PaymentMethodSection({required this.card, required this.onChanged});
  final SavedCard card;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        children: <Widget>[
          BrandBadge(card: card),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Карта оплаты',
                    style: AppTextStyles.bodyMRegular
                        .copyWith(color: AppColors.textSecondary)),
                SizedBox(height: 2.h),
                Text(
                  '•••• ${card.last4 ?? "----"}',
                  style: AppTextStyles.bodyMRegular,
                ),
                if (card.isExpired) ...<Widget>[
                  SizedBox(height: 2.h),
                  Text(
                    'Срок действия истёк — обновите карту',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 11.sp,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              await context.push('/subscription/cards');
              onChanged();
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              child: Text(
                'Сменить',
                style: AppTextStyles.bodyMRegular
                    .copyWith(color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoRenewToggle extends StatefulWidget {
  const _AutoRenewToggle({
    required this.autoRenew,
    required this.hasCard,
    required this.paidUntil,
    required this.onChanged,
  });
  final bool autoRenew;
  final bool hasCard;
  final DateTime? paidUntil;
  final VoidCallback onChanged;

  @override
  State<_AutoRenewToggle> createState() => _AutoRenewToggleState();
}

class _AutoRenewToggleState extends State<_AutoRenewToggle> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    if (!widget.hasCard) {
      // Без карты включить авто-продление нельзя. Везём через paywall
      // (kind=card_binding с activate_trial=true). Webhook activateTrial
      // сам различит сценарии:
      //   - trial_used=false → даёт триал на 30 дней + auto_renew=true
      //   - trial_used=true  → НЕ даёт триал повторно, но включает
      //     auto_renew + сохраняет subscription_payment_method_id.
      // Тексты paywall'а для уже использовавших триал — отдельная
      // задача на UX. Сейчас одинаковые «30 дней бесплатно»; на БД-
      // уровне второй триал не выдаётся (см. webhook activateTrial).
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SubscriptionPaywall(),
        ),
      );
      widget.onChanged();
      return;
    }
    if (!value) {
      // Выключение — confirm с предупреждением.
      final bool? ok = await _confirmDisable(context, widget.paidUntil);
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await ProfileService.instance.updateSubscription(autoRenew: value);
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Авто-продление подписки',
                    style: AppTextStyles.bodyMRegular),
                SizedBox(height: 2.h),
                Text(
                  widget.hasCard
                      ? '1 000 ₽ списываются раз в месяц'
                      : 'Привяжите карту для авто-продления',
                  style: AppTextStyles.bodyMRegular.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          Switch.adaptive(
            value: widget.autoRenew,
            onChanged: _busy ? null : _toggle,
            activeTrackColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDisable(
      BuildContext context, DateTime? paidUntil) async {
    final String dateText = paidUntil == null
        ? ''
        : '${paidUntil.day}.${paidUntil.month.toString().padLeft(2, '0')}';
    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Отключить авто-продление?'),
        content: Text(
          paidUntil == null
              ? 'Доступ к каталогу пропадёт после истечения подписки.'
              : 'Доступ к каталогу останется до $dateText, '
                  'после — пропадёт. Включить можно будет в любой момент.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.priv, required this.onChanged});
  final MyPrivate? priv;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final bool hasCard = priv?.subscriptionPaymentMethodId != null;
    final String label = hasCard
        ? 'Возобновить подписку (1 000 ₽)'
        : 'Подключить подписку';
    return PrimaryButton(
      label: label,
      onPressed: () async {
        if (hasCard) {
          // Платим 1 000 ₽ сохранённой картой и уходим на экран
          // результата — он сам поллит status, при succeeded возвращает
          // на /subscription/manage с обновлённым состоянием. Раньше
          // здесь делался createPayment без awaiting succeeded и сразу
          // вызывался onChanged() — UI показывал старое состояние,
          // пока webhook не прилетит.
          try {
            final PaymentCreateResult result =
                await PaymentService.instance.createPayment(
              kind: PaymentKind.subscription,
              paymentMethodId: priv!.subscriptionPaymentMethodId,
            );
            if (!context.mounted) return;
            context.go(
              '/subscription/payment/result'
              '?id=${Uri.encodeComponent(result.paymentId)}'
              '&return=${Uri.encodeComponent('/subscription/manage')}',
            );
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Не удалось создать платёж.')),
              );
            }
          }
        } else {
          // Нет карты — гонят через триал-paywall.
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SubscriptionPaywall(),
            ),
          );
          onChanged();
        }
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Не удалось загрузить данные подписки',
              style: AppTextStyles.bodyMRegular),
          SizedBox(height: 16.h),
          PrimaryButton(label: 'Повторить', onPressed: onRetry),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dispatcher_1/core/config/env.dart';
import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/payments/payment_service.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/subscription/widgets/brand_badge.dart';

import 'package:dispatcher_1/core/widgets/dialog_close_button.dart';
/// Экран «Способы оплаты» — список сохранённых карт + удаление + кнопка
/// добавления новой карты.
///
/// Внутри YooKassa-флоу: сами реквизиты карты пользователь вводит только
/// на форме YooKassa (PCI-зона). Сохранение происходит при первом платеже
/// подписки/услуги через `save_card=true`. Поэтому «Добавить карту» здесь
/// — это инициирование обычной оплаты подписки, после успеха которой
/// webhook кладёт карту в `saved_payment_methods`.
class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  List<SavedCard>? _cards;
  bool _loading = true;
  final Set<String> _deleting = <String>{};

  /// Идёт инициирование привязки карты — `createPayment` в полёте.
  /// Блокирует повторный тап, пока не получим confirmation_url.
  bool _binding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<SavedCard> cards =
          await PaymentService.instance.listCards();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cards = const <SavedCard>[];
        _loading = false;
      });
    }
  }

  Future<void> _onDelete(SavedCard c) async {
    // Если это карта, привязанная к подписке (subscription_payment_method_id),
    // дополнительно предупреждаем — после удаления auto_renew выключится
    // (БД-триггер `clear_subscription_card_on_deactivate`), и подписка
    // не продлится. Вычисляем «является ли карта подписочной» через
    // профиль — если это так, показываем дополнительное предупреждение.
    final MyPrivate? priv = await ProfileService.instance.loadMyPrivate();
    final bool isSubCard = priv?.subscriptionPaymentMethodId == c.id;
    if (!mounted) return;
    final bool? ok = await _confirmDelete(c, isSubscriptionCard: isSubCard);
    if (ok != true || !mounted) return;
    setState(() => _deleting.add(c.id));
    try {
      await PaymentService.instance.deleteCard(c.id);
      if (!mounted) return;
      setState(() {
        _cards = (_cards ?? <SavedCard>[])
            .where((SavedCard x) => x.id != c.id)
            .toList(growable: false);
        _deleting.remove(c.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting.remove(c.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить карту')),
      );
    }
  }

  Future<bool?> _confirmDelete(
    SavedCard c, {
    bool isSubscriptionCard = false,
  }) {
    // Стандартный модал приложения: крестик справа, центрированный
    // заголовок, описание под ним, основная оранжевая кнопка действия и
    // текстовая «Вернуться» снизу. Тот же шаблон диалога используется и при
    // отключении подписки — держим визуально единым.
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
                'Удалить карту?',
                style: AppTextStyles.titleL,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                isSubscriptionCard
                    ? 'Эта карта используется для авто-продления подписки. '
                        'После удаления авто-продление отключится — '
                        'подписка не продлится по окончании срока.'
                    : '${c.isYooMoney ? "YooMoney" : _brandLabel(c.brand)} '
                        '•• ${c.displayLast4} больше не будет использоваться '
                        'для оплаты.',
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Удалить',
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
              SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'Вернуться',
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

  /// «Добавить карту» — прямой YooKassa-флоу через kind='card_binding'.
  ///
  /// 1) Создаём в бэкенде платёж 1 ₽ с `save_payment_method=true`.
  /// 2) Открываем confirmation_url в системном браузере и одновременно
  ///    переходим на экран результата (тот же `PaymentResultScreen`,
  ///    но с флагом binding=1) — он будет поллить статус.
  /// 3) После успеха webhook сохраняет карту и тут же запускает
  ///    рефанд той же 1 ₽ — юзер получает карту, ничего по факту
  ///    не платит.
  /// 4) Когда юзер вернётся в приложение и нажмёт «Готово», экран
  ///    результата сам вернёт его на этот экран — мы сразу
  ///    перечитываем список карт.
  Future<void> _onAddCard() async {
    if (_binding) return;
    setState(() => _binding = true);
    try {
      // YooKassa должен вернуть юзера обратно в приложение — но Chrome
      // (Android) НЕ открывает кастомные схемы (`dispatcher1pro://`)
      // через прямой 302-редирект с чужого сайта (yoomoney.ru). Поэтому
      // return_url отправляем на нашу промежуточную страницу (Edge
      // Function `payment-return`), которая отдаёт HTML с JS-переходом на
      // `dispatcher1pro://...` — такой переход Chrome допускает. Тот же
      // приём используется в подписочных платежах (payment_method_card).
      //
      // Флаг `?binding=1` уходит в payment-return: Edge Function допишет
      // `&payment_id=<uuid>`, и когда YooKassa в конце редиректит юзера,
      // мы получим оба параметра и поймём, что это привязка карты, а не
      // обычный платёж. База берётся из Env.supabaseUrl, а не хардкодом.
      final String supabaseBase =
          Env.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
      final String returnDeeplink =
          '$supabaseBase/functions/v1/payment-return?binding=1';
      final PaymentCreateResult result =
          await PaymentService.instance.createPayment(
        kind: PaymentKind.cardBinding,
        saveCard: true,
        returnUrl: returnDeeplink,
      );
      if (!mounted) return;
      // Уезжаем на экран результата (поллит статус) и параллельно
      // открываем форму YooKassa в браузере. Push не await'им
      // напрямую — фьючер `resultClosed` нужен только чтобы перезагрузить
      // список карт после возврата.
      final Future<Object?> resultClosed = context.push<void>(
        '/subscription/payment/result'
        '?id=${Uri.encodeComponent(result.paymentId)}&binding=1',
      );
      if (result.confirmationUrl != null) {
        // ignore: discarded_futures
        launchUrl(
          Uri.parse(result.confirmationUrl!),
          mode: LaunchMode.externalApplication,
        );
      }
      // Когда юзер закрыл экран результата — перечитываем список карт:
      // в случае успеха новая карта уже лежит в saved_payment_methods.
      await resultClosed;
      if (mounted) await _load();
    } on PaymentError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось начать привязку карты. Попробуйте ещё раз.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _binding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Способы оплаты'),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.md,
                  AppSpacing.screenH,
                  AppSpacing.lg,
                ),
                children: <Widget>[
                  if (_cards != null && _cards!.isNotEmpty) ...<Widget>[
                    for (int i = 0; i < _cards!.length; i++) ...<Widget>[
                      _CardTile(
                        card: _cards![i],
                        deleting: _deleting.contains(_cards![i].id),
                        onDelete: () => _onDelete(_cards![i]),
                      ),
                      SizedBox(height: 8.h),
                    ],
                  ] else
                    Padding(
                      padding: EdgeInsets.fromLTRB(4.w, 0, 4.w, 16.h),
                      child: Text(
                        'Сохранённых карт пока нет.',
                        style: AppTextStyles.bodyMRegular
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  _AddCardTile(onTap: _onAddCard),
                ],
              ),
      ),
    );
  }
}

/// Карточка-плитка одной сохранённой карты в списке.
class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.deleting,
    required this.onDelete,
  });

  final SavedCard card;
  final bool deleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56.h,
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      decoration: BoxDecoration(
        // Лёгкая бренд-заливка вместо нейтрально-серого — серая
        // палитра в дизайне приложения вообще не встречается, везде
        // мягкий оранжевый tint.
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: <Widget>[
          BrandBadge(card: card),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  // Отступы: между названием бренда и `••` — 4 пробела
                  // (~2× от расстояния между `••` и цифрами карты, которое
                  // = 2 пробелам). Так название бренда визуально отделяется,
                  // а сама пара «точки + 4 цифры» читается как один блок.
                  card.isYooMoney
                      ? 'YooMoney    ••  ${card.displayLast4}'
                      : '${card.brand ?? "Карта"}    ••  ${card.displayLast4}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: card.isExpired ? AppColors.textSecondary : null,
                  ),
                ),
                if (card.isExpired)
                  Text(
                    'Срок действия истёк',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 11.sp,
                      color: AppColors.error,
                    ),
                  ),
              ],
            ),
          ),
          if (deleting)
            SizedBox(
              width: 22.r,
              height: 22.r,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          else
            SizedBox(
              width: 40.r,
              height: 40.r,
              child: IconButton(
                padding: EdgeInsets.zero,
                splashRadius: 20.r,
                icon: Icon(Icons.delete_outline_rounded,
                    color: AppColors.textTertiary, size: 22.r),
                onPressed: onDelete,
              ),
            ),
        ],
      ),
    );
  }
}

/// «Добавить карту» — строка-действие: оранжевая иконка `add_card`
/// слева, обычный чёрный текст справа. Без подложки — вписывается в
/// общий ритм списка плиток и совпадает по стилю с похожими CTA на
/// других экранах приложения.
class _AddCardTile extends StatelessWidget {
  const _AddCardTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Padding(
        // Левый отступ совпадает с empty-state «Сохранённых карт пока
        // нет.» (4.w) — иконка прижата к левому краю независимо от
        // того, есть ли уже привязанные карты.
        padding: EdgeInsets.fromLTRB(4.w, 12.h, 16.w, 12.h),
        child: Row(
          children: <Widget>[
            Image.asset(
              'assets/images/catalog/card_add.webp',
              width: 24.r,
              height: 24.r,
              fit: BoxFit.contain,
            ),
            SizedBox(width: 12.w),
            Text('Добавить карту', style: AppTextStyles.bodyMedium),
          ],
        ),
      ),
    );
  }
}

String _brandLabel(String? raw) {
  final String s = (raw ?? '').toUpperCase();
  if (s.contains('MIR')) return 'МИР';
  if (s.contains('VISA')) return 'VISA';
  if (s.contains('MAESTRO')) return 'MAES';
  if (s.contains('MASTER')) return 'MC';
  if (s.contains('JCB')) return 'JCB';
  if (s.contains('AMERICAN') || s.contains('AMEX')) return 'AMEX';
  if (s.contains('UNION')) return 'UPI';
  return 'CARD';
}


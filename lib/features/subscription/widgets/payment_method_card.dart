import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dispatcher_1/core/config/env.dart';
import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/payments/payment_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/widgets/dialog_close_button.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/subscription/widgets/brand_badge.dart';

/// Общая платёжная карточка «Способ оплаты», встраивается в:
///   - SubscriptionPaywall  (kind = subscription)
///   - ExecutorCardPaywall  (kind = subscription, с тем же продуктом)
///   - ServicePaywall       (kind = serviceSlot, передаёт serviceId)
///
/// Интеграция YooKassa:
///   - «Новая карта» — `createPayment(saveCard: true)`. Карта
///     сохраняется автоматически после успешной оплаты (по
///     требованию пользователя — без отдельного чекбокса согласия).
///   - Сохранённая карта (по тапу radio) — `createPayment(paymentMethodId)`,
///     повторное списание без редиректа в браузер (если у карты не
///     требуется 3DS).
///
/// Привязка пустой карты за 1 ₽ здесь НЕ делается — это отдельный
/// флоу для экрана «Способы оплаты» в Информации о подписке
/// (см. `add_card_screen.dart`).
class PaymentMethodCard extends StatefulWidget {
  const PaymentMethodCard({
    super.key,
    required this.kind,
    required this.amount,
    this.serviceId,
    this.returnPath,
    this.activateTrial = false,
  });

  /// `subscription`, `serviceSlot` или `cardBinding`. Для cardBinding
  /// карточка показывает только «Новая карта» (сохранённой картой
  /// привязка не имеет смысла), кнопка — «Привязать карту», списание 1 ₽
  /// (рефанд после успеха). С `activateTrial=true` — это активация
  /// триала подписки.
  final PaymentKind kind;

  /// Сумма платежа (₽), показывается в кнопке «Оплатить N ₽».
  /// `null` — пока цена грузится из `settings`, кнопка показывает
  /// просто «Оплатить».
  final int? amount;

  /// id услуги — обязателен для `serviceSlot`. Прокидывается в
  /// Edge Function, попадает в `payments.service_id`. После
  /// успешной оплаты триггер `apply_payment_success` ставит
  /// `services.is_paid = true`.
  final String? serviceId;

  /// Куда вернуть юзера после успешной оплаты — внутренний путь
  /// go_router'а, например `/services`, `/executor-card`. `null`
  /// = `/shell` (главный экран). Прокидывается через query-параметр
  /// `return=...` — он живёт и в URL экрана результата, и в deep-link
  /// возврата из браузера ЮКассы; `PaymentResultScreen._onClose`
  /// использует его в `context.go(...)` после «Готово».
  final String? returnPath;

  /// При `kind = cardBinding && activateTrial = true` после успешной
  /// привязки карты webhook сразу активирует подписочный триал
  /// (paid_until = now()+30d, trial_used=true, auto_renew=true).
  /// Игнорируется для других kind.
  final bool activateTrial;

  @override
  State<PaymentMethodCard> createState() => _PaymentMethodCardState();
}

class _PaymentMethodCardState extends State<PaymentMethodCard> {
  /// `null` означает «Новая карта» (saveCard=true при оплате).
  /// Иначе — id выбранной сохранённой карты.
  String? _selectedPmId;
  List<SavedCard>? _cards;
  bool _loadingCards = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    // Привязка карты (card_binding) — это всегда новая карта; сохранённые
    // карты в этом сценарии бессмысленны (мы добавляем именно ещё одну).
    // Сразу инициализируем пустым списком, чтобы UI не показывал блок
    // «Сохранённые карты» и кнопка «Привязать карту» сразу включалась.
    if (widget.kind == PaymentKind.cardBinding) {
      setState(() {
        _cards = const <SavedCard>[];
        _selectedPmId = null;
        _loadingCards = false;
      });
      return;
    }
    try {
      final List<SavedCard> cards = await PaymentService.instance.listCards();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        // Дефолтный выбор: первая сохранённая карта, если есть; иначе
        // — null, что означает «Новая карта». Это совпадает с тем,
        // что юзер видит как «активный radio» по умолчанию.
        _selectedPmId = cards.isNotEmpty ? cards.first.id : null;
        _loadingCards = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cards = const <SavedCard>[];
        _selectedPmId = null;
        _loadingCards = false;
      });
    }
  }

  Future<void> _onPay() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // returnPath доезжает до PaymentResultScreen двумя путями:
      //   1) Если оплата сохранённой картой прошла без редиректа —
      //      `context.go(...)` ниже сразу прокидывает её в URL экрана.
      //   2) Если был ввод реквизитов / 3DS — юзер ушёл в браузер,
      //      ЮКасса редиректит на `returnDeeplink`. Передаём `return`
      //      и в нём, чтобы deep-link обработчик мог распарсить и
      //      положить тот же returnPath в URL экрана результата.
      final String? rp = widget.returnPath;
      final String returnTail =
          rp == null ? '' : '&return=${Uri.encodeComponent(rp)}';
      // YooKassa должен вернуть юзера обратно в приложение — но Chrome
      // (Android) НЕ открывает кастомные схемы (`dispatcher1pro://`)
      // через прямой 302-редирект с чужого сайта (yoomoney.ru).
      // Поэтому return_url отправляем на нашу промежуточную страницу
      // (Edge Function `payment-return`), которая отдаёт HTML с
      // JS-вызовом `window.location.href = 'dispatcher1pro://...'` —
      // такой переход Chrome допускает. Подробности см. в
      // `supabase/functions/payment-return/index.ts`.
      //
      // База берётся из Env.supabaseUrl, а не хардкодом — при смене
      // домена бэка не нужно искать URL по коду, и инфраструктура не
      // светится строкой в собранном APK.
      final String supabaseBase =
          Env.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
      final String returnBaseUrl =
          '$supabaseBase/functions/v1/payment-return';
      final String returnDeeplink = rp == null
          ? returnBaseUrl
          : '$returnBaseUrl?return=${Uri.encodeComponent(rp)}';
      final PaymentCreateResult result =
          await PaymentService.instance.createPayment(
        kind: widget.kind,
        serviceId: widget.serviceId,
        paymentMethodId: _selectedPmId,
        // Если выбрана «Новая карта» — просим YooKassa сохранить её
        // автоматически. Без отдельного чекбокса согласия (по UX-просьбе
        // пользователя). Сохранённая карта (paymentMethodId != null) —
        // флаг saveCard серверной логикой игнорируется.
        saveCard: _selectedPmId == null,
        returnUrl: returnDeeplink,
        activateTrial: widget.activateTrial,
      );
      if (!mounted) return;
      // Уходим на экран результата (он сам поллит статус). Стек
      // заменяется на /subscription/payment/result, paywall
      // размонтируется. После «Готово» payment_result_screen
      // уведёт на returnPath (или /shell, если не задан).
      context.go(
        '/subscription/payment/result'
        '?id=${Uri.encodeComponent(result.paymentId)}$returnTail',
      );
      if (result.confirmationUrl != null) {
        final bool ok = await launchUrl(
          Uri.parse(result.confirmationUrl!),
          mode: LaunchMode.externalApplication,
        );
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Не удалось открыть форму оплаты. Установите браузер '
                'и попробуйте снова.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } on PaymentError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось создать платёж. Попробуйте ещё раз.'),
        ),
      );
    }
  }

  String _fmtPrice(int v) {
    final String s = v.toString();
    final StringBuffer b = StringBuffer();
    for (int k = 0; k < s.length; k++) {
      if (k > 0 && (s.length - k) % 3 == 0) b.write(' ');
      b.write(s[k]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final List<SavedCard> cards = _cards ?? const <SavedCard>[];
    return Container(
      key: const ValueKey('payment'),
      height: MediaQuery.of(context).size.height * 0.47,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 20.h),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Center(
                    child: Text(
                      'Способ оплаты',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                // Общий компонент с 44×44 тап-зоной — H2 закрывал
                // такие места массово, но этот не был зачтён скрипту
                // массовой замены, потому что иконка `Icons.close`
                // (без `_rounded`).
                DialogCloseButton(
                  onTap: () => Navigator.of(context).pop(),
                  iconData: Icons.close,
                  iconSize: 22.r,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: AppColors.divider),
          Expanded(
            child: _loadingCards
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
                    children: <Widget>[
                      // «Новая карта» — всегда первая в списке. По тапу
                      // снимаем выбор сохранённых карт; реальная привязка
                      // произойдёт при «Оплатить».
                      _NewCardRow(
                        selected: _selectedPmId == null,
                        onTap: () => setState(() => _selectedPmId = null),
                      ),
                      for (final SavedCard c in cards)
                        _CardRow(
                          card: c,
                          selected: _selectedPmId == c.id,
                          onTap: () =>
                              setState(() => _selectedPmId = c.id),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16.w,
              16.h,
              16.w,
              16.h + MediaQuery.of(context).padding.bottom,
            ),
            child: PrimaryButton(
              label: widget.activateTrial
                  ? 'Начать пробный период'
                  : widget.kind == PaymentKind.cardBinding
                      ? 'Привязать карту'
                      : widget.amount == null
                          ? 'Оплатить'
                          : 'Оплатить ${_fmtPrice(widget.amount!)} ₽',
              enabled: !_loadingCards && !_saving,
              onPressed: _onPay,
            ),
          ),
        ],
      ),
    );
  }
}

class _NewCardRow extends StatelessWidget {
  const _NewCardRow({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Row(
          children: <Widget>[
            _Radio(selected: selected),
            SizedBox(width: 12.w),
            Image.asset(
              'assets/images/catalog/card_add.webp',
              width: 28.r,
              height: 28.r,
            ),
            SizedBox(width: 12.w),
            Text(
              'Новая карта',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16.sp,
                fontWeight: FontWeight.w400,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.card,
    required this.selected,
    required this.onTap,
  });
  final SavedCard card;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Текст рядом с бэйджем: бренд (или «YooMoney») и `•••• 1234`. Сам
    // визуальный логотип бренда даёт `BrandBadge` слева — поэтому в
    // тексте бренд можно было бы и не повторять, но «Visa •••• 4804»
    // привычнее читается, чем просто «•••• 4804». Только для YooMoney
    // дублирование выглядит странно — там показываем «•••• 1234»
    // (бренд уже в фиолетовом YOO-бэйдже).
    final String label = card.isYooMoney
        ? '•••• ${card.displayLast4}'
        : '${card.brand ?? 'Карта'} •••• ${card.displayLast4}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Row(
          children: <Widget>[
            _Radio(selected: selected),
            SizedBox(width: 12.w),
            BrandBadge(card: card),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22.r,
      height: 22.r,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.divider,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 12.r,
                height: 12.r,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

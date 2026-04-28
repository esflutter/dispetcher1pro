import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/payments/payment_service.dart';
import 'package:dispatcher_1/core/settings/settings_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Экран «Способ оплаты» — выбор сохранённой карты или новой.
///
/// Открывается из:
///   - `/subscription/payment` (kind=subscription, дефолт)
///   - paywall'а оплаты услуги: `/subscription/payment` с extra
///     `{kind: 'service_slot', serviceId: '<uuid>'}`
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    this.kind = PaymentKind.subscription,
    this.serviceId,
  });

  final PaymentKind kind;
  final String? serviceId;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  /// `null` = «Новая карта». Иначе — id выбранной сохранённой карты.
  String? _selectedPmId;

  List<SavedCard>? _cards;
  bool _loadingCards = true;
  bool _saving = false;
  int? _amount;

  @override
  void initState() {
    super.initState();
    _loadCards();
    _loadAmount();
  }

  Future<void> _loadCards() async {
    try {
      final List<SavedCard> cards = await PaymentService.instance.listCards();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        // По умолчанию выбираем первую сохранённую карту, если есть.
        // Если нет — `_selectedPmId == null` означает «Новая карта».
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

  Future<void> _loadAmount() async {
    try {
      final int amount = widget.kind == PaymentKind.subscription
          ? await SettingsService.instance.subscriptionMonthlyPriceRub()
          : await SettingsService.instance.serviceSlotPriceRub();
      if (!mounted) return;
      setState(() => _amount = amount);
    } catch (_) {/* fallback в build */}
  }

  Future<void> _onPay() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final PaymentCreateResult result =
          await PaymentService.instance.createPayment(
        kind: widget.kind,
        serviceId: widget.serviceId,
        // _selectedPmId == null → «Новая карта». В этом случае всегда
        // просим YooKassa сохранить, чтобы у юзера накапливался список
        // карт для следующих оплат.
        paymentMethodId: _selectedPmId,
        saveCard: _selectedPmId == null,
      );
      if (!mounted) return;
      // Сначала уходим на экран результата (он начинает поллинг сразу),
      // потом открываем confirmation_url. Так юзер, вернувшись из
      // браузера, увидит уже актуальный статус, а не пустой экран.
      context.go(
        '/subscription/payment/result?id=${Uri.encodeComponent(result.paymentId)}',
      );
      if (result.confirmationUrl != null) {
        // Открываем форму YooKassa в системном браузере. Если браузер
        // вернёт false (на эмуляторе без браузера) — пользователю
        // покажется экран ожидания со таймаутом.
        // ignore: discarded_futures
        launchUrl(
          Uri.parse(result.confirmationUrl!),
          mode: LaunchMode.externalApplication,
        );
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
            content: Text('Не удалось создать платёж. Попробуйте ещё раз.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            'assets/images/catalog/subscription_bg.webp',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(color: AppColors.textTertiary),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _PaymentSheet(
              loading: _loadingCards,
              cards: _cards ?? const <SavedCard>[],
              selectedPmId: _selectedPmId,
              amount: _amount,
              saving: _saving,
              onSelect: (String? pmId) =>
                  setState(() => _selectedPmId = pmId),
              onPay: _onPay,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentSheet extends StatelessWidget {
  const _PaymentSheet({
    required this.loading,
    required this.cards,
    required this.selectedPmId,
    required this.amount,
    required this.saving,
    required this.onSelect,
    required this.onPay,
  });

  final bool loading;
  final List<SavedCard> cards;
  final String? selectedPmId;
  final int? amount;
  final bool saving;
  final ValueChanged<String?> onSelect;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.md,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Способ оплаты',
                    style: AppTextStyles.titleL
                        .copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Icon(Icons.close_rounded,
                      size: 22.r, color: AppColors.textSecondary),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.sm),
            Divider(height: 1.h, color: AppColors.divider),
            SizedBox(height: AppSpacing.md),
            if (loading)
              Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: const Center(child: CircularProgressIndicator()),
              )
            else ...<Widget>[
              ...cards.map((SavedCard c) => _CardOption(
                    card: c,
                    selected: selectedPmId == c.id,
                    onTap: () => onSelect(c.id),
                  )),
              _NewCardOption(
                selected: selectedPmId == null,
                onTap: () => onSelect(null),
              ),
            ],
            SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: amount == null
                  ? 'Оплатить'
                  : 'Оплатить ${_fmtPrice(amount!)} ₽',
              enabled: !loading && !saving,
              onPressed: onPay,
            ),
          ],
        ),
      ),
    );
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
}

class _CardOption extends StatelessWidget {
  const _CardOption({
    required this.card,
    required this.selected,
    required this.onTap,
  });

  final SavedCard card;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.primary : AppColors.textTertiary,
              size: 22.r,
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${card.brand ?? 'Карта'} •••• ${card.displayLast4}',
                    style: AppTextStyles.bodyMedium,
                  ),
                  if (card.displayExpiry.isNotEmpty)
                    Text('до ${card.displayExpiry}',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewCardOption extends StatelessWidget {
  const _NewCardOption({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.primary : AppColors.textTertiary,
              size: 22.r,
            ),
            SizedBox(width: AppSpacing.sm),
            Container(
              width: 32.r,
              height: 24.r,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(4.r),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.add_rounded, size: 16.r, color: Colors.white),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Новая карта (с сохранением)',
                style: AppTextStyles.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

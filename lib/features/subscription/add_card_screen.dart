import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/payments/payment_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';

/// Экран «Мои карты» — список сохранённых карт + удаление.
///
/// Раньше тут была форма ввода карточных данных, что нарушало PCI:
/// данные карты должны вводиться только на форме YooKassa. Сохранение
/// карты теперь происходит автоматически при первом платеже подписки/
/// услуги через `save_card=true` в `yookassa-create-payment`.
class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  List<SavedCard>? _cards;
  bool _loading = true;
  final Set<String> _deleting = <String>{};

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
    final bool? ok = await _confirmDelete(c);
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

  Future<bool?> _confirmDelete(SavedCard c) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Удалить карту?'),
        content: Text(
            '${c.brand ?? 'Карта'} •••• ${c.displayLast4} больше не будет использоваться для оплаты.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _onAddCard() {
    // «Добавить карту» = инициировать обычный платёж подписки с
    // `save_card=true`. После успешной оплаты webhook сам положит карту
    // в `saved_payment_methods`, и при следующем заходе она появится
    // в списке. Прямого «zero-amount binding» в нашем бэкенде ещё нет.
    context.push('/subscription/payment');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Мои карты'),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: <Widget>[
                  Expanded(
                    child: _cards == null || _cards!.isEmpty
                        ? _EmptyState(onAddTap: _onAddCard)
                        : ListView.separated(
                            padding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.screenH,
                                vertical: AppSpacing.md),
                            itemCount: _cards!.length,
                            separatorBuilder: (_, _) =>
                                Divider(height: 1.h, color: AppColors.divider),
                            itemBuilder: (BuildContext ctx, int i) {
                              final SavedCard c = _cards![i];
                              return _CardTile(
                                card: c,
                                deleting: _deleting.contains(c.id),
                                onDelete: () => _onDelete(c),
                              );
                            },
                          ),
                  ),
                  if (_cards != null && _cards!.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.screenH,
                        AppSpacing.sm,
                        AppSpacing.screenH,
                        AppSpacing.lg,
                      ),
                      child: TextButton.icon(
                        onPressed: _onAddCard,
                        icon: Icon(Icons.add_rounded,
                            color: AppColors.primary, size: 20.r),
                        label: Text('Добавить карту',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.primary)),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

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
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Icon(Icons.credit_card_rounded,
              color: AppColors.textSecondary, size: 24.r),
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
          if (deleting)
            SizedBox(
              width: 22.r,
              height: 22.r,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  color: AppColors.error, size: 22.r),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddTap});
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.credit_card_off_rounded,
                color: AppColors.textTertiary, size: 64.r),
            SizedBox(height: AppSpacing.md),
            Text('Сохранённых карт нет',
                style: AppTextStyles.h3, textAlign: TextAlign.center),
            SizedBox(height: AppSpacing.sm),
            Text(
              'Карта сохранится автоматически при первой оплате подписки или услуги.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMRegular
                  .copyWith(color: AppColors.textSecondary),
            ),
            SizedBox(height: AppSpacing.xl),
            TextButton.icon(
              onPressed: onAddTap,
              icon: Icon(Icons.add_rounded,
                  color: AppColors.primary, size: 20.r),
              label: Text('Перейти к оплате',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

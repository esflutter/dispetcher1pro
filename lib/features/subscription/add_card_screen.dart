import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/payments/payment_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';

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
            '${_brandLabel(c.brand)} •• ${c.displayLast4} больше не будет использоваться для оплаты.'),
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
                        'Сохранённых карт пока нет. Карта сохранится автоматически при первой оплате подписки или услуги.',
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
        color: AppColors.categoryCard,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: <Widget>[
          _BrandBadge(brand: card.brand),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              '••  ${card.displayLast4}',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          if (deleting)
            SizedBox(
              width: 22.r,
              height: 22.r,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          else
            // Tap-зона 40×40 для удобного попадания, иконка 22 — как в Figma.
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

/// Плашка «Добавить карту» — стилизована под бренд (мягкий оранжевый
/// фон + оранжевый текст и иконка), чтобы выделяться на фоне серых
/// плиток с уже сохранёнными картами.
class _AddCardTile extends StatelessWidget {
  const _AddCardTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryTint,
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          height: 56.h,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.add_rounded, color: AppColors.primary, size: 22.r),
              SizedBox(width: 8.w),
              Text(
                'Добавить карту',
                style: AppTextStyles.button.copyWith(color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Цветной шильдик с надписью бренда — заменяет логотипы платёжных
/// систем, которых нет в ассетах. Цвета взяты из официальных гайдлайнов
/// (МИР, Visa, MasterCard, Maestro), чтобы юзер мгновенно узнавал
/// «свою» карту в списке.
class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.brand});

  final String? brand;

  @override
  Widget build(BuildContext context) {
    final String label = _brandLabel(brand);
    final Color color = _brandColor(brand);
    return Container(
      width: 40.w,
      height: 28.h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 10.sp,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.4,
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

Color _brandColor(String? raw) {
  final String s = (raw ?? '').toUpperCase();
  if (s.contains('MIR')) return const Color(0xFF0F754E); // МИР — зелёный
  if (s.contains('VISA')) return const Color(0xFF1434CB);
  if (s.contains('MAESTRO')) return const Color(0xFF0099DF);
  if (s.contains('MASTER')) return const Color(0xFFEB001B);
  if (s.contains('JCB')) return const Color(0xFF0E4C96);
  if (s.contains('AMERICAN') || s.contains('AMEX')) {
    return const Color(0xFF006FCF);
  }
  if (s.contains('UNION')) return const Color(0xFFE21836);
  return AppColors.textTertiary;
}

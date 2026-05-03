import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/payments/payment_service.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/router.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';

/// Экран результата оплаты — поллит наш бэкенд по `paymentId`, пока
/// статус не станет терминальным (succeeded/canceled) или не истечёт
/// 90-секундный таймаут. На время поллинга показывается спиннер.
class PaymentResultScreen extends StatefulWidget {
  const PaymentResultScreen({
    super.key,
    required this.paymentId,
    this.binding = false,
    this.returnPath,
  });

  final String paymentId;

  /// `true` — экран открыт после привязки карты (kind='card_binding').
  /// Тексты статуса в этом случае другие («Карта привязана» вместо
  /// «Оплата прошла»), а кнопка «Готpo» возвращает на один уровень
  /// назад (в список карт), а не до корня — иначе юзер вылетал бы
  /// в профиль/главную после привязки.
  final bool binding;

  /// Куда уводить юзера после нажатия «Готово»/«Закрыть» при успешной
  /// оплате (без `binding`). Передаётся paywall'ом через query-параметр
  /// `return=...`. По смыслу — «вернись туда, откуда я тебя пустил
  /// в оплату»: для оплаты услуги это `/services`, для оплаты карточки
  /// исполнителя — `/executor-card`, для общей подписки — `/shell`.
  /// `null` = `/shell` (поведение по умолчанию для неопознанных оплат
  /// и cold-start deep-link'ов без параметра).
  final String? returnPath;

  @override
  State<PaymentResultScreen> createState() => _PaymentResultScreenState();
}

class _PaymentResultScreenState extends State<PaymentResultScreen> {
  PaymentStatus _status = PaymentStatus.pending;
  bool _polling = true;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _startPolling() async {
    // Прямой заход на /subscription/payment/result без id (битый
    // deep-link / ручная навигация) — 90 секунд поллить нечего.
    if (widget.paymentId.isEmpty) {
      setState(() {
        _status = PaymentStatus.unknown;
        _polling = false;
      });
      return;
    }
    // Short-circuit для двух кейсов:
    //   1) hot restart Android Studio: Activity-intent остаётся со
    //      старым deep-link'ом, мы повторно открываем result-экран
    //      по уже завершённому платежу — спиннер «Платёж в обработке»
    //      бесполезен;
    //   2) юзер закрыл браузер не платив, открыл приложение позже —
    //      его не должно встречать «обработкой» того, что он не делал.
    // Если status уже терминальный (succeeded/refunded), сразу
    // уводим в финальное место без рендера спиннера.
    final PaymentStatus first =
        await PaymentService.instance.getPaymentStatus(widget.paymentId);
    if (!mounted) return;
    if (first == PaymentStatus.succeeded ||
        first == PaymentStatus.refunded) {
      _onClose();
      return;
    }
    if (first == PaymentStatus.failed) {
      setState(() {
        _status = first;
        _polling = false;
      });
      return;
    }
    final PaymentStatus s = await PaymentService.instance.pollPaymentStatus(
      widget.paymentId,
      isCancelled: () => _disposed,
    );
    if (!mounted) return;
    setState(() {
      _status = s;
      _polling = false;
    });
    if (s == PaymentStatus.succeeded || s == PaymentStatus.refunded) {
      // Для привязки карты состояние подписки не меняется — пропуск.
      // Для подписочного/услугового платежа — подтягиваем paid_until,
      // его уже продлил триггер apply_payment_success.
      if (!widget.binding) {
        // ignore: discarded_futures
        _refreshSubscriptionState();
      }
    }
  }

  Future<void> _refreshSubscriptionState() async {
    try {
      final MyPrivate? priv = await ProfileService.instance.loadMyPrivate();
      final DateTime? until = priv?.subscriptionPaidUntil;
      if (until != null) {
        VerificationStatus.hasSubscription = true;
        VerificationStatus.subscriptionPaidUntilText = _fmtDateRu(until);
      }
    } catch (_) {/* silent */}
  }

  static const List<String> _monthsRu = <String>[
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  String _fmtDateRu(DateTime d) {
    final DateTime local = d.toLocal();
    return '${local.day} ${_monthsRu[local.month - 1]}';
  }

  /// Возврат с экрана результата.
  ///
  /// Используем `appRouter` вместо `Navigator.pop()` — экран мог быть
  /// открыт двумя способами:
  ///   1. `context.push(...)` из add_card_screen / paywall — стек есть,
  ///      pop сработал бы.
  ///   2. `appRouter.go(...)` из deep-link фолбэка после возврата
  ///      из браузера YooKassa — стек заменён на единственную страницу
  ///      `payment/result`, и обычный pop становится no-op.
  ///
  /// Просто `go('/subscription/cards')` тут не годится: оно опять
  /// схлопывает стек до одной страницы, и тогда:
  ///   - in-app back на cards-экране ничего не делает
  ///     (Navigator.maybePop() возвращает false);
  ///   - system back (аппаратная кнопка телефона) уходит в предыдущий
  ///     OS-таск — то есть в браузер, из которого пришёл deep-link.
  /// Поэтому для привязки карты явно собираем синтетический backstack
  /// /shell → /subscription → /subscription/cards: первый `go` ставит
  /// /shell как корень, два `push` дополняют его. У AppBar back и
  /// system back появляется куда возвращаться.
  void _onClose() {
    if (widget.binding) {
      appRouter.go('/shell');
      appRouter.push('/subscription');
      appRouter.push('/subscription/cards');
    } else {
      // ServicePaywall и подобные открываются через
      // `Navigator.of(context).push(MaterialPageRoute(...))` поверх
      // GoRouter-страницы. После `appRouter.go('/services')` go_router
      // меняет верхнюю страницу, но MaterialPageRoute из root Navigator
      // не выпадает — остаётся невидимый «слой», и back-кнопка на
      // /services сначала закрывает его (выглядит как «не работает»).
      // Чистим root Navigator до go_router'а.
      final NavigatorState root =
          Navigator.of(context, rootNavigator: true);
      while (root.canPop()) {
        root.pop();
      }
      // Строим синтетический стек go_router: /profile → returnPath. Так
      // back-кнопка на «Мои услуги» / «Карточка исполнителя» вернёт
      // юзера на вкладку «Профиль» главного шелла (а не куда-то в
      // зависимости от того, откуда он зашёл в paywall). Для общей
      // подписки или других кейсов без returnPath — просто /shell.
      final String? rp = widget.returnPath;
      if (rp == null || rp.isEmpty || rp == '/shell' || rp == '/profile') {
        appRouter.go(rp ?? '/shell');
      } else {
        appRouter.go('/profile');
        appRouter.push(rp);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: _onClose,
                  behavior: HitTestBehavior.opaque,
                  // Без IconButton-обёртки: у IconButton дефолтный
                  // 48×48 tap-таргет, и иконка визуально оказывалась
                  // ~12px правее левого края контента — выглядело
                  // несогласованно с другими элементами страницы.
                  // GestureDetector + Padding даёт ровно тот же
                  // hit-area, но с иконкой строго по левому краю.
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    child: Icon(
                      Icons.close_rounded,
                      color: AppColors.textPrimary,
                      size: 24.r,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              _buildBody(),
              const Spacer(),
              _buildButton(),
              SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_polling) {
      return Column(
        children: <Widget>[
          Container(
            width: 120.r,
            height: 120.r,
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: SizedBox(
              width: 48.r,
              height: 48.r,
              child: const CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
          SizedBox(height: AppSpacing.xl),
          Text('Ждём подтверждение оплаты',
              style: AppTextStyles.h3, textAlign: TextAlign.center),
          SizedBox(height: AppSpacing.sm),
          Text(
            'Если вы только что оплатили в браузере — статус обновится через несколько секунд.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMRegular
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      );
    }

    // Для привязки карты «succeeded» от YooKassa — это уже факт того,
    // что карта сохранена и инициирован рефанд. Webhook позже переведёт
    // запись в `refunded`, поллинг может зацепить как `succeeded`, так
    // и `refunded` — оба считаются успешным результатом.
    final bool ok = _status == PaymentStatus.succeeded ||
        (widget.binding && _status == PaymentStatus.refunded);
    final bool failed = _status == PaymentStatus.failed;
    final bool unknown = _status == PaymentStatus.unknown;
    final IconData icon = ok
        ? Icons.check_circle_rounded
        : (failed || unknown)
            ? Icons.cancel_rounded
            : Icons.access_time_rounded;
    final Color iconColor = ok
        ? AppColors.success
        : (failed || unknown)
            ? AppColors.error
            : AppColors.textSecondary;
    final String title = ok
        ? (widget.binding ? 'Карта привязана' : 'Оплата прошла')
        : failed
            ? (widget.binding ? 'Привязка не удалась' : 'Платёж не прошёл')
            : unknown
                ? 'Платёж не найден'
                : (widget.binding
                    ? 'Привязка в обработке'
                    : 'Платёж в обработке');
    final String subtitle = ok
        ? (widget.binding
            ? 'Списали 1 ₽ и сразу вернули. Карта сохранена и доступна '
                'для оплат подписки и услуг.'
            : 'Подписка активирована. Заказы доступны.')
        : failed
            ? (widget.binding
                ? 'Списание не прошло. Можно попробовать ещё раз.'
                : 'Списание не прошло. Можно попробовать ещё раз.')
            : unknown
                ? (widget.binding
                    ? 'Не удалось получить данные. Проверьте список карт чуть позже.'
                    : 'Не удалось получить данные о платеже. Проверьте статус подписки в профиле.')
                : (widget.binding
                    ? 'Статус ещё не пришёл от банка. Карта появится в списке через минуту.'
                    : 'Статус ещё не пришёл от банка. Загляните в подписку через минуту.');

    return Column(
      children: <Widget>[
        Container(
          width: 120.r,
          height: 120.r,
          decoration: BoxDecoration(
            color: ok ? AppColors.primaryTint : AppColors.surfaceVariant,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 64.r),
        ),
        SizedBox(height: AppSpacing.xl),
        Text(title, style: AppTextStyles.h3, textAlign: TextAlign.center),
        SizedBox(height: AppSpacing.sm),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMRegular
              .copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildButton() {
    if (_polling) return const SizedBox.shrink();
    final bool ok = _status == PaymentStatus.succeeded ||
        (widget.binding && _status == PaymentStatus.refunded);
    final String label = ok ? 'Готово' : 'Закрыть';
    return PrimaryButton(label: label, onPressed: _onClose);
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dispatcher_1/core/analytics/app_analytics.dart';
import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/payments/payment_service.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/router.dart';
import 'package:dispatcher_1/core/schedule/schedule_prompt_prefs.dart';
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
    this.confirmationUrl,
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

  /// URL формы подтверждения оплаты ЮKassa (3DS / кошелёк). Если задан — во
  /// время ожидания показываем кнопку «Открыть форму оплаты», чтобы вернуть
  /// пользователя к подтверждению (браузер не открылся / закрыт не заплатив).
  /// Приходит только при оплате; из deep-link возврата не передаётся (там
  /// оплата уже подтверждена).
  final String? confirmationUrl;

  @override
  State<PaymentResultScreen> createState() => _PaymentResultScreenState();
}

class _PaymentResultScreenState extends State<PaymentResultScreen> {
  PaymentStatus _status = PaymentStatus.pending;
  bool _polling = true;

  /// Поллинг идёт дольше 90 секунд (вебхук задержался): меняем подпись
  /// с «через несколько секунд» на честную — можно закрыть экран,
  /// активация придёт автоматически.
  bool _slow = false;
  Timer? _slowTimer;
  bool _disposed = false;
  // Поднимаем при каждом ручном перезапуске поллинга, чтобы старая
  // background-итерация поняла, что её результат уже неактуален и
  // не перезаписывала бы _status.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _disposed = true;
    super.dispose();
  }

  /// Авто-поллинг статуса до терминального состояния. Запускается из
  /// initState один раз. У юзера нет ручных кнопок «Проверить» —
  /// экран сам подхватит webhook (адаптивный шаг см. в
  /// `PaymentService.pollPaymentStatus`).
  Future<void> _startPolling() async {
    final int myAttempt = ++_attempt;
    _slowTimer?.cancel();
    _slow = false;
    _slowTimer = Timer(const Duration(seconds: 90), () {
      if (mounted && _polling) setState(() => _slow = true);
    });
    // Прямой заход на /subscription/payment/result без id (битый
    // deep-link / ручная навигация) — поллить нечего.
    if (widget.paymentId.isEmpty) {
      if (!mounted || myAttempt != _attempt) return;
      setState(() {
        _status = PaymentStatus.unknown;
        _polling = false;
      });
      return;
    }
    // Short-circuit, если статус уже терминальный — без рендера спиннера.
    final PaymentStatus first =
        await PaymentService.instance.getPaymentStatus(widget.paymentId);
    if (!mounted || myAttempt != _attempt) return;
    if (first == PaymentStatus.succeeded ||
        first == PaymentStatus.refunded) {
      // Платёж уже подтверждён — гасим режим ожидания, чтобы убрать кнопку
      // «Открыть форму оплаты» (открывать уже нечего) ещё до авто-закрытия.
      if (mounted && myAttempt == _attempt) {
        setState(() {
          _status = first;
          _polling = false;
        });
      }
      AppAnalytics.log('payment_success', <String, Object>{
        'kind': widget.binding ? 'card_binding' : 'payment',
      });
      // Привязка карты = активация триала: поднимаем сигнал для разового
      // попапа «Заполните график работы» — его покажет корневой экран или
      // карточка исполнителя после первого кадра.
      if (widget.binding) SchedulePromptPrefs.pending = true;
      // Обновляем подписку и в быстром пути, и для привязки карты/триала
      // (binding): триал нового исполнителя идёт через привязку карты, и без
      // этого гейты в каталоге/карточке сразу после оплаты снова показывают
      // paywall, пока юзер не зайдёт в Профиль. Ждём перед закрытием.
      await _refreshSubscriptionState();
      if (!mounted || myAttempt != _attempt) return;
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
      isCancelled: () => _disposed || myAttempt != _attempt,
    );
    if (!mounted || myAttempt != _attempt) return;
    setState(() {
      _status = s;
      _polling = false;
    });
    if (s == PaymentStatus.succeeded || s == PaymentStatus.refunded) {
      AppAnalytics.log('payment_success', <String, Object>{
        'kind': widget.binding ? 'card_binding' : 'payment',
      });
      // Триал активирован через привязку карты — сигнал для разового
      // попапа «Заполните график работы» (см. быстрый путь выше).
      if (widget.binding) SchedulePromptPrefs.pending = true;
      // Обновляем и для binding — триал нового исполнителя идёт через
      // привязку карты, иначе гейты сразу после оплаты снова покажут paywall.
      // ignore: discarded_futures
      _refreshSubscriptionState();
    }
  }

  Future<void> _refreshSubscriptionState() async {
    try {
      final MyPrivate? priv = await ProfileService.instance.loadMyPrivate();
      final DateTime? until = priv?.subscriptionPaidUntil;
      if (priv != null && until != null) {
        // grace-aware (subscriptionActive): единый источник с гейтами.
        VerificationStatus.hasSubscription = priv.subscriptionActive;
        VerificationStatus.subscriptionPaidUntilText = _fmtDateRu(until);
        VerificationStatus.subscriptionPaidUntil = until;
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
  /// Защита от двойного закрытия: авто-закрытие (после await обновления
  /// подписки в быстром пути успеха) и ручной тап по крестику могут совпасть
  /// в узком окне — без флага навигация отрабатывала бы дважды и верхняя
  /// страница дублировалась («назад» срабатывал со второго раза).
  bool _closed = false;

  /// /shell → /subscription → /subscription/cards: первый `go` ставит
  /// /shell как корень, два `push` дополняют его. У AppBar back и
  /// system back появляется куда возвращаться.
  void _onClose() {
    if (_closed) return;
    _closed = true;

    // Whitelist обязателен: returnPath приходит из deep-link
    // `dispatcher1pro://payment/result?return=...`. Без проверки
    // злоумышленник мог бы оформить ссылку с return=/admin/... (когда такой
    // роут появится) — и мы открыли бы его сами после успешного callback'а
    // от YooKassa.
    const Set<String> allowedReturnPaths = <String>{
      '/shell',
      '/profile',
      '/services',
      '/executor-card',
      '/subscription/manage',
      '/subscription/cards',
    };
    final String? rp = widget.returnPath;
    final String? safeRp =
        (rp != null && allowedReturnPaths.contains(rp)) ? rp : null;

    // Уводит по returnPath, если он задан; возвращает false, если returnPath
    // нет (тогда вызывающий применяет дефолт). Для не-корневых путей строим
    // синтетический стек /profile → returnPath, чтобы back с «Моих услуг» /
    // «Карточки исполнителя» вёл на вкладку «Профиль» главного шелла.
    bool goByReturnPath() {
      if (safeRp == null) return false;
      if (safeRp == '/shell' || safeRp == '/profile') {
        appRouter.go(safeRp);
      } else {
        appRouter.go('/profile');
        appRouter.push(safeRp);
      }
      return true;
    }

    if (widget.binding) {
      // Привязка карты приходит сюда в ДВУХ сценариях:
      //  - «Добавить карту» из «Способов оплаты» (returnPath нет) — оставляем
      //    стек /shell → управление → карты, чтобы back вёл к списку карт;
      //  - активация пробного периода из каталога/услуги/карточки (returnPath
      //    задан) — уводим туда, ради чего юзер активировал триал, а не в
      //    «Способы оплаты». Пейволл открыт через MaterialPageRoute, поэтому
      //    чистим root Navigator (как в ветке ниже), иначе под go_router
      //    остаётся невидимый слой и back срабатывает не сразу.
      if (safeRp != null) {
        final NavigatorState root =
            Navigator.of(context, rootNavigator: true);
        while (root.canPop()) {
          root.pop();
        }
        goByReturnPath();
      } else {
        appRouter.go('/shell');
        appRouter.push('/subscription/manage');
        appRouter.push('/subscription/cards');
      }
    } else {
      // ServicePaywall и подобные открываются через
      // `Navigator.of(context).push(MaterialPageRoute(...))` поверх
      // GoRouter-страницы. После `appRouter.go(...)` go_router меняет верхнюю
      // страницу, но MaterialPageRoute из root Navigator не выпадает —
      // остаётся невидимый «слой», и back-кнопка сперва закрывает его.
      // Чистим root Navigator до go_router'а.
      final NavigatorState root =
          Navigator.of(context, rootNavigator: true);
      while (root.canPop()) {
        root.pop();
      }
      if (!goByReturnPath()) {
        appRouter.go('/shell');
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
            _slow
                ? 'Платёж обрабатывается дольше обычного. Можно закрыть экран — всё активируется автоматически, как только банк подтвердит оплату.'
                : widget.confirmationUrl != null
                    ? 'Завершите оплату в открывшемся браузере и вернитесь — статус обновится автоматически. Если браузер не открылся, нажмите кнопку ниже.'
                    : 'Если вы только что оплатили в браузере — статус обновится через несколько секунд.',
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
    // Большая «голая» иконка в брендовом цвете (без бэкграундового
    // кружка) — единый паттерн для всех терминальных состояний.
    //   - succeeded → оранжевая галочка;
    //   - failed/unknown → красный круг с «X»;
    //   - pending (после внешней отмены поллинга) → серые часы.
    final IconData icon = ok
        ? Icons.check_circle_rounded
        : (failed || unknown)
            ? Icons.cancel_rounded
            : Icons.access_time_rounded;
    final Color iconColor = ok
        ? AppColors.primary
        : (failed || unknown)
            ? AppColors.error
            : AppColors.textTertiary;
    final String title = ok
        ? (widget.binding ? 'Карта привязана' : 'Оплата прошла успешно')
        : failed
            ? (widget.binding ? 'Привязка не удалась' : 'Платёж не прошёл')
            : unknown
                ? 'Платёж не найден'
                : (widget.binding
                    ? 'Привязка в обработке'
                    : 'Платёж в обработке');
    // Для не-binding-успеха не показываем подпись вовсе — заголовка
    // «Оплата прошла успешно» юзеру достаточно. Раньше тут был
    // дублирующий «Платёж успешно прошёл», который ничего не добавлял.
    final String? subtitle = ok
        ? (widget.binding
            ? 'Списали 1 ₽ и сразу вернули. Карта сохранена и доступна '
                'для оплат подписки и услуг.'
            : null)
        : failed
            ? 'Списание не прошло. Можно попробовать ещё раз.'
            : unknown
                ? (widget.binding
                    ? 'Не удалось получить данные. Проверьте список карт чуть позже.'
                    : 'Не удалось получить данные о платеже. Проверьте статус в профиле.')
                : (widget.binding
                    ? 'Статус ещё не пришёл от банка. Карта появится в списке через минуту.'
                    : 'Статус ещё не пришёл от банка. Загляните в профиль через минуту.');

    return Column(
      children: <Widget>[
        Icon(icon, color: iconColor, size: 120.r),
        SizedBox(height: AppSpacing.xl),
        Text(title, style: AppTextStyles.h3, textAlign: TextAlign.center),
        if (subtitle != null) ...<Widget>[
          SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMRegular
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  /// Повторно открыть форму подтверждения оплаты (если браузер не открылся
  /// или пользователь закрыл его не заплатив). Платёж тот же — confirmation_url
  /// ЮKassa остаётся валидным до завершения/отмены.
  Future<void> _reopenPaymentForm() async {
    if (_closed) return;
    final String? url = widget.confirmationUrl;
    if (url == null) return;
    final Uri? uri = Uri.tryParse(url);
    // conf приходит из query маршрута — открываем только https-ссылки доменов
    // ЮKassa/ЮMoney, чтобы подменённый сторонний deep-link не увёл на внешний
    // сайт (по аналогии с белым списком для returnPath).
    if (uri == null ||
        uri.scheme != 'https' ||
        !(uri.host == 'yoomoney.ru' ||
            uri.host.endsWith('.yoomoney.ru') ||
            uri.host == 'yookassa.ru' ||
            uri.host.endsWith('.yookassa.ru'))) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* кнопка остаётся — можно повторить */}
  }

  Widget _buildButton() {
    if (_polling) {
      // Если оплата требует подтверждения в браузере — во время ожидания
      // даём кнопку открыть форму ещё раз (вдруг браузер не открылся или
      // закрыт не заплатив). Иначе кнопки нет: X слева закрывает, поллинг
      // прервётся через isCancelled при unmount.
      if (widget.confirmationUrl != null) {
        return PrimaryButton(
          label: 'Открыть форму оплаты',
          onPressed: _reopenPaymentForm,
        );
      }
      return const SizedBox.shrink();
    }
    final bool ok = _status == PaymentStatus.succeeded ||
        (widget.binding && _status == PaymentStatus.refunded);
    final String label = ok ? 'Готово' : 'Закрыть';
    return PrimaryButton(label: label, onPressed: _onClose);
  }
}

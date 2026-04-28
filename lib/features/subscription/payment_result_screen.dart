import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/payments/payment_service.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';

/// Экран результата оплаты — поллит наш бэкенд по `paymentId`, пока
/// статус не станет терминальным (succeeded/canceled) или не истечёт
/// 90-секундный таймаут. На время поллинга показывается спиннер.
class PaymentResultScreen extends StatefulWidget {
  const PaymentResultScreen({super.key, required this.paymentId});

  final String paymentId;

  @override
  State<PaymentResultScreen> createState() => _PaymentResultScreenState();
}

class _PaymentResultScreenState extends State<PaymentResultScreen> {
  PaymentStatus _status = PaymentStatus.pending;
  bool _polling = true;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  Future<void> _startPolling() async {
    final PaymentStatus s = await PaymentService.instance.pollPaymentStatus(
      widget.paymentId,
    );
    if (!mounted) return;
    setState(() {
      _status = s;
      _polling = false;
    });
    if (s == PaymentStatus.succeeded || s == PaymentStatus.refunded) {
      // Только succeeded triggers UI обновления (refunded в текущей
      // логике на UI не приходит, но на всякий — обновим состояние).
      // После успешной оплаты подтягиваем актуальное состояние
      // подписки из БД — paid_until уже продлён триггером.
      // ignore: discarded_futures
      _refreshSubscriptionState();
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
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textPrimary),
                  onPressed: () => Navigator.of(context)
                      .popUntil((Route<dynamic> r) => r.isFirst),
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

    final bool ok = _status == PaymentStatus.succeeded;
    final bool failed = _status == PaymentStatus.failed;
    final IconData icon = ok
        ? Icons.check_circle_rounded
        : failed
            ? Icons.cancel_rounded
            : Icons.access_time_rounded;
    final Color iconColor = ok
        ? AppColors.success
        : failed
            ? AppColors.error
            : AppColors.textSecondary;
    final String title = ok
        ? 'Оплата прошла'
        : failed
            ? 'Платёж не прошёл'
            : 'Платёж в обработке';
    final String subtitle = ok
        ? 'Подписка активирована. Заказы доступны.'
        : failed
            ? 'Списание не прошло. Можно попробовать ещё раз.'
            : 'Статус ещё не пришёл от банка. Загляните в подписку через минуту.';

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
    final bool ok = _status == PaymentStatus.succeeded;
    final String label = ok ? 'Готово' : 'Закрыть';
    return PrimaryButton(
      label: label,
      onPressed: () => Navigator.of(context)
          .popUntil((Route<dynamic> r) => r.isFirst),
    );
  }
}

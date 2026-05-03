import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/payments/models.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';

/// Брендовый шильдик-логотип карты (Visa/Mastercard/МИР/YooMoney/...).
/// Используется в:
///   - `add_card_screen.dart` — список «Способы оплаты».
///   - `payment_method_card.dart` — шторка выбора способа оплаты в
///     paywall'ах подписки / карточки исполнителя / слота услуги.
///
/// Размер фиксированный — 40×28. Большинство брендов рисуем как
/// цветную плашку с короткой 3-4-буквенной аббревиатурой; Mastercard
/// и Maestro — двумя пересекающимися кругами в фирменных цветах.
class BrandBadge extends StatelessWidget {
  const BrandBadge({super.key, required this.card});

  final SavedCard card;

  @override
  Widget build(BuildContext context) {
    final double w = 40.w;
    final double h = 28.h;
    if (card.isYooMoney) {
      return _TextBadge(
        width: w,
        height: h,
        label: 'YOO',
        bg: const Color(0xFF8B3FFC),
        fg: Colors.white,
      );
    }
    final String b = (card.brand ?? '').toUpperCase();
    if (b.contains('MASTER')) {
      return _MastercardLogo(width: w, height: h);
    }
    if (b.contains('MAESTRO')) {
      return _MaestroLogo(width: w, height: h);
    }
    if (b.contains('VISA')) {
      return _TextBadge(
        width: w,
        height: h,
        label: 'VISA',
        bg: const Color(0xFF1A1F71),
        fg: Colors.white,
        italic: true,
        letterSpacing: 0.5,
      );
    }
    if (b.contains('MIR')) {
      return _TextBadge(
        width: w,
        height: h,
        label: 'МИР',
        bg: const Color(0xFF0F754E),
        fg: Colors.white,
      );
    }
    if (b.contains('JCB')) {
      return _TextBadge(
        width: w,
        height: h,
        label: 'JCB',
        bg: const Color(0xFF0E4C96),
        fg: Colors.white,
      );
    }
    if (b.contains('AMERICAN') || b.contains('AMEX')) {
      return _TextBadge(
        width: w,
        height: h,
        label: 'AMEX',
        bg: const Color(0xFF006FCF),
        fg: Colors.white,
      );
    }
    if (b.contains('UNION') || b.contains('UPI')) {
      return _TextBadge(
        width: w,
        height: h,
        label: 'UPay',
        bg: const Color(0xFFE21836),
        fg: Colors.white,
        letterSpacing: 0,
      );
    }
    if (b.contains('DISCOVER')) {
      return _TextBadge(
        width: w,
        height: h,
        label: 'DISC',
        bg: const Color(0xFFFF6000),
        fg: Colors.white,
      );
    }
    if (b.contains('DINERS')) {
      return _TextBadge(
        width: w,
        height: h,
        label: 'DC',
        bg: const Color(0xFF0079BE),
        fg: Colors.white,
      );
    }
    if (b.contains('TROY')) {
      return _TextBadge(
        width: w,
        height: h,
        label: 'TROY',
        bg: const Color(0xFFF1A220),
        fg: Colors.white,
      );
    }
    if (b.contains('ELO')) {
      return _TextBadge(
        width: w,
        height: h,
        label: 'ELO',
        bg: const Color(0xFF000000),
        fg: Colors.white,
      );
    }
    if (b.contains('HIPER')) {
      return _TextBadge(
        width: w,
        height: h,
        label: 'HIPR',
        bg: const Color(0xFFD0021B),
        fg: Colors.white,
      );
    }
    if (b.contains('RUPAY')) {
      return _TextBadge(
        width: w,
        height: h,
        label: 'RPay',
        bg: const Color(0xFF097B6F),
        fg: Colors.white,
        letterSpacing: 0,
      );
    }
    return _TextBadge(
      width: w,
      height: h,
      label: 'CARD',
      bg: AppColors.textTertiary,
      fg: Colors.white,
    );
  }
}

class _TextBadge extends StatelessWidget {
  const _TextBadge({
    required this.width,
    required this.height,
    required this.label,
    required this.bg,
    required this.fg,
    this.italic = false,
    this.letterSpacing = 0.4,
  });

  final double width;
  final double height;
  final String label;
  final Color bg;
  final Color fg;
  final bool italic;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 11.sp,
          fontWeight: FontWeight.w900,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          color: fg,
          letterSpacing: letterSpacing,
        ),
      ),
    );
  }
}

class _MastercardLogo extends StatelessWidget {
  const _MastercardLogo({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final double d = height;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      child: SizedBox(
        width: d * 1.55,
        height: d,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              child: Container(
                width: d,
                height: d,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFEB001B),
                ),
              ),
            ),
            Positioned(
              right: 0,
              child: Container(
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF79E1B).withValues(alpha: 0.78),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaestroLogo extends StatelessWidget {
  const _MaestroLogo({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final double d = height;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      child: SizedBox(
        width: d * 1.55,
        height: d,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 0,
              child: Container(
                width: d,
                height: d,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFEB001B),
                ),
              ),
            ),
            Positioned(
              right: 0,
              child: Container(
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0099DF).withValues(alpha: 0.82),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

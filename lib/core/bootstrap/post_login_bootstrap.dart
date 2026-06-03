import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/photo_crop_screen.dart';
import '../../features/executor_card/executor_card_screen.dart';
import '../../features/profile/widgets/verification_badge.dart';
import '../../features/services/my_services_screen.dart';
import '../auth/phone_format.dart';
import '../executor_card/executor_card_service.dart';
import '../profile/profile_service.dart';
import '../push/push_service.dart';

/// Тянет приватный профиль (подписка), карточку исполнителя и услуги
/// сразу после того, как стало известно про валидную сессию: либо на
/// splash при наличии auth-сессии, либо сразу после OTP-логина.
///
/// Без этого юзер, зашедший через OTP и тапнувший «Откликнуться» в
/// каталоге раньше, чем зайдёт в свою карточку/услуги, видел попап
/// «Создайте карточку исполнителя» (или «Создайте услугу»), хотя в БД
/// всё уже есть. Раньше bootstrap был только в splash_screen и
/// срабатывал лишь при холодном старте с уже валидной сессией.
///
/// Все три загрузки независимы; падение одной не отменяет другие.
Future<void> runPostLoginBootstrap() async {
  final Session? session = Supabase.instance.client.auth.currentSession;
  if (session == null) return;

  final String? rawPhone = session.user.phone;
  if (rawPhone != null && rawPhone.isNotEmpty) {
    final String e164 =
        rawPhone.startsWith('+') ? rawPhone : '+$rawPhone';
    CropResult.userPhoneE164 = e164;
    CropResult.userPhone = PhoneFormat.toPretty(e164);
  }

  await Future.wait<void>(<Future<void>>[
    _bootstrapSubscription(),
    _bootstrapExecutorCard(),
    _bootstrapServices(),
    // Регистрация FCM-токена сразу после OTP-логина. Внутри single-flight
    // + дедуп 5 минут — повторный вызов из main.dart (cold-start с
    // валидной сессией) не задвоит работу.
    PushService.instance.registerForCurrentUser(),
  ]);
}

Future<void> _bootstrapSubscription() async {
  try {
    final MyPrivate? priv = await ProfileService.instance.loadMyPrivate();
    final DateTime? paidUntil = priv?.subscriptionPaidUntil;
    if (paidUntil != null) {
      VerificationStatus.hasSubscription =
          paidUntil.isAfter(DateTime.now().toUtc());
      VerificationStatus.subscriptionPaidUntilText = _fmtDateRu(paidUntil);
    }
    if (priv?.email != null &&
        priv!.email!.isNotEmpty &&
        CropResult.userEmail.isEmpty) {
      CropResult.userEmail = priv.email!;
    }
  } catch (_) {/* фоллбэк: подписку поднимет profile_screen */}
}

Future<void> _bootstrapExecutorCard() async {
  try {
    final MyExecutorCard? c =
        await ExecutorCardService.instance.loadMine();
    if (c != null) {
      ExecutorCardState.cardCreated = c.savedAt != null;
    }
  } catch (_) {/* фоллбэк: карточку поднимет executor_card_screen */}
}

Future<void> _bootstrapServices() async {
  try {
    await ServiceData.refresh();
  } catch (_) {/* фоллбэк: services поднимет my_services_screen */}
}

const List<String> _monthsRu = <String>[
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

String _fmtDateRu(DateTime d) {
  final DateTime local = d.toLocal();
  return '${local.day} ${_monthsRu[local.month - 1]}';
}

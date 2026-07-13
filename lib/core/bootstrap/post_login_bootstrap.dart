import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/photo_crop_screen.dart';
import '../../features/executor_card/executor_card_screen.dart';
import '../../features/profile/account_block.dart';
import '../../features/profile/widgets/verification_badge.dart';
import '../../features/services/my_services_screen.dart';
import '../auth/phone_format.dart';
import '../executor_card/executor_card_service.dart';
import '../profile/profile_service.dart';
import '../settings/settings_service.dart';
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

  // Регистрация FCM-токена — в ФОНЕ (unawaited), НЕ держим на ней
  // навигацию. Запрос разрешения (до 60с) + получение токена (до 15с) на
  // прошивках без сервисов Google могут тянуться ~75с; раньше это висело в
  // awaited-пакете и замораживало экран кода. Внутри single-flight + дедуп
  // 5 минут — повторный вызов из main.dart (cold-start) не задвоит работу.
  unawaited(PushService.instance.registerForCurrentUser());

  // Помечаем аккаунт исполнителем: это приложение PRO, значит пользователь —
  // исполнитель. Раньше is_executor нигде не выставлялся в true, из-за чего
  // реальные исполнители не попадали ни в админ-панель (вкладка «Исполнители»,
  // где видны их документы), ни в каталог заказчику. Идемпотентно, в фоне.
  unawaited(_ensureExecutor());

  // Три загрузки гасят ложный попап «создайте карточку/услугу» — их ждём,
  // но они независимы; падение одной не отменяет другие.
  await Future.wait<void>(<Future<void>>[
    _bootstrapSubscription(),
    _bootstrapExecutorCard(),
    _bootstrapServices(),
    _bootstrapVerification(),
  ]);
}

/// Подтягивает статус верификации и блокировку по рейтингу сразу после
/// входа. Без этого верифицированный исполнитель, вошедший по коду и
/// сразу тапнувший «Откликнуться» (не заходя в профиль), видел ложное
/// «верификация не пройдена» — статус оставался дефолтным notVerified.
Future<void> _bootstrapVerification() async {
  try {
    final MyProfile? p = await ProfileService.instance.loadMine();
    if (p == null) return;
    AccountBlock.setUntil(p.blockedUntil);
    // В режиме «документы при каждой услуге» проверки личности аккаунта нет —
    // доступ на сервере завязан на одобренную услугу. Клиент считает аккаунт
    // «пройденным», чтобы карточка и отклик не требовали верификации аккаунта.
    // await-геттер сам дожидается/повторяет загрузку настроек — при
    // непрогретом кэше не откатываемся ложно в легаси-UI (верификация аккаунта).
    final bool perService = await SettingsService.instance.perServiceDocs();
    VerificationStatus.current = perService
        ? VerificationStatus.verified
        : switch (p.verificationStatus) {
            'approved' => VerificationStatus.verified,
            'pending' => VerificationStatus.inProgress,
            'rejected' => VerificationStatus.rejected,
            _ => VerificationStatus.notVerified,
          };
  } catch (_) {/* фоллбэк: статус поднимет profile_screen */}
}

Future<void> _ensureExecutor() async {
  try {
    await Supabase.instance.client.rpc('ensure_executor');
  } catch (_) {/* не критично: повторится при следующем входе и при подаче документов */}
}

Future<void> _bootstrapSubscription() async {
  try {
    final MyPrivate? priv = await ProfileService.instance.loadMyPrivate();
    final DateTime? paidUntil = priv?.subscriptionPaidUntil;
    if (paidUntil != null) {
      // grace-aware: зеркалит серверную is_subscription_active (3 дня форы
      // при автопродлении с картой). Раньше тут был сырой paidUntil>now,
      // из-за чего в grace-окне гейты блокировали отклик, хотя сервер пускал.
      VerificationStatus.hasSubscription = priv!.subscriptionActive;
      VerificationStatus.subscriptionPaidUntilText = _fmtDateRu(paidUntil);
      VerificationStatus.subscriptionPaidUntil = paidUntil;
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
      // Наполняем статический кэш ТЕМ ЖЕ преобразованием, что и экран
      // просмотра карточки (_loadFromDb). Раньше клали только cardCreated,
      // а адрес/радиус/статус/опыт отбрасывали — и форма правки, открытая
      // из ИИ-черновика до захода на экран просмотра, стартовала с пустыми
      // статусом/опытом и при «Сохранить» затирала их в БД на null.
      ExecutorCardData.location = c.locationAddress;
      ExecutorCardData.radius =
          c.radiusKm != null ? 'В радиусе ${c.radiusKm} км' : null;
      ExecutorCardData.about = c.about;
      ExecutorCardData.experience = c.experienceYears?.toString();
      ExecutorCardData.status = _legalStatusLabel(c.legalStatus);
      ExecutorCardState.cardCreated = c.savedAt != null;
    }
  } catch (_) {/* фоллбэк: карточку поднимет executor_card_screen */}
}

/// Код правового статуса (`legal_status`) → подпись для формы. Зеркалит
/// `_legalStatusLabel` в executor_card_screen — значения обязаны совпадать,
/// иначе кэш разойдётся с тем, что грузит экран просмотра.
String? _legalStatusLabel(String? code) {
  switch (code) {
    case 'individual':
      return 'Физ. лицо';
    case 'self_employed':
      return 'Самозанятый';
    case 'ip':
      return 'ИП';
    case 'legal_entity':
      return 'Юр. лицо';
    default:
      return null;
  }
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

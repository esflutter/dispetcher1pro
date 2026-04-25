import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'package:dispatcher_1/features/executor_card/executor_card_screen.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';
import 'package:dispatcher_1/features/services/my_services_screen.dart';

/// Моковый «сессионный кэш» — хранит снимок пользовательских данных
/// по номеру телефона, чтобы при выходе из аккаунта и повторном входе
/// по тому же номеру всё вернулось, а не пришлось регистрироваться
/// заново. До появления бэкенда играет роль серверной персистентности
/// профиля.
///
/// Не путать с `auth_reset` — там очистка текущей сессии в памяти.
/// Здесь — долгоживущее хранилище, которое переживает logout.
///
/// ⚠️ Любой новый статический стор с данными пользователя должен
/// синхронно попадать в [save] и [restore] этого класса, а также
/// чиститься в `_clearAll()` в `auth_reset.dart`. Иначе будут баги:
/// либо данные не вернутся после повторного входа, либо утекут между
/// аккаунтами на одном устройстве.
class SessionCache {
  SessionCache._();

  static final Map<String, _Snapshot> _byPhone = <String, _Snapshot>{};

  /// Есть ли сохранённая сессия для этого номера.
  static bool has(String phone) => _byPhone.containsKey(phone);

  /// Снять снимок с текущих статических сторов и сохранить под номером.
  /// Вызывается при выходе из аккаунта.
  static void save(String phone) {
    _byPhone[phone] = _Snapshot(
      userName: CropResult.userName,
      userEmail: CropResult.userEmail,
      avatar: CropResult.saved,
      verification: VerificationStatus.current,
      hasSubscription: VerificationStatus.hasSubscription,
      cardLocation: ExecutorCardData.location,
      cardRadius: ExecutorCardData.radius,
      cardExperience: ExecutorCardData.experience,
      cardStatus: ExecutorCardData.status,
      cardAbout: ExecutorCardData.about,
      cardCreated: ExecutorCardScreen.cardCreated,
      services: List<ServiceMock>.from(ServiceData.services),
      hasUnusedPaidSlot: ServiceData.hasUnusedPaidSlot,
    );
  }

  /// Восстановить пользовательские данные из снимка. Телефон
  /// подставляет заново из аргумента — это ключ снимка и то, что
  /// пользователь только что ввёл на экране входа.
  static void restore(String phone) {
    final _Snapshot? s = _byPhone[phone];
    if (s == null) return;
    CropResult.userName = s.userName;
    CropResult.userPhone = phone;
    CropResult.userEmail = s.userEmail;
    CropResult.saved = s.avatar;
    VerificationStatus.current = s.verification;
    VerificationStatus.hasSubscription = s.hasSubscription;
    ExecutorCardData.location = s.cardLocation;
    ExecutorCardData.radius = s.cardRadius;
    // Спецтехника и категории услуг не восстанавливаются отдельно —
    // они computed из `ServiceData.services`, которые восстанавливаются
    // ниже.
    ExecutorCardData.experience = s.cardExperience;
    ExecutorCardData.status = s.cardStatus;
    ExecutorCardData.about = s.cardAbout;
    ExecutorCardScreen.cardCreated = s.cardCreated;
    ServiceData.services
      ..clear()
      ..addAll(s.services);
    ServiceData.hasUnusedPaidSlot = s.hasUnusedPaidSlot;
  }

  /// Выбросить снимок — вызывается при удалении аккаунта.
  static void drop(String phone) {
    _byPhone.remove(phone);
  }
}

class _Snapshot {
  _Snapshot({
    required this.userName,
    required this.userEmail,
    required this.avatar,
    required this.verification,
    required this.hasSubscription,
    required this.cardLocation,
    required this.cardRadius,
    required this.cardExperience,
    required this.cardStatus,
    required this.cardAbout,
    required this.cardCreated,
    required this.services,
    required this.hasUnusedPaidSlot,
  });

  final String userName;
  final String userEmail;
  final CropResult? avatar;
  final VerificationStatus verification;
  final bool hasSubscription;
  final String? cardLocation;
  final String? cardRadius;
  final String? cardExperience;
  final String? cardStatus;
  final String? cardAbout;
  final bool cardCreated;
  final List<ServiceMock> services;
  final bool hasUnusedPaidSlot;
}

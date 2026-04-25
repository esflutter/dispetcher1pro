import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/clickable_address.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/catalog/widgets/catalog_search_bar.dart';
import 'package:dispatcher_1/core/widgets/cropped_avatar.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'package:dispatcher_1/core/utils/plural.dart';
import 'package:dispatcher_1/features/profile/account_block.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';
import 'package:dispatcher_1/features/services/my_services_screen.dart';

import 'widgets/executor_card_alerts.dart';
import 'widgets/executor_card_paywall.dart';

enum ExecutorCardStatus { empty, inReview, rejected, verified, blocked }

/// Глобальное состояние карточки исполнителя. Реактивное — любые
/// экраны, подписанные на `notifier`, перерисовываются при изменении
/// флага. Сброс до `false` делается в `auth_reset.dart` при logout.
///
/// Раньше был `static bool ExecutorCardScreen.cardCreated`, но
/// он не давал реактивности: если карточка создавалась из другого
/// экрана, родитель не узнавал об этом без ручного `setState`.
class ExecutorCardState {
  ExecutorCardState._();

  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  static bool get cardCreated => notifier.value;
  static set cardCreated(bool v) => notifier.value = v;
}

class ExecutorCardScreen extends StatefulWidget {
  const ExecutorCardScreen({super.key});

  /// Deprecated — оставлено как прокси для совместимости с существующими
  /// вызовами (`ExecutorCardScreen.cardCreated = true`). Новый код —
  /// через [ExecutorCardState.cardCreated].
  static bool get cardCreated => ExecutorCardState.cardCreated;
  static set cardCreated(bool v) => ExecutorCardState.cardCreated = v;

  @override
  State<ExecutorCardScreen> createState() => _ExecutorCardScreenState();
}

class _ExecutorCardScreenState extends State<ExecutorCardScreen> {
  /// Последний статус, для которого мы уже показали информационный
  /// алерт. Сравнивается со _status — если они разные, алерт надо
  /// показать снова. Это исправляет случай, когда пользователь
  /// получил алерт «на проверке», статус сменился на `rejected`, а
  /// алерт про отказ не показался, потому что `_alertShown` уже был
  /// выставлен в `true` прошлым заходом.
  ExecutorCardStatus? _lastAlertedStatus;

  bool get _filled =>
      AccountBlock.isBlocked ||
      (VerificationStatus.current.isVerified &&
          VerificationStatus.isSubscriptionValid &&
          ExecutorCardScreen.cardCreated);

  ExecutorCardStatus get _status {
    if (AccountBlock.isBlocked) return ExecutorCardStatus.blocked;
    switch (VerificationStatus.current) {
      case VerificationStatus.verified:
        return ExecutorCardScreen.cardCreated
            ? ExecutorCardStatus.verified
            : ExecutorCardStatus.empty;
      case VerificationStatus.inProgress:
        return ExecutorCardStatus.inReview;
      case VerificationStatus.rejected:
      case VerificationStatus.notVerified:
        return ExecutorCardStatus.empty;
    }
  }

  @override
  void initState() {
    super.initState();
    AccountBlock.notifier.addListener(_refresh);
    VerificationStatus.notifier.addListener(_refresh);
    ExecutorCardState.notifier.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowStatusAlert());
  }

  @override
  void dispose() {
    AccountBlock.notifier.removeListener(_refresh);
    VerificationStatus.notifier.removeListener(_refresh);
    ExecutorCardState.notifier.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _maybeShowStatusAlert();
  }

  /// Показываем информационный алерт, соответствующий текущему статусу,
  /// ровно один раз на статус. Если статус изменился с прошлого показа
  /// (например, `inReview` → `rejected`) — показываем снова.
  void _maybeShowStatusAlert() {
    if (!mounted) return;
    final ExecutorCardStatus s = _status;
    if (s == _lastAlertedStatus) return;
    if (s == ExecutorCardStatus.inReview) {
      _lastAlertedStatus = s;
      showExecutorCardStatusDialog(context, s);
    } else if (VerificationStatus.current == VerificationStatus.rejected) {
      _lastAlertedStatus = s;
      showCreateExecutorCardAlert(context);
    }
  }

  Future<void> _onCreateTap() async {
    if (AccountBlock.isBlocked) {
      await showExecutorCardStatusDialog(context, ExecutorCardStatus.blocked);
      return;
    }
    if (_status == ExecutorCardStatus.inReview) {
      await showExecutorCardStatusDialog(context, _status);
      return;
    }

    if (VerificationStatus.current.isVerified) {
      if (!VerificationStatus.isSubscriptionValid) {
        final bool? paid = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            fullscreenDialog: true,
            builder: (_) => const ExecutorCardPaywall(),
          ),
        );
        if (paid != true || !mounted) return;
        VerificationStatus.hasSubscription = true;
      }
      if (mounted) {
        await context.push('/executor-card/edit');
        if (mounted) setState(() {});
      }
      return;
    }

    await showCreateExecutorCardAlert(context);
    if (!mounted) return;

    if (_status == ExecutorCardStatus.inReview && mounted) {
      await showExecutorCardStatusDialog(context, _status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool filled = _filled;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Моя карточка исполнителя'),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 88.h),
        child: AiAssistantFab(onTap: () => context.push('/assistant/chat')),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: filled ? _FilledCard() : _EmptyContent(status: _status),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    offset: const Offset(0, -1),
                    blurRadius: 8,
                  ),
                ],
              ),
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
              child: filled
                  ? PrimaryButton(
                      label: 'Редактировать',
                      onPressed: () async {
                        await context.push('/executor-card/edit');
                        if (mounted) setState(() {});
                      },
                    )
                  : PrimaryButton(
                      label: 'Создать',
                      onPressed: _onCreateTap,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyContent extends StatelessWidget {
  const _EmptyContent({required this.status});
  final ExecutorCardStatus status;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 22.h),
          if (VerificationStatus.current.isVerified)
            const FullWidthVerificationPill(
                status: VerificationStatus.verified),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Создайте карточку\nисполнителя',
                    style: AppTextStyles.titleL,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 6.h),
                  Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16.w),
                    child: Text(
                      'Заказчики смогут посмотреть информацию о вас, услугах и связаться с вами.',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Данные карточки исполнителя (до появления бэкенда).
class ExecutorCardData {
  /// Имя — прокси на [CropResult.userName], чтобы имя в карточке и в
  /// профиле оставалось одним источником правды.
  static String get name => CropResult.userName;
  static set name(String value) => CropResult.userName = value;

  /// Телефон — всегда совпадает с номером профиля из регистрации
  /// ([CropResult.userPhone]). Отдельно не хранится и не меняется:
  /// изменение номера возможно только через повторную регистрацию.
  static String get phone => CropResult.userPhone;

  static String? location;
  static String? radius;

  /// Спецтехника и категории услуг — НЕ хранятся отдельно.
  /// Подтягиваются из услуг исполнителя (объединение по всем услугам,
  /// distinct, порядок первого появления). Единственный источник
  /// истины — `ServiceData.services`, поэтому сеттеров нет: меняется
  /// только через создание/удаление услуг в «Мои услуги».
  static List<String> get machinery => _unionFromServices((s) => s.machinery);
  static List<String> get categories => _unionFromServices((s) => s.categories);

  static List<String> _unionFromServices(
      List<String> Function(ServiceMock) pick) {
    final Set<String> seen = <String>{};
    final List<String> out = <String>[];
    for (final ServiceMock s in ServiceData.services) {
      for (final String v in pick(s)) {
        if (seen.add(v)) out.add(v);
      }
    }
    return out;
  }

  static String? experience;
  static String? status;
  static String? about;

  /// Сбросить все поля карточки к значениям «как при первом запуске» —
  /// для logout / удаления аккаунта. Техника и категории обнуляются
  /// через `ServiceData.clear()`, телефон — через сброс
  /// `CropResult.userPhone` (делается в `auth_reset`), отдельно не
  /// трогаем.
  static void clear() {
    location = null;
    radius = null;
    experience = null;
    status = null;
    about = null;
  }
}

class _FilledCard extends StatelessWidget {
  // Non-const умышленно: читает из статической `ExecutorCardData`, и чтобы
  // родитель мог перерисовать карточку после возврата из экрана
  // редактирования, каждый build должен создавать новый instance. Иначе
  // Flutter видит идентичный const-виджет и пропускает rebuild.
  // ignore: prefer_const_constructors_in_immutables
  _FilledCard();

  String _val(String? v) => (v != null && v.isNotEmpty) ? v : '—';

  /// Форматирует опыт работы: «5 лет», «1 год», «2 года» или «—».
  String _experienceText(String? v) {
    final int? n = v != null ? int.tryParse(v) : null;
    if (n == null) return '—';
    final int mod100 = n % 100;
    final String word;
    if (mod100 >= 11 && mod100 <= 14) {
      word = 'лет';
    } else {
      switch (n % 10) {
        case 1:
          word = 'год';
          break;
        case 2:
        case 3:
        case 4:
          word = 'года';
          break;
        default:
          word = 'лет';
      }
    }
    return '$n $word';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(),
          SizedBox(height: 20.h),
          _SectionTitle('Номер телефона'),
          SizedBox(height: 4.h),
          Text(ExecutorCardData.phone, style: AppTextStyles.body),
          SizedBox(height: 16.h),
          _SectionTitle('Электронная почта'),
          SizedBox(height: 4.h),
          Text(_val(CropResult.userEmail), style: AppTextStyles.body),
          SizedBox(height: 16.h),
          _SectionTitle('Местоположение'),
          SizedBox(height: 4.h),
          (ExecutorCardData.location != null &&
                  ExecutorCardData.location!.trim().isNotEmpty)
              ? ClickableAddress(ExecutorCardData.location!,
                  baseStyle: AppTextStyles.body)
              : Text(_val(ExecutorCardData.location),
                  style: AppTextStyles.body),
          if (ExecutorCardData.radius != null && ExecutorCardData.radius!.isNotEmpty) ...[
            SizedBox(height: 2.h),
            Text(ExecutorCardData.radius!,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textTertiary)),
          ],
          SizedBox(height: 16.h),
          _SectionTitle('Спецтехника'),
          SizedBox(height: 8.h),
          // Techника подтягивается из услуг (computed getter). Оборачиваем
          // в StatefulBuilder, чтобы после возврата с /services (по кнопке
          // CTA) можно было перерисовать только этот блок без лишних
          // setState на всём экране.
          StatefulBuilder(
            builder: (BuildContext ctx, StateSetter setInner) {
              final List<String> items = ExecutorCardData.machinery;
              if (items.isNotEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ChipWrap(items: items),
                    SizedBox(height: 8.h),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 14.sp,
                          color: AppColors.textTertiary,
                        ),
                        children: [
                          const TextSpan(text: 'Добавьте '),
                          WidgetSpan(
                            baseline: TextBaseline.alphabetic,
                            alignment: PlaceholderAlignment.baseline,
                            child: GestureDetector(
                              onTap: () async {
                                await ctx.push('/services');
                                if (ctx.mounted) setInner(() {});
                              },
                              child: Text(
                                'новую услугу',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 14.sp,
                                  color: AppColors.textTertiary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                          const TextSpan(
                              text: ', чтобы расширить список спецтехники.'),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return _EmptyMachineryCta(
                hint: 'Создайте первую услугу — и здесь появятся '
                    'виды вашей спецтехники.',
                onTap: () async {
                  await ctx.push('/services');
                  if (ctx.mounted) setInner(() {});
                },
              );
            },
          ),
          SizedBox(height: 16.h),
          _SectionTitle('Категории услуг'),
          SizedBox(height: 8.h),
          // Категории — тот же computed-getter паттерн, что и спецтехника.
          StatefulBuilder(
            builder: (BuildContext ctx, StateSetter setInner) {
              final List<String> items = ExecutorCardData.categories;
              if (items.isNotEmpty) return _ChipWrap(items: items);
              return _EmptyMachineryCta(
                hint: 'Создайте первую услугу — и здесь появятся '
                    'категории ваших работ.',
                onTap: () async {
                  await ctx.push('/services');
                  if (ctx.mounted) setInner(() {});
                },
              );
            },
          ),
          SizedBox(height: 16.h),
          _SectionTitle('Опыт работы'),
          SizedBox(height: 4.h),
          Text(_experienceText(ExecutorCardData.experience),
              style: AppTextStyles.body),
          SizedBox(height: 16.h),
          _SectionTitle('Статус'),
          SizedBox(height: 4.h),
          Text(_val(ExecutorCardData.status), style: AppTextStyles.body),
          SizedBox(height: 16.h),
          _SectionTitle('О себе'),
          SizedBox(height: 4.h),
          Text(_val(ExecutorCardData.about), style: AppTextStyles.body),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        CroppedAvatar(size: 72.r),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(CropResult.displayName, style: AppTextStyles.titleS),
              SizedBox(height: 4.h),
              Row(
                children: [
                  Image.asset('assets/images/catalog/star.webp',
                      width: 20.r, height: 20.r),
                  SizedBox(width: 4.w),
                  Text('4,5', style: AppTextStyles.body),
                  SizedBox(width: 16.w),
                  GestureDetector(
                    onTap: () => context.push('/profile/reviews'),
                    child: Text(
                      '${ReviewsData.count} ${reviewsWord(ReviewsData.count)}',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textPrimary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTextStyles.bodyMedium
          .copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: items
          .map((label) => Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.primary, width: 1),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  label,
                  style: AppTextStyles.chip.copyWith(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textPrimary,
                  ),
                ),
              ))
          .toList(),
    );
  }
}

/// Пустое состояние блока «Спецтехника»/«Категории услуг» в просмотре
/// карточки: когда у исполнителя ещё нет ни одной услуги — показываем
/// подсказку и оранжевую outlined-кнопку перехода в «Мои услуги». Как
/// только появится первая услуга, блок заменится на чипы (в родителе).
class _EmptyMachineryCta extends StatelessWidget {
  const _EmptyMachineryCta({required this.onTap, required this.hint});

  final VoidCallback onTap;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          hint,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14.sp,
            fontWeight: FontWeight.w400,
            height: 1.3,
            color: AppColors.textTertiary,
          ),
        ),
        SizedBox(height: 12.h),
        SecondaryButton(
          label: 'Перейти к моим услугам',
          onPressed: onTap,
          height: 42.h,
        ),
      ],
    );
  }
}

Future<void> showExecutorCardStatusDialog(
    BuildContext context, ExecutorCardStatus status) {
  final String title;
  final String text;
  if (status == ExecutorCardStatus.inReview) {
    title = 'Ваши документы ещё\nна проверке';
    text = 'Вы получите уведомление, когда проверка завершится';
  } else if (status == ExecutorCardStatus.blocked) {
    title = 'Ваш профиль заблокирован\nна 30 дней';
    text = 'Во избежание дальнейших блокировок избегайте отзывов с низкой оценкой';
  } else {
    title = 'Документы не прошли\nпроверку';
    text = 'Проверьте данные и отправьте документы ещё раз';
  }
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 16.w),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.r, 14.r, 16.r, 22.r),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Icon(Icons.close_rounded,
                    size: 22.r, color: AppColors.textTertiary),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleL.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8.h),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMRegular
                  .copyWith(color: AppColors.textSecondary),
            ),
            SizedBox(height: 18.h),
            PrimaryButton(
              label: 'Ок',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            SizedBox(height: 12.h),
          ],
        ),
      ),
    ),
  );
}

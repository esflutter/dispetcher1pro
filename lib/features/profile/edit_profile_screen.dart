import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/auth/auth_reset.dart';
import 'package:dispatcher_1/core/profile/profile_service.dart';
import 'package:dispatcher_1/core/storage/storage_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/photo_source.dart';
import 'package:dispatcher_1/core/widgets/cropped_avatar.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'profile_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const int _nameMaxLen = 60;
  static const int _emailMaxLen = 50;

  /// Базовая проверка формата email: что-то@что-то.tld, без пробелов.
  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
  );

  late final TextEditingController _nameCtrl =
      TextEditingController(text: CropResult.userName);
  late final TextEditingController _emailCtrl =
      TextEditingController(text: CropResult.userEmail);

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();

  /// Показывать ли красную подсказку под полем телефона — включается
  /// по тапу на телефон (сменить номер нельзя, см. текст подсказки).
  bool _showPhoneHint = false;

  /// Текст ошибки под полем email. Выставляется при потере фокуса,
  /// если формат не проходит валидацию. Сбрасывается при возврате
  /// фокуса в поле либо после корректного ввода.
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() async {
      if (!_nameFocus.hasFocus) {
        final String value = _nameCtrl.text.trim();
        if (value.isEmpty) {
          _nameCtrl.text = CropResult.userName;
        } else if (value != CropResult.userName) {
          CropResult.userName = value;
          try {
            await ProfileService.instance.update(name: value);
          } catch (_) {
            // Сеть/БД упала — имя останется в UI локально, но попадёт
            // в БД при следующем успешном сохранении.
          }
        }
      }
    });
    _emailFocus.addListener(() async {
      if (_emailFocus.hasFocus) {
        if (_emailError != null) {
          setState(() => _emailError = null);
        }
      } else {
        final String value = _emailCtrl.text.trim();
        final bool valid = value.isEmpty || _emailRegex.hasMatch(value);
        if (valid) {
          if (value != CropResult.userEmail) {
            CropResult.userEmail = value;
            try {
              await ProfileService.instance.updatePrivateEmail(value);
            } catch (_) {/* silent */}
          }
          if (_emailError != null) setState(() => _emailError = null);
        } else {
          setState(() => _emailError = 'Некорректная электронная почта');
        }
      }
    });
  }

  @override
  void dispose() {
    // Фикс значения на случай, если пользователь ушёл со экрана
    // не снимая фокус (например, кнопкой назад). Невалидные значения
    // просто не попадают в [CropResult] — там остаётся последнее
    // сохранённое валидное.
    final String name = _nameCtrl.text.trim();
    if (name.isNotEmpty) CropResult.userName = name;
    final String email = _emailCtrl.text.trim();
    if (email.isEmpty || _emailRegex.hasMatch(email)) {
      CropResult.userEmail = email;
    }
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Редактирование профиля'),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 16.h),
              Center(child: _PhotoPicker()),
              SizedBox(height: AppSpacing.xl),
              _EditableField(
                controller: _nameCtrl,
                hint: 'Имя и фамилия',
                keyboardType: TextInputType.name,
                maxLength: _nameMaxLen,
                focusNode: _nameFocus,
              ),
              SizedBox(height: AppSpacing.sm),
              _EditableField(
                controller: _emailCtrl,
                hint: 'Электронная почта',
                keyboardType: TextInputType.emailAddress,
                maxLength: _emailMaxLen,
                focusNode: _emailFocus,
              ),
              if (_emailError != null) ...[
                SizedBox(height: 6.h),
                Text(
                  _emailError!,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                    color: AppColors.error,
                  ),
                ),
              ],
              SizedBox(height: AppSpacing.sm),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    setState(() => _showPhoneHint = !_showPhoneHint),
                child: _TintField(text: CropResult.userPhone),
              ),
              if (_showPhoneHint) ...[
                SizedBox(height: 6.h),
                Text(
                  'Для смены номера телефона обратитесь в техподдержку '
                  'или зарегистрируйте новый аккаунт.',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                    color: AppColors.error,
                  ),
                ),
              ],
              const Spacer(),
              _ActionTile(
                iconAsset: 'assets/icons/profile/logout.webp',
                text: 'Выйти из аккаунта',
                arrowAsset: 'assets/icons/profile/arrow_right.webp',
                onTap: () async {
                  final confirmed = await showLogoutAlert(context);
                  if (confirmed == true && context.mounted) {
                    signOut();
                    context.go('/auth/phone');
                  }
                },
              ),
              SizedBox(height: AppSpacing.sm),
              _ActionTile(
                iconAsset: 'assets/icons/profile/delete.webp',
                text: 'Удалить аккаунт',
                arrowAsset: 'assets/icons/profile/arrow_right_red.webp',
                danger: true,
                onTap: () async {
                  final confirmed = await showDeleteAccountAlert(context);
                  if (confirmed != true || !context.mounted) return;
                  // hard_delete_user — security definer RPC: удаляет
                  // auth.users (CASCADE убирает profiles и связанные
                  // данные), создаёт маркер бана по SHA-256 от телефона.
                  try {
                    final user = Supabase.instance.client.auth.currentUser;
                    if (user != null) {
                      await Supabase.instance.client
                          .rpc('hard_delete_user', params: <String, dynamic>{
                        'p_user_id': user.id,
                        'p_reason': 'user_request',
                      });
                    }
                  } catch (_) {/* всё равно делаем local cleanup */}
                  await Supabase.instance.client.auth.signOut();
                  if (!context.mounted) return;
                  deleteAccount();
                  context.go('/auth/phone');
                },
              ),
              SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPicker extends StatefulWidget {
  @override
  State<_PhotoPicker> createState() => _PhotoPickerState();
}

class _PhotoPickerState extends State<_PhotoPicker> {
  Future<void> _openCrop() async {
    final String? imagePath = await pickImageFromGallery(context: context);
    if (imagePath == null || !mounted) return;
    final result = await Navigator.of(context).push<CropResult>(
      MaterialPageRoute(
        builder: (_) => PhotoCropScreen(imagePath: imagePath),
      ),
    );
    if (result != null && mounted) {
      setState(() => CropResult.saved = result);
      // Загружаем оригинал в Storage и сохраняем URL в profiles.avatar_url.
      // Используем исходный путь (до кропа) — крой хранится только визуально
      // в CropResult; серверное превью будем делать отдельно при показе.
      final String? path = result.imagePath;
      if (path != null && !path.startsWith('assets/')) {
        _uploadAvatar(path);
      }
    }
  }

  Future<void> _uploadAvatar(String path) async {
    try {
      final String url =
          await StorageService.instance.uploadAvatar(File(path));
      await ProfileService.instance.update(avatarUrl: url);
    } catch (_) {
      // Ошибка загрузки не блокирует UI — локально кроп уже сохранён
      // в CropResult.saved; синхронизируем при следующем успешном save.
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openCrop,
      child: SizedBox(
        width: 104.r,
        height: 104.r,
        child: Stack(
          children: [
            CroppedAvatar(size: 104.r),
            Positioned(
              right: -2.w,
              bottom: 0,
              child: Image.asset(
                'assets/icons/ui/edit.webp',
                width: 28.r,
                height: 28.r,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TintField extends StatelessWidget {
  const _TintField({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56.h,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.fieldFill,
        borderRadius: BorderRadius.circular(14.r),
      ),
      alignment: Alignment.centerLeft,
      child: Text(text, style: AppTextStyles.body),
    );
  }
}

/// Редактируемое поле в том же стиле, что и [_TintField], но с
/// подключённым контроллером и hint-текстом. Всегда редактируется по
/// нажатию — отдельной иконки-карандаша нет.
class _EditableField extends StatelessWidget {
  const _EditableField({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.maxLength,
    this.focusNode,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final int? maxLength;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56.h,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.fieldFill,
        borderRadius: BorderRadius.circular(14.r),
      ),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        maxLength: maxLength,
        style: AppTextStyles.body,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          // Скрываем встроенный счётчик maxLength — ограничение работает
          // только как жёсткий обрез ввода, показывать «X/Y» не надо.
          counterText: '',
          hintText: hint,
          hintStyle:
              AppTextStyles.body.copyWith(color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.iconAsset,
    required this.text,
    required this.onTap,
    required this.arrowAsset,
    this.danger = false,
  });

  final String iconAsset;
  final String arrowAsset;
  final String text;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.textPrimary;
    return Material(
      color: AppColors.categoryCard,
      borderRadius: BorderRadius.circular(14.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14.r),
        child: Container(
          height: 56.h,
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Image.asset(iconAsset, width: 22.r, height: 22.r),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(text,
                    style: AppTextStyles.body.copyWith(color: color)),
              ),
              Image.asset(arrowAsset, width: 20.r, height: 20.r),
            ],
          ),
        ),
      ),
    );
  }
}

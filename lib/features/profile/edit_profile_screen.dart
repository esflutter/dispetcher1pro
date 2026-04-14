import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/cropped_avatar.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';
import 'profile_screen.dart';

class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key});

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
              _TintField(text: CropResult.userName),
              SizedBox(height: AppSpacing.sm),
              _TintField(text: CropResult.userPhone),
              const Spacer(),
              _ActionTile(
                iconAsset: 'assets/icons/profile/logout.webp',
                text: 'Выйти из аккаунта',
                arrowAsset: 'assets/icons/profile/arrow_right.webp',
                onTap: () async {
                  final confirmed = await showLogoutAlert(context);
                  if (confirmed == true && context.mounted) {
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
                  if (confirmed == true && context.mounted) {
                    context.go('/auth/phone');
                  }
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
    final result = await Navigator.of(context).push<CropResult>(
      MaterialPageRoute(builder: (_) => const PhotoCropScreen()),
    );
    if (result != null && mounted) {
      setState(() => CropResult.saved = result);
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

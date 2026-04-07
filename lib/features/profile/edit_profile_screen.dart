import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';

class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20.r, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: Text(
          'Редактирование профиля',
          style: AppTextStyles.titleS.copyWith(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            AppSpacing.screenH, AppSpacing.lg, AppSpacing.screenH, AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: _PhotoPicker()),
            SizedBox(height: AppSpacing.xl),
            const _InfoField(
              icon: Icons.person_outline,
              text: 'Александр Иванов',
              tint: true,
            ),
            SizedBox(height: AppSpacing.sm),
            const _InfoField(
              icon: Icons.phone_outlined,
              text: '+7 999 123-45-67',
              tint: true,
            ),
            SizedBox(height: AppSpacing.sm),
            _InfoField(
              icon: Icons.logout_rounded,
              text: 'Выйти из аккаунта',
              tint: false,
              onTap: () => context.go('/auth/phone'),
            ),
            SizedBox(height: AppSpacing.sm),
            _InfoField(
              icon: Icons.delete_outline_rounded,
              text: 'Удалить аккаунт',
              tint: false,
              danger: true,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Аккаунт удалён (демо)'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100.r,
      height: 100.r,
      child: Stack(
        children: [
          Container(
            width: 100.r,
            height: 100.r,
            decoration: const BoxDecoration(
              color: AppColors.border,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person,
                size: 60.r, color: const Color(0xFF707070)),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 32.r,
              height: 32.r,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.edit,
                  size: 18.r, color: AppColors.textHeading),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoField extends StatelessWidget {
  const _InfoField({
    required this.icon,
    required this.text,
    required this.tint,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String text;
  final bool tint;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusM),
      child: Container(
        height: 56.h,
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: tint ? AppColors.primaryTint : const Color(0xFFF1F1F1),
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22.r, color: color),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(text,
                  style: AppTextStyles.body.copyWith(color: color)),
            ),
            if (!tint)
              Icon(Icons.chevron_right_rounded,
                  size: 20.r, color: color),
          ],
        ),
      ),
    );
  }
}

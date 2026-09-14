import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/auth/guest_gate.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Полезный стартовый экран для гостя вместо пустого живого каталога.
class GuestStartScreen extends StatelessWidget {
  const GuestStartScreen({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.background,
    child: SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(child: _hero()),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16.w, 18.h, 16.w, 120.h),
            sliver: SliverList.list(
              children: <Widget>[
                _primaryAction(context),
                SizedBox(height: 16.h),
                _catalogAction(context),
                SizedBox(height: 14.h),
                Center(
                  child: TextButton(
                    onPressed: () =>
                        startGuestAuth(context, intent: GuestAuthIntent.signIn),
                    child: Text(
                      'Уже есть аккаунт? Войти',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _hero() => Container(
    color: AppColors.navBarDark,
    padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 28.h),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(11.r),
              child: Image.asset(
                'assets/icons/app_icon.png',
                width: 44.r,
                height: 44.r,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Диспетчер №1 PRO',
                    style: AppTextStyles.titleL.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'для исполнителей',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 26.h),
        Text(
          'Найдите новые заказы',
          style: AppTextStyles.h2.copyWith(color: Colors.white),
        ),
        SizedBox(height: 8.h),
        Text(
          'Создайте профиль — заказчики смогут выбрать именно вас.',
          style: AppTextStyles.body.copyWith(color: Colors.white70),
        ),
      ],
    ),
  );

  Widget _primaryAction(BuildContext context) => Container(
    padding: EdgeInsets.all(18.r),
    decoration: BoxDecoration(
      color: AppColors.primaryTint,
      borderRadius: BorderRadius.circular(20.r),
      border: Border.all(color: AppColors.primaryTintStrong),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 46.r,
          height: 46.r,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.person_add_alt_1_rounded,
            color: Colors.white,
            size: 25.r,
          ),
        ),
        SizedBox(height: 14.h),
        Text('Создайте профиль исполнителя', style: AppTextStyles.titleL),
        SizedBox(height: 6.h),
        Text(
          'Регистрация займёт около минуты. После неё сразу откроется оформление профиля.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        SizedBox(height: 18.h),
        PrimaryButton(
          label: 'Создать профиль',
          onPressed: () =>
              startGuestAuth(context, intent: GuestAuthIntent.createProfile),
        ),
      ],
    ),
  );

  Widget _catalogAction(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(18.r),
    onTap: () => showGuestAuthPrompt(
      context,
      message:
          'Войдите и создайте профиль, чтобы смотреть заказы и откликаться.',
      intent: GuestAuthIntent.browseCatalog,
    ),
    child: Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(18.r),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44.r,
            height: 44.r,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.work_outline_rounded,
              color: AppColors.textHeading,
              size: 24.r,
            ),
          ),
          SizedBox(width: 13.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Каталог заказов', style: AppTextStyles.titleS),
                SizedBox(height: 3.h),
                Text(
                  'Откроется после создания профиля',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 17.r,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    ),
  );
}

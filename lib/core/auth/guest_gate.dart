import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/dialog_close_button.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Гость — пользователь без активной Supabase-сессии. Лента заказов ему открыта
/// (см. миграцию 101 — anon читает опубликованные заказы), но «аккаунтные»
/// разделы и действия (отклик, мои заказы, профиль, услуги, график) требуют входа.
bool get isGuest => Supabase.instance.client.auth.currentSession == null;

/// Полноэкранная заглушка для вкладок, доступных только вошедшим
/// («Заказы», «Профиль»): иконка + текст + кнопка «Войти». В стиле приложения.
class GuestLockedView extends StatelessWidget {
  const GuestLockedView({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.lock_outline,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 64.r, color: AppColors.textTertiary),
            SizedBox(height: 20.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 10.h),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textTertiary),
            ),
            SizedBox(height: 24.h),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Войти',
                onPressed: () => context.go('/auth/phone'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Попап «нужен вход» для действий, требующих аккаунта (откликнуться, ассистент
/// и т.п.). [message] — пояснение, что именно требует входа. Возвращает true,
/// если пользователь пошёл на вход.
Future<bool> showGuestAuthPrompt(
  BuildContext context, {
  required String message,
}) async {
  final bool? wentToLogin = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (BuildContext ctx) => Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 16.w),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.r, 18.r, 16.r, 24.r),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: DialogCloseButton(
                onTap: () => Navigator.of(ctx).pop(false),
                color: AppColors.textTertiary,
                iconSize: 22.r,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              'Требуется авторизация',
              textAlign: TextAlign.center,
              style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 10.h),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textSecondary),
            ),
            SizedBox(height: 20.h),
            PrimaryButton(
              label: 'Войти',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            SizedBox(height: 20.h),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(false),
              child: Center(
                child: Text(
                  'Позже',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    ),
  );
  if (wentToLogin == true && context.mounted) {
    context.go('/auth/phone');
    return true;
  }
  return false;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/auth/auth_service.dart';
import 'package:dispatcher_1/core/auth/phone_format.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'photo_crop_screen.dart';

class PhoneInputScreen extends StatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  State<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends State<PhoneInputScreen> {
  final _maskFormatter = MaskTextInputFormatter(
    mask: '(###) ###-##-##',
    filter: {'#': RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );
  final TextEditingController _controller = TextEditingController();
  bool _isComplete = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!mounted) return;
    final complete = _maskFormatter.getUnmaskedText().length == 10;
    if (complete != _isComplete) {
      setState(() => _isComplete = complete);
    }
  }

  Future<void> _onNext() async {
    final String e164;
    try {
      e164 = PhoneFormat.toE164(_maskFormatter.getUnmaskedText());
    } on FormatException catch (e) {
      _showError(e.message);
      return;
    }

    setState(() => _sending = true);
    try {
      // 10 с — потолок ожидания SMS-провайдера. Без timeout кнопка
      // оставалась залипшей disabled-state, пока DNS/сеть не отвалятся
      // по системному таймауту (десятки секунд).
      await AuthService.instance
          .sendOtp(e164)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      CropResult.userPhoneE164 = e164;
      CropResult.userPhone = PhoneFormat.toPretty(e164);
      context.go('/auth/otp');
    } on TimeoutException {
      if (mounted) _showError('Сервер не отвечает. Попробуйте позже.');
    } on AuthException catch (e) {
      if (!mounted) return;
      // Supabase Auth заворачивает SocketException/ClientException
      // в AuthException с сырым текстом. Подменяем на дружелюбное
      // сообщение, чтобы юзер не видел `Failed host lookup ...`.
      _showError(_looksLikeNetwork(e.message)
          ? 'Нет соединения с сервером. Проверьте интернет или отключите VPN.'
          : e.message);
    } catch (e) {
      if (!mounted) return;
      _showError(_looksLikeNetwork(e.toString())
          ? 'Нет соединения с сервером. Проверьте интернет или отключите VPN.'
          : 'Не удалось отправить код. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _looksLikeNetwork(String message) =>
      message.contains('SocketException') ||
      message.contains('Failed host lookup') ||
      message.contains('ClientException') ||
      message.contains('Connection refused') ||
      message.contains('Connection closed') ||
      message.contains('errno = 7');

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 16.h),
                    Text(
                      'Введите номер\nтелефона',
                      style: AppTextStyles.h1Phone.copyWith(color: AppColors.textBlack),
                    ),
                    SizedBox(height: 40.h),
                    Text(
                      'Номер телефона',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 16.sp,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    _PhoneField(controller: _controller, formatter: _maskFormatter),
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
              decoration: BoxDecoration(
                color: AppColors.background,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    offset: const Offset(0, -4),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: PrimaryButton(
                label: 'Далее',
                enabled: _isComplete && !_sending,
                onPressed: (_isComplete && !_sending) ? _onNext : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.controller, required this.formatter});

  final TextEditingController controller;
  final MaskTextInputFormatter formatter;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56.h,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(16.r),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.phone,
        autofocus: true,
        inputFormatters: <TextInputFormatter>[formatter],
        style: AppTextStyles.body.copyWith(
          fontSize: 16.sp,
          color: AppColors.textBlack,
        ),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          prefix: Text(
            '+7 ',
            style: AppTextStyles.body.copyWith(
              fontSize: 16.sp,
              color: AppColors.textBlack,
            ),
          ),
          hintText: '(900) 000-00-00',
          hintStyle: AppTextStyles.body.copyWith(
            fontSize: 16.sp,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

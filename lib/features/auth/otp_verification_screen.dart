import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key, this.phone});

  /// Номер, на который отправлен код. Если не передан — подставляется
  /// [CropResult.userPhone], сохранённый экраном ввода телефона.
  final String? phone;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const int _otpLength = 6;
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();

  bool _hasError = false;
  bool _codeResent = false;
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Таймер больше не запускается автоматически при входе на страницу
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        if (mounted) {
          setState(() {
            _secondsLeft = 0;
            _codeResent = false;
          });
        }
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  String _formatSeconds(int count) {
    final remainder10 = count % 10;
    final remainder100 = count % 100;

    if (remainder100 >= 11 && remainder100 <= 14) return '$count секунд';
    if (remainder10 == 1) return '$count секунду';
    if (remainder10 >= 2 && remainder10 <= 4) return '$count секунды';
    return '$count секунд';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _onCompleted(String code) {
    // Просто прячем клавиатуру при полном вводе
    _pinFocusNode.unfocus();
    setState(() {});
  }

  void _submit() {
    final code = _pinController.text;
    if (code == '000000') {
      setState(() => _hasError = true);
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && _hasError) {
          _pinController.clear();
          setState(() => _hasError = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _pinFocusNode.requestFocus();
          });
        }
      });
    } else {
      context.go('/auth/registration');
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 52.w,
      height: 64.h,
      textStyle: AppTextStyles.h3.copyWith(
        color: AppColors.textBlack,
        fontSize: 22.sp,
        fontWeight: FontWeight.w600,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(12.r),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: AppColors.primary, width: 1.5),
        color: AppColors.primaryTint,
      ),
    );

    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: Colors.transparent, width: 0),
        color: AppColors.errorTint,
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    SizedBox(height: 16.h),
                    Text(
                      'Верификация',
                      style: AppTextStyles.h1Phone.copyWith(color: AppColors.textBlack),
                    ),
                    SizedBox(height: 16.h),
                    Text(
                      'Код был выслан по номеру',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 18.sp,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      widget.phone?.trim().isNotEmpty == true
                          ? widget.phone!
                          : CropResult.userPhone,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textBlack,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 21.h),
                    Pinput(
                      controller: _pinController,
                      focusNode: _pinFocusNode,
                      length: _otpLength,
                      autofocus: true,
                      cursor: Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 2,
                          height: 22.h,
                          color: AppColors.primary,
                        ),
                      ),
                      defaultPinTheme: defaultPinTheme,
                      focusedPinTheme: focusedPinTheme,
                      errorPinTheme: errorPinTheme,
                      forceErrorState: _hasError,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      onChanged: (_) {
                        if (_hasError) {
                          setState(() => _hasError = false);
                        } else {
                          setState(() {});
                        }
                      },
                      onCompleted: _onCompleted,
                    ),
                    if (_hasError) ...[
                      SizedBox(height: 12.h),
                      Text(
                        'Неверный код',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.error,
                          fontSize: 15.sp,
                        ),
                      ),
                    ],
                    SizedBox(height: 21.h),
                    _secondsLeft > 0
                        ? RichText(
                            text: TextSpan(
                              text: 'Не пришёл код? ',
                              style: AppTextStyles.body.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 15.sp,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Отправить повторно через ${_formatSeconds(_secondsLeft)}',
                                  style: const TextStyle(
                                    color: AppColors.textBlack,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GestureDetector(
                            onTap: () {
                              _pinController.clear();
                              setState(() {
                                _hasError = false;
                                _codeResent = true;
                              });
                              _startTimer();
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) {
                                if (mounted) _pinFocusNode.requestFocus();
                              });
                            },
                            child: RichText(
                              text: TextSpan(
                                text: 'Не пришёл код? ',
                                style: AppTextStyles.body.copyWith(
                                  color: AppColors.textTertiary,
                                  fontSize: 14.sp,
                                ),
                                children: const [
                                  TextSpan(
                                    text: 'Отправить повторно',
                                    style: TextStyle(
                                      color: AppColors.textBlack,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    if (_codeResent) ...[
                      SizedBox(height: 32.h),
                      Text(
                        'Новый код отправлен',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.textBlack,
                          fontSize: 14.sp,
                        ),
                      ),
                    ],
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
                enabled: _pinController.text.length == _otpLength && !_hasError,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

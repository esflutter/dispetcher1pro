import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

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

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final complete = _maskFormatter.getUnmaskedText().length == 10;
      if (complete != _isComplete) {
        setState(() => _isComplete = complete);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
                    color: Colors.black.withOpacity(0.04),
                    offset: const Offset(0, -4),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: PrimaryButton(
                label: 'Далее',
                enabled: _isComplete,
                onPressed: _isComplete
                    ? () {
                        final d = _maskFormatter.getUnmaskedText();
                        CropResult.userPhone =
                            '+7 ${d.substring(0, 3)} ${d.substring(3, 6)}-${d.substring(6, 8)}-${d.substring(8, 10)}';
                        context.go('/auth/otp');
                      }
                    : null,
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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/photo_source.dart';
import 'package:dispatcher_1/core/widgets/cropped_avatar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';
import 'package:dispatcher_1/features/auth/photo_crop_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _firstNameController = TextEditingController();
  bool _agreed = false;
  CropResult? _cropResult;

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _firstNameController.dispose();
    super.dispose();
  }

  bool get _isValid => _firstNameController.text.trim().isNotEmpty && _agreed;

  Future<void> _openPhotoSheet() async {
    final String? imagePath = await pickImageFromGallery(context: context);
    if (imagePath == null || !mounted) return;
    final result = await Navigator.of(context).push<CropResult>(
      MaterialPageRoute(
        builder: (_) => PhotoCropScreen(imagePath: imagePath),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _cropResult = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      'Введите данные',
                      style: AppTextStyles.h1Phone.copyWith(color: AppColors.textBlack),
                    ),
                    SizedBox(height: 40.h),
                    Center(
                      child: _AvatarSlot(
                        onTap: _openPhotoSheet,
                        cropResult: _cropResult,
                      ),
                    ),
                    SizedBox(height: 25.h),
                    _LabeledField(
                      controller: _firstNameController,
                      hint: 'Имя',
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 28.h),
              child: _PolicyCheckbox(
                value: _agreed,
                onChanged: (bool v) => setState(() => _agreed = v),
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
                label: 'Готово',
                enabled: _isValid,
                onPressed: _isValid
                    ? () {
                        CropResult.saved = _cropResult;
                        CropResult.userName = _firstNameController.text.trim();
                        context.go('/assistant');
                      }
                    : () {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarSlot extends StatelessWidget {
  const _AvatarSlot({required this.onTap, required this.cropResult});
  final VoidCallback onTap;
  final CropResult? cropResult;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          cropResult != null
              ? CroppedAvatar(size: 112.r, cropResult: cropResult)
              : Container(
                  width: 112.r,
                  height: 112.r,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEAEAEA),
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Image.asset(
                    'assets/icons/ui/avatar.webp',
                    fit: BoxFit.cover,
                  ),
                ),
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
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

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
        inputFormatters: [LengthLimitingTextInputFormatter(25)],
        style: AppTextStyles.body.copyWith(
          fontSize: 16.sp,
          color: AppColors.textBlack,
        ),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: AppTextStyles.body.copyWith(
            fontSize: 16.sp,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _PolicyCheckbox extends StatelessWidget {
  const _PolicyCheckbox({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: 3.h),
            child: Image.asset(
              value ? 'assets/icons/ui/check_ok.png' : 'assets/icons/ui/check.webp',
              width: 24.r,
              height: 24.r,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textBlack,
                  fontSize: 12.sp,
                  height: 1.4,
                ),
                children: [
                  const TextSpan(text: 'Я прочитал(а) и согласен(а) с '),
                  TextSpan(
                    text: 'Правилами обработки персональных данных',
                    style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                    recognizer: TapGestureRecognizer()..onTap = () {},
                  ),
                  const TextSpan(text: ', '),
                  TextSpan(
                    text: 'Пользовательским соглашением',
                    style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                    recognizer: TapGestureRecognizer()..onTap = () {},
                  ),
                  const TextSpan(text: ' и '),
                  TextSpan(
                    text: 'Политикой конфиденциальности',
                    style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                    recognizer: TapGestureRecognizer()..onTap = () {},
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

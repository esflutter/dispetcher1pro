import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';

/// Нижняя панель ввода чата: текстовое поле + микрофон + скрепка + send.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onAttach,
    this.onMicTap,
    this.isRecording = false,
    this.showAttach = true,
    this.hint = 'Написать... ',
  });

  final ValueChanged<String> onSend;
  final VoidCallback? onAttach;
  final VoidCallback? onMicTap;
  final bool isRecording;
  final bool showAttach;
  final String hint;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _ctrl = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final has = _ctrl.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _ctrl.clear();
    setState(() => _hasText = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
        decoration: const BoxDecoration(color: AppColors.navBarDark),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: BoxConstraints(minHeight: 44.h),
                padding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: 6.h,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        style: AppTextStyles.body,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: widget.hint,
                          hintStyle: AppTextStyles.body.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                    if (widget.showAttach)
                      _IconBtn(
                        icon: Icons.attach_file,
                        onTap: widget.onAttach,
                        color: AppColors.textSecondary,
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 8.w),
            _SendOrMic(
              hasText: _hasText,
              isRecording: widget.isRecording,
              onSend: _submit,
              onMicTap: widget.onMicTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendOrMic extends StatelessWidget {
  const _SendOrMic({
    required this.hasText,
    required this.isRecording,
    required this.onSend,
    required this.onMicTap,
  });

  final bool hasText;
  final bool isRecording;
  final VoidCallback onSend;
  final VoidCallback? onMicTap;

  @override
  Widget build(BuildContext context) {
    final showSend = hasText;
    return Material(
      color: showSend || isRecording
          ? AppColors.primary
          : AppColors.primaryTint,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: showSend ? onSend : onMicTap,
        child: SizedBox(
          width: 44.w,
          height: 44.w,
          child: Icon(
            showSend ? Icons.send : Icons.mic,
            size: 22.sp,
            color: showSend || isRecording
                ? Colors.white
                : AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, required this.color});

  final IconData icon;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22.r,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
        child: Icon(icon, size: 22.sp, color: color),
      ),
    );
  }
}

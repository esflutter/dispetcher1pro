import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';

/// Нижняя панель ввода чата ассистента.
/// Поддерживает: текст, превью прикреплённых картинок, состояние записи голоса.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onAttach,
    this.onMicTap,
    this.onCancelRecording,
    this.onSendVoice,
    this.onRemovePendingImage,
    this.pendingImages = const <String>[],
    this.isRecording = false,
    this.showAttach = true,
    this.hint = 'Написать...',
  });

  final ValueChanged<String> onSend;
  final VoidCallback? onAttach;
  final VoidCallback? onMicTap;
  final VoidCallback? onCancelRecording;
  final VoidCallback? onSendVoice;
  final ValueChanged<int>? onRemovePendingImage;
  final List<String> pendingImages;
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
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty && widget.pendingImages.isEmpty) return;
    widget.onSend(text);
    _ctrl.clear();
    setState(() => _hasText = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.pendingImages.isNotEmpty && !widget.isRecording)
          _PendingImagesRow(
            images: widget.pendingImages,
            onRemove: widget.onRemovePendingImage,
          ),
        Container(
          color: AppColors.navBarDark,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
              child: widget.isRecording
                  ? _RecordingBar(
                      onCancel: widget.onCancelRecording,
                      onSend: widget.onSendVoice,
                    )
                  : _TextInputBar(
                      controller: _ctrl,
                      hint: widget.hint,
                      hasText: _hasText,
                      showAttach: widget.showAttach,
                      onAttach: widget.onAttach,
                      onSubmit: _submit,
                      onMicTap: widget.onMicTap,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TextInputBar extends StatelessWidget {
  const _TextInputBar({
    required this.controller,
    required this.hint,
    required this.hasText,
    required this.showAttach,
    required this.onAttach,
    required this.onSubmit,
    required this.onMicTap,
  });

  final TextEditingController controller;
  final String hint;
  final bool hasText;
  final bool showAttach;
  final VoidCallback? onAttach;
  final VoidCallback onSubmit;
  final VoidCallback? onMicTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showAttach) ...[
          GestureDetector(
            onTap: onAttach,
            child: Image.asset(
              'assets/icons/support/attach.webp',
              width: 40.h,
              height: 40.h,
            ),
          ),
          SizedBox(width: 16.w),
        ],
        Expanded(
          child: Container(
            height: 40.h,
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSubmit(),
                    textAlignVertical: TextAlignVertical.center,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textBlack,
                      fontSize: 16.sp,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: hint,
                      hintStyle: AppTextStyles.body.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 16.sp,
                      ),
                    ),
                  ),
                ),
                if (!hasText)
                  Transform.translate(
                    offset: Offset(8.w, 0),
                    child: GestureDetector(
                      onTap: onMicTap,
                      child: Padding(
                        padding: EdgeInsets.only(left: 8.w),
                        child: Image.asset(
                          'assets/icons/support/mic.webp',
                          width: 20.r,
                          height: 20.r,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(width: 16.w),
        GestureDetector(
          onTap: onSubmit,
          child: Image.asset(
            'assets/icons/support/send.webp',
            width: 40.h,
            height: 40.h,
          ),
        ),
      ],
    );
  }
}

class _RecordingBar extends StatelessWidget {
  const _RecordingBar({required this.onCancel, required this.onSend});
  final VoidCallback? onCancel;
  final VoidCallback? onSend;

  static const Duration maxDuration = Duration(seconds: 60);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40.h,
            child: _Waveform(
              duration: maxDuration,
              onComplete: onSend,
            ),
          ),
        ),
        SizedBox(width: 16.w),
        GestureDetector(
          onTap: onCancel,
          child: Image.asset(
            'assets/icons/support/cancel.webp',
            width: 40.h,
            height: 40.h,
          ),
        ),
        SizedBox(width: 16.w),
        GestureDetector(
          onTap: onSend,
          child: Image.asset(
            'assets/icons/support/send.webp',
            width: 40.h,
            height: 40.h,
          ),
        ),
      ],
    );
  }
}

class _Waveform extends StatefulWidget {
  const _Waveform({required this.duration, this.onComplete});
  final Duration duration;
  final VoidCallback? onComplete;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete?.call();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        return CustomPaint(
          painter: _WaveformPainter(progress: _progress.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.progress});

  final double progress;

  static const int _barCount = 30;

  // Статичный паттерн высот столбиков (0..1), напоминает референсную картинку
  static final List<double> _heights = List<double>.generate(_barCount, (i) {
    final double a = math.sin(i * 1.3) * 0.5 + 0.5;
    final double b = math.sin(i * 0.55 + 1.1) * 0.5 + 0.5;
    return 0.25 + 0.7 * (0.55 * a + 0.45 * b);
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double slot = size.width / _barCount;
    final double barWidth = slot * 0.63;
    final double midY = size.height / 2;
    final double maxH = size.height * 0.6;

    final orangePaint = Paint()..color = AppColors.primary;
    final whitePaint = Paint()..color = Colors.white;

    final double scaled = progress * _barCount;
    final int fullBars = scaled.floor();
    final double partial = scaled - fullBars;

    for (int i = 0; i < _barCount; i++) {
      final double h = maxH * _heights[i];
      final double x = slot * (i + 0.5);
      final rect = Rect.fromCenter(
        center: Offset(x, midY),
        width: barWidth,
        height: h,
      );
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2));

      if (i < fullBars) {
        canvas.drawRRect(rrect, orangePaint);
      } else if (i == fullBars && partial > 0) {
        canvas.drawRRect(rrect, whitePaint);
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(
          rect.left,
          rect.top,
          rect.left + rect.width * partial,
          rect.bottom,
        ));
        canvas.drawRRect(rrect, orangePaint);
        canvas.restore();
      } else {
        canvas.drawRRect(rrect, whitePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress;
}

class _PendingImagesRow extends StatelessWidget {
  const _PendingImagesRow({required this.images, required this.onRemove});
  final List<String> images;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: SizedBox(
        height: 80.w,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: images.length,
          separatorBuilder: (_, __) => SizedBox(width: 8.w),
          itemBuilder: (context, i) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: () => _showFullscreenImage(context, images[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10.r),
                    child: Image.asset(
                      images[i],
                      width: 80.w,
                      height: 80.w,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 80.w,
                        height: 80.w,
                        color: AppColors.surfaceMuted,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4.w,
                  right: 4.w,
                  child: GestureDetector(
                    onTap: onRemove == null ? null : () => onRemove!(i),
                    child: Image.asset(
                      'assets/icons/support/close_image.webp',
                      width: 24.r,
                      height: 24.r,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showFullscreenImage(BuildContext context, String asset) {
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            color: Colors.black,
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    maxScale: 4.0,
                    child: Image.asset(asset),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  right: 20,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/photo_source.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';
import 'package:dispatcher_1/features/support/widgets/chat_bubble.dart';
import 'package:dispatcher_1/features/support/widgets/chat_input_bar.dart';

/// Экран чата с ИИ-ассистентом «Поддержка».
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.initialMessage});

  final String? initialMessage;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static final List<ChatMessage> _messages = <ChatMessage>[
    const ChatMessage(
      id: 'm1',
      text: 'Здравствуйте! Чем могу помочь?',
      fromUser: false,
    ),
  ];

  static int _idCounter = 0;

  final List<String> _pendingImages = <String>[];
  final ScrollController _scrollController = ScrollController();
  bool _isRecording = false;

  bool get _showQuickActions =>
      _messages.length == 1 && !_messages.first.fromUser && _pendingImages.isEmpty;

  bool _awaitingDocuments = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMessage;
    if (initial != null && initial.trim().isNotEmpty) {
      if (initial.trim() == 'verify_documents') {
        _awaitingDocuments = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _messages.add(ChatMessage(
              id: _nextId(),
              text: 'Отправьте, пожалуйста, фото документов, чтобы мы могли '
                  'подтвердить ваш профиль:\n\n'
                  '• ФИО или название организации\n'
                  '• Паспорт (первая страница)\n'
                  '• Фото техники\n'
                  '• Документы на технику\n'
                  '• Удостоверение на право управления техникой\n'
                  '• Водительское удостоверение\n\n'
                  'Можно отправить всё одним сообщением или по отдельности.',
              fromUser: false,
            ));
            _scrollToBottom();
          });
        });
      } else if (initial.trim() == 'create_service') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _messages.add(ChatMessage(
              id: _nextId(),
              text: 'Опишите услугу — текстом или голосом, я заполню всё за вас',
              fromUser: false,
            ));
            _scrollToBottom();
          });
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleSend(initial.trim());
        });
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  String _nextId() {
    _idCounter += 1;
    return 'm${DateTime.now().millisecondsSinceEpoch}_$_idCounter';
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleSend(String text) {
    final hasImages = _pendingImages.isNotEmpty;
    if (text.isEmpty && !hasImages) return;

    setState(() {
      if (hasImages) {
        if (_awaitingDocuments) {
          VerificationStatus.current = VerificationStatus.inProgress;
        }
        _messages.add(
          ChatMessage(
            id: _nextId(),
            text: '',
            fromUser: true,
            type: ChatMessageType.image,
            imageAssets: List<String>.from(_pendingImages),
          ),
        );
        _pendingImages.clear();
      }
      if (text.isNotEmpty) {
        _messages.add(
          ChatMessage(id: _nextId(), text: text, fromUser: true),
        );
      }
      _scrollToBottom();
    });

    // Заглушка ответа ассистента
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() {
        if (_awaitingDocuments && hasImages) {
          _awaitingDocuments = false;
          _messages.add(
            ChatMessage(
              id: _nextId(),
              text: 'Документы отправлены 👍\n'
                  'Результат проверки появится в профиле.\n'
                  'Мы также пришлём уведомление.',
              fromUser: false,
            ),
          );
        } else if (text.toLowerCase().contains('экскават')) {
          _messages.add(
            ChatMessage(
              id: _nextId(),
              text: 'В каком городе вы ищите заказ?',
              fromUser: false,
            ),
          );
        } else {
          _messages.add(
            ChatMessage(
              id: _nextId(),
              text: 'Спасибо! Я уточню детали и вернусь с ответом.',
              fromUser: false,
            ),
          );
        }
        _scrollToBottom();
      });
    });
  }

  Future<void> _handleAttach() async {
    final int remaining = 8 - _pendingImages.length;
    if (remaining <= 0) return;
    final List<String> picked =
        await pickMultipleImagesFromGallery(limit: remaining, context: context);
    if (picked.isEmpty || !mounted) return;
    final List<String> kept =
        picked.length > remaining ? picked.sublist(0, remaining) : picked;
    setState(() => _pendingImages.addAll(kept));
    if (picked.length > remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Можно добавить не более 8 фото. Добавлены первые ${kept.length}.',
          ),
        ),
      );
    }
  }

  void _removePendingImage(int index) {
    setState(() => _pendingImages.removeAt(index));
  }

  void _toggleRecording() {
    setState(() => _isRecording = !_isRecording);
  }

  void _cancelRecording() {
    setState(() => _isRecording = false);
  }

  void _sendVoice() {
    setState(() {
      _isRecording = false;
      _messages.add(
        ChatMessage(
          id: _nextId(),
          text: '*Текст голосового сообщения*',
          fromUser: true,
        ),
      );
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Padding(
          padding: EdgeInsets.only(top: 4.h),
          child: Text(
            'Поддержка',
            style: AppTextStyles.h3.copyWith(
              color: AppColors.textBlack,
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 4.w),
            child: IconButton(
              padding: EdgeInsets.only(top: 4.h),
              icon: Image.asset('assets/icons/support/close.webp', width: 26.r, height: 26.r),
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  context.go('/shell');
                }
              },
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1.h),
          child: Container(height: 1.h, color: AppColors.divider),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
              itemCount: _messages.length,
              separatorBuilder: (_, _) => SizedBox.shrink(),
              itemBuilder: (context, index) {
                return ChatBubble(message: _messages[index]);
              },
            ),
          ),
          if (_showQuickActions)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 54.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QuickActionChip(
                    label: 'Разместить услугу',
                    onTap: () => _handleSend('Разместить услугу'),
                  ),
                  SizedBox(height: 8.h),
                  _QuickActionChip(
                    label: 'Создать карточку исполнителя',
                    onTap: () => _handleSend('Создать карточку исполнителя'),
                  ),
                ],
              ),
              ),
            ),
          ChatInputBar(
            isRecording: _isRecording,
            pendingImages: _pendingImages,
            onRemovePendingImage: _removePendingImage,
            onSend: _handleSend,
            onAttach: _handleAttach,
            onMicTap: _toggleRecording,
            onCancelRecording: _cancelRecording,
            onSendVoice: _sendVoice,
          ),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8.r),
          child: Container(
            height: 36.h,
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(
                color: Colors.white,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

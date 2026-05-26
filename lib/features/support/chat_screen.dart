import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/ai/ai_client.dart';
import 'package:dispatcher_1/core/ai/stt_recorder.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/photo_source.dart';
import 'package:dispatcher_1/features/profile/widgets/verification_badge.dart';
import 'package:dispatcher_1/features/support/widgets/chat_bubble.dart';
import 'package:dispatcher_1/features/support/widgets/chat_input_bar.dart';

/// Экран чата с ИИ-ассистентом «Поддержка».
///
/// Поддерживает 3 режима:
///   - chat              — обычный FAQ / общий разговор (по умолчанию)
///   - slotFillService   — создание услуги пошагово (initialMessage='create_service')
///   - search            — поиск заказов по описанию (через quick action или
///                         когда юзер пишет «найди заказы…»)
///
/// Для `initialMessage='verify_documents'` — отдельный flow отправки фото
/// документов (на сервер пишет profiles.verification_status='pending').
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.initialMessage});

  final String? initialMessage;

  /// Сбрасывает историю чата к начальному приветствию.
  /// Вызывается при logout/удалении аккаунта.
  static void resetHistory() {
    _ChatScreenState.resetHistory();
    AiClient.instance.resetSessions();
  }

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  // Статичное хранилище сообщений — между переходами по экранам
  // история не сбрасывается. Очищается только из resetHistory()
  // (logout / удаление аккаунта).
  static final List<ChatMessage> _messages = <ChatMessage>[
    const ChatMessage(
      id: 'm1',
      text: 'Здравствуйте! Я помогу найти заказы, создать услугу, заполнить '
            'карточку или ответить на вопрос по приложению. С чего начнём?',
      fromUser: false,
    ),
  ];

  static AiChatKind _mode = AiChatKind.chat;
  static int _idCounter = 0;

  static void resetHistory() {
    _messages
      ..clear()
      ..add(const ChatMessage(
        id: 'm1',
        text: 'Здравствуйте! Я помогу найти заказы, создать услугу, заполнить '
              'карточку или ответить на вопрос по приложению. С чего начнём?',
        fromUser: false,
      ));
    _mode = AiChatKind.chat;
    _idCounter = 0;
  }

  final List<String> _pendingImages = <String>[];
  final ScrollController _scrollController = ScrollController();
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _awaitingDocuments = false;
  /// Защёлка от двойного тапа по микрофону / автостопа + ручной отправки
  /// одновременно. Сбрасывается после завершения операции.
  bool _voiceBusy = false;

  bool get _showQuickActions =>
      _messages.length == 1 && !_messages.first.fromUser && _pendingImages.isEmpty && !_isProcessing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initial = widget.initialMessage?.trim();
    if (initial == null || initial.isEmpty) {
      // Открытие чата без intent — это «обычный разговор». Сбрасываем
      // режим, иначе предыдущий slot-fill / search режим залипает и
      // следующее сообщение пойдёт не в ai-chat.
      _mode = AiChatKind.chat;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: true));
      return;
    }

    if (initial == 'verify_documents') {
      _awaitingDocuments = true;
      _addBotMessage(
        'Отправьте, пожалуйста, фото документов, чтобы мы могли '
        'подтвердить ваш профиль:\n\n'
        '• ФИО или название организации\n'
        '• Паспорт (первая страница)\n'
        '• Фото техники\n'
        '• Документы на технику\n'
        '• Удостоверение на право управления техникой\n'
        '• Водительское удостоверение\n\n'
        'Можно отправить всё одним сообщением или по отдельности.',
      );
      return;
    }

    if (initial == 'create_service' || initial == 'Разместить услугу') {
      _mode = AiChatKind.slotFillService;
      _addBotMessage('Опишите услугу — текстом или голосом, я заполню всё за вас.');
      return;
    }

    if (initial == 'find_orders' || initial == 'Найти заказы') {
      _mode = AiChatKind.search;
      _addBotMessage('Опишите какой заказ ищете — техника, регион, даты.');
      return;
    }

    // Любой другой initial = реальный запрос юзера, отправляем как chat.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mode = AiChatKind.chat;
      _handleSend(initial);
    });
  }

  void _addBotMessage(String text, {Map<String, dynamic>? data, ChatMessageType type = ChatMessageType.text}) {
    // Если экран уже не активен (юзер ушёл, пока шёл LLM-запрос) — всё равно
    // добавляем сообщение в статичный список, чтобы при возврате юзер его увидел.
    // setState вызываем только когда mounted, иначе будет исключение.
    final msg = ChatMessage(
      id:   _nextId(),
      text: text,
      fromUser: false,
      type: type,
      data: data,
    );
    if (!mounted) {
      _messages.add(msg);
      return;
    }
    setState(() => _messages.add(msg));
    _scrollToBottom();
  }

  String _nextId() {
    _idCounter += 1;
    return 'm${DateTime.now().millisecondsSinceEpoch}_$_idCounter';
  }

  void _scrollToBottom({bool jump = false}) {
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: jump));
      return;
    }
    final pos = _scrollController.position.maxScrollExtent;
    if (jump) {
      _scrollController.jumpTo(pos);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _handleSend(String text) async {
    final hasImages = _pendingImages.isNotEmpty;
    if (text.isEmpty && !hasImages) return;
    if (_isProcessing) return;

    setState(() {
      if (hasImages) {
        if (_awaitingDocuments) {
          VerificationStatus.current = VerificationStatus.inProgress;
        }
        _messages.add(ChatMessage(
          id:   _nextId(),
          text: '',
          fromUser: true,
          type: ChatMessageType.image,
          imageAssets: List<String>.from(_pendingImages),
        ));
        _pendingImages.clear();
      }
      if (text.isNotEmpty) {
        _messages.add(ChatMessage(id: _nextId(), text: text, fromUser: true));
      }
    });
    _scrollToBottom();

    // Отправка документов (отдельный flow, без LLM).
    if (_awaitingDocuments && hasImages) {
      _awaitingDocuments = false;
      _addBotMessage(
        'Документы отправлены 👍\n'
        'Результат проверки появится в профиле.\n'
        'Мы также пришлём уведомление.',
      );
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          await Supabase.instance.client
              .from('profiles')
              .update(<String, dynamic>{'verification_status': 'pending'})
              .eq('id', user.id);
          VerificationStatus.current = VerificationStatus.inProgress;
        }
      } catch (_) {/* silent */}
      return;
    }

    if (text.isEmpty) return;
    await _sendToAssistant(text);
  }

  Future<void> _sendToAssistant(String text) async {
    setState(() => _isProcessing = true);
    _scrollToBottom();
    // Таймаут 30 сек: иначе спиннер «печатает...» крутится бесконечно на
    // подвисшей сети / Edge Function. YandexGPT обычно укладывается в 5-10 сек.
    const Duration timeout = Duration(seconds: 30);
    try {
      Future<AiReply> call() {
        switch (_mode) {
          case AiChatKind.search:
            return AiClient.instance.search(text);
          case AiChatKind.slotFillService:
            return AiClient.instance.slotFillService(text);
          case AiChatKind.slotFillOrder:
          case AiChatKind.chat:
            return AiClient.instance.chat(text);
        }
      }
      final reply = await call().timeout(timeout);
      _appendReply(reply);
    } on AiQuotaExceeded catch (e) {
      _addBotMessage(e.message);
    } on AiContentFilterError catch (e) {
      _addBotMessage(e.message);
    } on TimeoutException {
      _addBotMessage('Не дождался ответа. Попробуйте ещё раз.');
    } catch (_) {
      _addBotMessage(
        'Не удалось получить ответ. Проверьте интернет и попробуйте снова.',
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _appendReply(AiReply reply) {
    final kind = reply.dataKind;
    if (kind == 'order_cards' && reply.items.isNotEmpty) {
      _addBotMessage(reply.text, type: ChatMessageType.orderCards, data: reply.data);
      return;
    }
    if (kind == 'executor_cards' && reply.items.isNotEmpty) {
      _addBotMessage(reply.text, type: ChatMessageType.executorCards, data: reply.data);
      return;
    }
    if ((kind == 'order_draft' || kind == 'service_draft') && reply.isDraftReady) {
      _addBotMessage(reply.text, type: ChatMessageType.draftReady, data: reply.data);
      return;
    }
    // slot_progress / error / обычный текст
    _addBotMessage(reply.text);
  }

  Future<void> _handleAttach() async {
    final int remaining = 8 - _pendingImages.length;
    if (remaining <= 0) return;
    final picked = await pickMultipleImagesFromGallery(limit: remaining, context: context);
    if (picked.isEmpty || !mounted) return;
    final kept = picked.length > remaining ? picked.sublist(0, remaining) : picked;
    setState(() => _pendingImages.addAll(kept));
    if (picked.length > remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          'Можно добавить не более 8 фото. Добавлены первые ${kept.length}.',
        )),
      );
    }
  }

  void _removePendingImage(int index) {
    setState(() => _pendingImages.removeAt(index));
  }

  Future<void> _toggleRecording() async {
    if (_voiceBusy) return;
    _voiceBusy = true;
    try {
      if (_isRecording) {
        await _cancelRecording();
        return;
      }
      await _startRecording();
    } finally {
      _voiceBusy = false;
    }
  }

  Future<void> _startRecording() async {
    final granted = await SttRecorder.instance.ensurePermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Нет доступа к микрофону.'),
        action: SnackBarAction(
          label: 'Настройки',
          onPressed: () => SttRecorder.instance.openSettings(),
        ),
      ));
      return;
    }
    final started = await SttRecorder.instance.start();
    if (!started) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось начать запись')),
        );
      }
      return;
    }
    // Колбэк ставим ПОСЛЕ успешного start (иначе предыдущий таймер мог бы
    // дотикать на этом колбэке, если запись из прошлого экрана не отменилась).
    SttRecorder.instance.onAutoStop = () {
      if (!mounted || !_isRecording) return;
      _sendVoice();
    };
    if (mounted) setState(() => _isRecording = true);
  }

  Future<void> _cancelRecording() async {
    // Снимаем колбэк ДО cancel, чтобы таймер, выстреливший в эту же
    // миллисекунду, не отправил уже отменяемую запись.
    SttRecorder.instance.onAutoStop = null;
    await SttRecorder.instance.cancel();
    if (mounted) setState(() => _isRecording = false);
  }

  Future<void> _sendVoice() async {
    // Защёлка: и автостоп, и ручная отправка могут дёрнуть _sendVoice
    // почти одновременно — пускаем строго один раз.
    if (!_isRecording) return;
    // Сразу обнуляем флаг записи и колбэк автостопа, чтобы повторный
    // вход (от автостопа в ту же миллисекунду) увидел !_isRecording.
    SttRecorder.instance.onAutoStop = null;
    if (mounted) setState(() => _isRecording = false);

    final File? audio = await SttRecorder.instance.stop();
    if (audio == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Слишком короткое сообщение — задержите кнопку микрофона')),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);
    String? errorMsg;
    String? recognized;
    try {
      recognized = await AiClient.instance.transcribeAudio(audio);
    } on AiQuotaExceeded catch (e) {
      errorMsg = e.message;
    } on AiAudioTooLargeError {
      errorMsg = 'Слишком длинное сообщение — больше минуты.';
    } on AiAudioNoSpeechError {
      errorMsg = 'Не услышал речи — попробуйте ещё раз, поближе к микрофону.';
    } on AiAudioInvalidFormatError {
      errorMsg = 'Запись в неподдерживаемом формате. Напишите, пожалуйста, текстом.';
    } catch (_) {
      errorMsg = 'Не удалось распознать голос. Проверьте интернет.';
    }
    try { await audio.delete(); } catch (_) {}

    if (!mounted) return;
    if (errorMsg != null || recognized == null || recognized.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg ?? 'Не удалось распознать речь')),
      );
      setState(() => _isProcessing = false);
      return;
    }
    // Распознанный текст показываем как сообщение юзера и шлём ассистенту.
    setState(() {
      _messages.add(ChatMessage(id: _nextId(), text: recognized!, fromUser: true));
    });
    _scrollToBottom();
    // Лимитируем длину распознанного текста — текстовый инпут тоже ограничен 1000.
    final String capped = recognized.length > 1000 ? recognized.substring(0, 1000) : recognized;
    await _sendToAssistant(capped);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Уход в фон во время записи — корректно отменяем (иначе таймер
    // дотикает в фоне, файл осиротеет, при возврате — рассинхрон UI).
    if (state == AppLifecycleState.paused && _isRecording) {
      SttRecorder.instance.cancel();
      if (mounted) setState(() => _isRecording = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Закрытие экрана с активной записью — обязательно отменяем, иначе
    // запись продолжится «в фоне», onAutoStop выстрелит на удалённом state.
    if (_isRecording) {
      SttRecorder.instance.cancel();
    }
    SttRecorder.instance.onAutoStop = null;
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
              itemCount: _messages.length + (_isProcessing ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox.shrink(),
              itemBuilder: (context, index) {
                if (index < _messages.length) {
                  return ChatBubble(message: _messages[index]);
                }
                return const TypingBubble();
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
                      onTap: () {
                        _mode = AiChatKind.slotFillService;
                        _addBotMessage('Опишите услугу — текстом или голосом, я заполню всё за вас.');
                      },
                    ),
                    SizedBox(height: 8.h),
                    _QuickActionChip(
                      label: 'Найти заказы',
                      onTap: () {
                        _mode = AiChatKind.search;
                        _addBotMessage('Опишите какой заказ ищете — техника, регион, даты. Можно голосом.');
                      },
                    ),
                    SizedBox(height: 8.h),
                    _QuickActionChip(
                      label: 'Заполнить карточку',
                      onTap: () {
                        _mode = AiChatKind.chat;
                        _handleSend('Как заполнить карточку исполнителя?');
                      },
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

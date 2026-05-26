import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/photo_source.dart';
import 'package:dispatcher_1/features/services/create_service_screen.dart';

enum ChatMessageType { text, image, orderCards, executorCards, draftReady }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.fromUser,
    this.type = ChatMessageType.text,
    this.imageAssets = const <String>[],
    this.data,
  });

  final String id;
  final String text;
  final bool fromUser;
  final ChatMessageType type;
  final List<String> imageAssets;
  /// Для handoff-сообщений (order_cards / executor_cards / draftReady).
  ///   - orderCards:  { items: [ {id, title, address, date_from, ...}, ... ] }
  ///   - executorCards: { items: [ {user_id, name, rating, location_address, ...}, ... ] }
  ///   - draftReady:  { kind: "order_draft" | "service_draft", draft: {...} }
  final Map<String, dynamic>? data;
}

/// Пузырь сообщения. Входящие — кремовый primaryTint слева,
/// исходящие — оранжевый primary справа.
class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.fromUser;
    final bg = isUser ? AppColors.primary : AppColors.primaryTint;
    final fg = isUser ? Colors.white : AppColors.textBlack;

    if (message.type == ChatMessageType.orderCards) {
      return _OrderCardsHandoff(text: message.text, data: message.data ?? const {});
    }
    if (message.type == ChatMessageType.executorCards) {
      return _ExecutorCardsHandoff(text: message.text, data: message.data ?? const {});
    }
    if (message.type == ChatMessageType.draftReady) {
      return _DraftReadyHandoff(text: message.text, data: message.data ?? const {});
    }

    if (message.type == ChatMessageType.image) {
      return Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: 312.w), // 88*3 + 8*2 + 16*2
          margin: EdgeInsets.symmetric(vertical: 8.h),
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16.r),
          ),
          child: Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final asset in message.imageAssets)
                GestureDetector(
                  onTap: () => _showFullscreenImage(context, asset),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.r),
                    child: isAssetPath(asset)
                        ? Image.asset(
                            asset,
                            width: 88.r,
                            height: 88.r,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _ThumbError(),
                          )
                        : Image.file(
                            File(asset),
                            width: 88.r,
                            height: 88.r,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _ThumbError(),
                          ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: 280.w),
        margin: EdgeInsets.symmetric(vertical: 8.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Text(
          message.text,
          style: AppTextStyles.body.copyWith(
            color: fg,
            fontSize: 16.sp,
            height: 1.25,
          ),
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
                    child: isAssetPath(asset)
                        ? Image.asset(asset)
                        : Image.file(File(asset)),
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

/// Плитка-плейсхолдер для не подгруженных миниатюр в чате.
class _ThumbError extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88.r,
      height: 88.r,
      color: AppColors.surfaceMuted,
      child: Icon(Icons.image_outlined,
          color: AppColors.textTertiary, size: 32.r),
    );
  }
}

// ============================================================
// Handoff-виджеты — найденные карточки и готовые черновики.
// ============================================================

/// Карточки заказов от ассистента — для исполнителя.
class _OrderCardsHandoff extends StatelessWidget {
  const _OrderCardsHandoff({required this.text, required this.data});
  final String text;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final items = (data['items'] is List ? data['items'] as List : const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: 312.w),
        margin: EdgeInsets.symmetric(vertical: 8.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (text.isNotEmpty) ...[
              Text(
                text,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textBlack,
                  fontSize: 16.sp,
                  height: 1.25,
                ),
              ),
              SizedBox(height: 12.h),
            ],
            // Фильтруем карточки без id — иначе пользователь видит их, но
            // они не кликабельны (silent dead UI). Лучше скрыть совсем.
            ...items
                .where((it) => (it['id'] as String? ?? '').isNotEmpty)
                .take(5)
                .map((it) => _OrderTile(item: it)),
            if (items.length > 5)
              Padding(
                padding: EdgeInsets.only(top: 8.h),
                child: Text(
                  'И ещё ${items.length - 5} — введите запрос точнее, чтобы их сузить.',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 13.sp,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final id      = item['id']      as String? ?? '';
    final title   = (item['title']  as String? ?? '').trim();
    final address = (item['address']as String? ?? '').trim();
    final dateFrom = item['date_from'] as String?;
    final distance = item['distance_km'];
    return InkWell(
      // В executor-приложении /orders/:id — это «мои отклики», а нам нужна
      // публичная карточка заказа из каталога: /catalog/order/:id.
      onTap: id.isEmpty ? null : () => context.push('/catalog/order/$id'),
      borderRadius: BorderRadius.circular(10.r),
      child: Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title.isEmpty ? 'Заказ' : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textBlack,
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (address.isNotEmpty) ...[
              SizedBox(height: 4.h),
              Text(
                address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 12.sp,
                ),
              ),
            ],
            if (dateFrom != null || distance != null) ...[
              SizedBox(height: 4.h),
              Text(
                [
                  if (dateFrom != null) 'с $dateFrom',
                  if (distance != null) '~ $distance км',
                ].join(' • '),
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 12.sp,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Карточки исполнителей — для заказчика. (Используется только в customer-приложении,
/// но дублирование класса в обоих приложениях избегаем — храним общий код.)
class _ExecutorCardsHandoff extends StatelessWidget {
  const _ExecutorCardsHandoff({required this.text, required this.data});
  final String text;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    // В приложении исполнителя этот режим не используется (executor ищет заказы,
    // а не людей), но виджет компилируется на случай переиспользования.
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: 280.w),
        margin: EdgeInsets.symmetric(vertical: 8.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Text(text,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textBlack, fontSize: 16.sp, height: 1.25,
            )),
      ),
    );
  }
}

/// Готовый черновик — кнопка «Открыть форму создания».
class _DraftReadyHandoff extends StatelessWidget {
  const _DraftReadyHandoff({required this.text, required this.data});
  final String text;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final kind  = data['kind']  as String? ?? '';
    final draft = data['draft'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final isService = kind == 'service_draft';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: 312.w),
        margin: EdgeInsets.symmetric(vertical: 8.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (text.isNotEmpty) ...[
              Text(text,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textBlack, fontSize: 16.sp, height: 1.25,
                ),
              ),
              SizedBox(height: 12.h),
            ],
            Text(
              isService ? 'Черновик услуги готов' : 'Черновик заказа готов',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textBlack, fontSize: 14.sp, fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              isService
                  ? 'Откройте форму услуги — проверьте поля и опубликуйте.'
                  : 'Откройте форму заказа — проверьте поля и опубликуйте.',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textTertiary, fontSize: 13.sp,
              ),
            ),
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // Защита от пустого draft: иначе откроется форма без полей,
                  // и юзер может случайно опубликовать заглушку.
                  if (draft.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Черновик пуст — расскажите подробнее ассистенту.')),
                    );
                    return;
                  }
                  if (isService) {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => CreateServiceScreen(aiDraft: draft),
                    ));
                  } else {
                    // В executor-приложении заказы не создают — на всякий
                    // случай (если LLM вернёт order_draft) показываем сообщение.
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Этот тип черновика недоступен в приложении исполнителя')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                ),
                child: Text(
                  isService ? 'Открыть форму услуги' : 'Открыть форму заказа',
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Индикатор «печатает…» — три точки в кремовом пузыре.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = ((_c.value * 3) - i).clamp(0.0, 1.0);
                final scale = 0.6 + 0.4 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3.w),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 8.r,
                      height: 8.r,
                      decoration: const BoxDecoration(
                        color: AppColors.textTertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

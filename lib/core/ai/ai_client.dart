// =====================================================================
// ai_client.dart — клиент для Edge Functions ИИ-ассистента.
//
// Обёртка над Supabase Functions client. Хранит session_id для каждого
// типа чата (chat / search / slot_fill), чтобы история сохранялась
// между сообщениями.
//
// Используется из chat_screen.dart и других UI-точек, где есть
// взаимодействие с ассистентом.
// =====================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Тип чата с ассистентом — определяет какая Edge Function вызывается.
enum AiChatKind { chat, search, slotFillOrder, slotFillService }

/// Результат одного обмена с ассистентом.
@immutable
class AiReply {
  const AiReply({
    required this.sessionId,
    required this.text,
    this.data,
    this.error,
    this.quota,
    this.cached = false,
  });

  final String sessionId;
  final String text;
  final Map<String, dynamic>? data;
  final String? error;
  final AiQuota? quota;
  final bool cached;

  /// Поле data.kind показывает, как клиент должен отрисовать ответ:
  ///   - null / "" — обычный текст
  ///   - "order_cards"     — массив заказов в data.items
  ///   - "executor_cards"  — массив исполнителей
  ///   - "order_draft"     — готовый черновик заказа (handoff)
  ///   - "service_draft"   — готовый черновик услуги (handoff)
  ///   - "slot_progress"   — slot-fill ещё не закончен
  ///   - "error"           — текст содержит дружелюбное сообщение
  String? get dataKind => data?['kind'] as String?;

  /// Найденные id (для order_cards/executor_cards).
  List<String> get itemIds {
    final ids = data?['ids'];
    if (ids is List) return ids.whereType<String>().toList(growable: false);
    return const <String>[];
  }

  /// Готов ли slot-fill draft (для kind == order_draft / service_draft / slot_progress).
  bool get isDraftReady => (data?['ready'] as bool?) ?? false;

  Map<String, dynamic>? get draft {
    final d = data?['draft'];
    if (d is Map<String, dynamic>) return d;
    return null;
  }

  /// Полные данные карточек заказов / исполнителей.
  List<Map<String, dynamic>> get items {
    final raw = data?['items'];
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }
}

@immutable
class AiQuota {
  const AiQuota({required this.used, required this.total});
  final int used;
  final int total;
  int get left => (total - used).clamp(0, total);
}

/// Исключение «лимит запросов исчерпан».
class AiQuotaExceeded implements Exception {
  AiQuotaExceeded(this.message);
  final String message;
  @override
  String toString() => 'AiQuotaExceeded: $message';
}

/// Исключение «фильтр контента» — мягкое сообщение для пользователя.
class AiContentFilterError implements Exception {
  AiContentFilterError(this.message);
  final String message;
  @override
  String toString() => 'AiContentFilterError: $message';
}

class AiClient {
  AiClient._({required this.app});
  static final AiClient instance = AiClient._(app: 'executor');

  /// Какое приложение шлёт запросы — серверная часть выбирает правильный
  /// системный промпт и фильтрует данные.
  final String app;

  SupabaseClient get _sb => Supabase.instance.client;

  // Кэшируем session_id отдельно для каждого типа чата, чтобы переключение
  // между ассистентом-чатом и ассистентом-поиском не теряло историю.
  final Map<AiChatKind, String?> _sessionIds = <AiChatKind, String?>{};

  /// Сбрасывает все session_id (вызывается из auth_reset при logout).
  void resetSessions() {
    _sessionIds.clear();
  }

  Future<AiReply> chat(String message) =>
      _invoke('ai-chat', message, AiChatKind.chat, null);

  Future<AiReply> search(String message) =>
      _invoke('ai-search', message, AiChatKind.search, null);

  Future<AiReply> slotFillOrder(String message) =>
      _invoke('ai-slot-fill', message, AiChatKind.slotFillOrder, 'create_order');

  Future<AiReply> slotFillService(String message) =>
      _invoke('ai-slot-fill', message, AiChatKind.slotFillService, 'create_service');

  Future<AiReply> _invoke(
    String functionName,
    String message,
    AiChatKind kind,
    String? intent,
  ) async {
    final body = <String, dynamic>{
      'message': message,
      'app':     app,
      'session_id': ?_sessionIds[kind],
      'intent':     ?intent,
    };

    try {
      final FunctionResponse res = await _sb.functions.invoke(
        functionName,
        body: body,
      );
      final status = res.status;
      final data   = res.data;
      final Map<String, dynamic> json = data is Map<String, dynamic>
          ? data
          : <String, dynamic>{};

      // 402 — лимит запросов
      if (status == 402) {
        throw AiQuotaExceeded(json['message'] as String? ?? 'Лимит исчерпан');
      }
      // 422 — фильтр контента (сообщение для юзера, как обычный ответ)
      if (status == 422 || (json['error'] == 'content_filter')) {
        throw AiContentFilterError(
          json['message'] as String? ?? 'Не удалось обработать запрос',
        );
      }
      // 503 — глобальный дневной бюджет исчерпан (защита от наплыва)
      if (status == 503) {
        throw AiQuotaExceeded(
          'Ассистент сейчас перегружен. Попробуйте через несколько минут.',
        );
      }
      if (status >= 400) {
        throw Exception('ai-$functionName failed: status=$status, error=${json['error']}');
      }

      final reply = AiReply(
        sessionId: json['session_id'] as String? ?? '',
        text:      json['reply']      as String? ?? '',
        data:      json['data']       as Map<String, dynamic>?,
        cached:    json['cached']     as bool?   ?? false,
        quota: json['quota'] is Map<String, dynamic>
            ? AiQuota(
                used:  (json['quota']['used']  as num? ?? 0).toInt(),
                total: (json['quota']['total'] as num? ?? 0).toInt(),
              )
            : null,
      );

      if (reply.sessionId.isNotEmpty) {
        _sessionIds[kind] = reply.sessionId;
      }
      return reply;
    } on AiQuotaExceeded {
      rethrow;
    } on AiContentFilterError {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('[ai-client] $functionName failed: $e');
      rethrow;
    }
  }

  /// Распознавание голоса через stt-yandex.
  /// Принимает файл с записью (формат OGG/Opus 16k mono — оптимально).
  ///
  /// Бросает:
  ///  - [AiQuotaExceeded] если дневной лимит юзера исчерпан;
  ///  - [AiAudioTooLargeError] если файл больше 1 МБ;
  ///  - [AiAudioNoSpeechError] если SpeechKit не услышал речи;
  ///  - [Exception] на прочие ошибки сети / API.
  Future<String> transcribeAudio(File audio, {String format = 'oggopus'}) async {
    final bytes = await audio.readAsBytes();
    try {
      final FunctionResponse res = await _sb.functions.invoke(
        'stt-yandex',
        method:        HttpMethod.post,
        body:          bytes,
        queryParameters: <String, dynamic>{ 'format': format },
      );
      final status = res.status;
      final data   = res.data;
      final Map<String, dynamic> json = data is Map<String, dynamic>
          ? data
          : <String, dynamic>{};

      if (status == 402) {
        throw AiQuotaExceeded(json['message'] as String? ?? 'Лимит исчерпан');
      }
      if (status == 413 || json['error'] == 'audio_too_large') {
        throw AiAudioTooLargeError();
      }
      if (status == 422 && json['error'] == 'no_speech') {
        throw AiAudioNoSpeechError();
      }
      if (status == 422 && json['error'] == 'invalid_format') {
        throw AiAudioInvalidFormatError();
      }
      if (status == 422) {
        // audio_too_short и прочие — общая ветка
        throw AiAudioNoSpeechError();
      }
      if (status == 500 && json['error'] == 'stt_auth_error') {
        // Серверная проблема, не интернет
        throw Exception('Ассистент временно недоступен (auth).');
      }
      if (status >= 400) {
        throw Exception('stt-yandex failed: status=$status, error=${json['error']}');
      }
      if (json['text'] is String) {
        return (json['text'] as String).trim();
      }
      return '';
    } on AiQuotaExceeded {
      rethrow;
    } on AiAudioTooLargeError {
      rethrow;
    } on AiAudioNoSpeechError {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('[ai-client] transcribe failed: $e');
      rethrow;
    }
  }
}

/// Запись больше 1 МБ — SpeechKit sync API не примет.
class AiAudioTooLargeError implements Exception {
  @override
  String toString() => 'AiAudioTooLargeError';
}

/// SpeechKit вернул пустой результат — речи в записи не было.
class AiAudioNoSpeechError implements Exception {
  @override
  String toString() => 'AiAudioNoSpeechError';
}

/// SpeechKit отверг формат (например, AAC вместо Opus на старых Xiaomi).
class AiAudioInvalidFormatError implements Exception {
  @override
  String toString() => 'AiAudioInvalidFormatError';
}

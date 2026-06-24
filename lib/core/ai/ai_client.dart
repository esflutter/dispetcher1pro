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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dispatcher_1/core/ai/device_id.dart';
import 'package:dispatcher_1/core/config/env.dart';
import 'package:dispatcher_1/core/user_location.dart';

/// Тип чата с ассистентом — определяет какая Edge Function вызывается.
enum AiChatKind { chat, search, slotFillOrder, slotFillService, slotFillCard }

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
    this.nav,
  });

  final String sessionId;
  final String text;
  final Map<String, dynamic>? data;
  final String? error;
  final AiQuota? quota;
  final bool cached;
  /// Подсказка перехода в раздел (кнопка «Перейти» под ответом).
  final AiNav? nav;

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

/// Подсказка перехода в раздел приложения — кнопка «Перейти» под ответом.
/// action — стабильный ключ от сервера; UI сам сопоставляет его с экраном.
@immutable
class AiNav {
  const AiNav({required this.action, required this.label});
  final String action;
  final String label;

  static AiNav? fromJson(dynamic j) {
    if (j is Map && j['action'] is String && j['label'] is String) {
      return AiNav(action: j['action'] as String, label: j['label'] as String);
    }
    return null;
  }
}

/// Один chunk потока ответа ассистента в стриминговом режиме.
@immutable
class AiChatChunk {
  const AiChatChunk({
    required this.text,
    required this.delta,
    required this.done,
    this.quota,
    this.nav,
  });

  /// Полный накопленный текст к моменту chunk'а.
  final String text;
  /// Новые символы, добавленные этим chunk'ом.
  final String delta;
  /// true для финального chunk'а — на нём заполнены quota и nav.
  final bool done;
  final AiQuota? quota;
  /// Подсказка перехода (приходит только на done-chunk'е, если сервер прислал).
  final AiNav? nav;
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

  // session_id по «корзинам» диалога. Беседа и поиск — ОДИН разговор с
  // общей памятью: им соответствует один session_id (корзина chat), чтобы
  // при переключении между «найди заказы» и обычным вопросом ассистент
  // помнил всю нить и не здоровался заново. Slot-fill держит свою сессию —
  // его пошаговый state не должен смешиваться с беседой/поиском.
  final Map<AiChatKind, String?> _sessionIds = <AiChatKind, String?>{};

  AiChatKind _sessionBucket(AiChatKind kind) =>
      (kind == AiChatKind.chat || kind == AiChatKind.search)
          ? AiChatKind.chat
          : kind;

  /// Сбрасывает все session_id (вызывается из auth_reset при logout).
  void resetSessions() {
    _sessionIds.clear();
    _lastSlotSessionId = null;
    unawaited(_clearPersistedSession());
  }

  // --- Персистентность разговора: чтобы история чата пережила перезапуск
  // приложения. Храним только session_id; сами сообщения берём из БД
  // (ai_messages, доступ по RLS «только свои сессии»). ---
  static const String _kChatSessionKey = 'ai_chat_session_id';
  // Сессия пошагового создания услуги (slot-fill) отдельная от чата. Храним её
  // id, чтобы при перезапуске показать в истории и эту часть разговора (а не
  // только обычный чат). Используется ТОЛЬКО для показа истории — в активную
  // «корзину» не кладём, иначе «Новая услуга» продолжила бы старый черновик.
  static const String _kSlotSessionKey = 'ai_slot_session_id';
  String? _lastSlotSessionId;

  void _persistChatSession() {
    final String? sid = _sessionIds[AiChatKind.chat];
    if (sid == null || sid.isEmpty) return;
    unawaited(SharedPreferences.getInstance()
        .then((SharedPreferences p) => p.setString(_kChatSessionKey, sid)));
  }

  void _persistSlotSession(String sid) {
    if (sid.isEmpty) return;
    _lastSlotSessionId = sid;
    unawaited(SharedPreferences.getInstance()
        .then((SharedPreferences p) => p.setString(_kSlotSessionKey, sid)));
  }

  /// Сбрасывает сессию пошагового сбора указанного типа — чтобы «Новая услуга»
  /// начиналась с ЧИСТОГО черновика, а не продолжала предыдущую (иначе поля
  /// прошлой услуги протекали бы в новую в рамках одного запуска приложения).
  void startFreshSlot(AiChatKind kind) {
    _sessionIds[kind] = null;
  }

  Future<void> _clearPersistedSession() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.remove(_kChatSessionKey);
      await p.remove(_kSlotSessionKey);
    } catch (_) {/* не критично */}
  }

  /// Восстанавливает session_id разговора из прошлого запуска. Вызывать при
  /// открытии экрана чата ДО loadHistory.
  Future<void> restoreChatSession() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      if (_sessionIds[AiChatKind.chat] == null) {
        final String? sid = p.getString(_kChatSessionKey);
        if (sid != null && sid.isNotEmpty) _sessionIds[AiChatKind.chat] = sid;
      }
      _lastSlotSessionId ??= p.getString(_kSlotSessionKey);
    } catch (_) {/* не критично */}
    // Локальный id стирается при ВЫХОДЕ из аккаунта (приватность: следующий
    // пользователь на устройстве не должен видеть чужую переписку). Поэтому
    // после повторного входа того же пользователя восстанавливаем его
    // последнюю беседу из БД по его id (RLS отдаёт только его сессии). Без
    // этого история «терялась» при выходе и повторном входе.
    await _restoreSessionsFromDb();
  }

  /// Достаёт последнюю сессию пользователя из БД, если локального id нет
  /// (после выхода/повторного входа). Беседа (chat/search) — для продолжения
  /// и истории; пошаговое создание (create_*) — только для показа истории.
  Future<void> _restoreSessionsFromDb() async {
    if (_sb.auth.currentUser == null) return;
    try {
      if ((_sessionIds[AiChatKind.chat] ?? '').isEmpty) {
        final List<dynamic> rows = await _sb
            .from('ai_sessions')
            .select('id')
            .eq('app', app)
            .inFilter('kind', const <String>['chat', 'search'])
            .order('updated_at', ascending: false)
            .limit(1);
        if (rows.isNotEmpty) {
          final String? sid = (rows.first as Map)['id'] as String?;
          if (sid != null && sid.isNotEmpty) {
            _sessionIds[AiChatKind.chat] = sid;
            _persistChatSession();
          }
        }
      }
      if ((_lastSlotSessionId ?? '').isEmpty) {
        final List<dynamic> rows = await _sb
            .from('ai_sessions')
            .select('id')
            .eq('app', app)
            .inFilter('kind',
                const <String>['create_order', 'create_service', 'create_card'])
            .order('updated_at', ascending: false)
            .limit(1);
        if (rows.isNotEmpty) {
          final String? sid = (rows.first as Map)['id'] as String?;
          if (sid != null && sid.isNotEmpty) _lastSlotSessionId = sid;
        }
      }
    } catch (_) {/* не критично — просто не восстановим, чат начнётся заново */}
  }

  /// Загружает историю текущего разговора из БД (последние сообщения сессии).
  /// Возвращает «сырые» строки {role, content, data}; экран сам строит из них
  /// сообщения. Пусто, если сессии нет или ошибка.
  Future<List<Map<String, dynamic>>> loadHistory() async {
    // Историю собираем по ДВУМ сессиям — обычный чат/поиск и пошаговое создание
    // услуги — и сливаем в одну ленту по времени. Без этого после перезапуска
    // часть «создание услуги» пропадала (она в отдельной сессии).
    final List<String> ids = <String>[
      if ((_sessionIds[AiChatKind.chat] ?? '').isNotEmpty) _sessionIds[AiChatKind.chat]!,
      if ((_lastSlotSessionId ?? '').isNotEmpty) _lastSlotSessionId!,
    ];
    if (ids.isEmpty) return const <Map<String, dynamic>>[];
    try {
      // Гость (без сессии) не может читать ai_messages напрямую (RLS только для
      // вошедших). Историю отдаёт RPC по device_id — она вернёт сообщения
      // только тех сессий, чей device_id совпадает (его знает только это устройство).
      if (_sb.auth.currentSession == null) {
        final String deviceId = await DeviceId.get();
        final List<dynamic> grows = await _sb.rpc(
          'get_guest_history',
          params: <String, dynamic>{
            'p_session_ids': ids,
            'p_device_id': deviceId,
          },
        );
        return grows
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      }
      final List<dynamic> rows = await _sb
          .from('ai_messages')
          .select('role, content, data, created_at')
          .inFilter('session_id', ids)
          .order('created_at', ascending: true)
          .limit(60);
      return rows
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<AiReply> chat(String message) =>
      _invoke('ai-chat', message, AiChatKind.chat, null);

  /// Стрим версия chat — присылает delta-куски по мере генерации.
  /// Эмитит первое событие AiChatChunk(text: '...', done: false) с
  /// частичным текстом, последнее — AiChatChunk(done: true) с полным
  /// текстом и квотой.
  ///
  /// Используется в UI для эффекта «ассистент печатает».
  /// Подписаться на возвращённый Stream через listen / await for.
  /// Если стрим-функция не задеплоена или сетевая ошибка — бросает
  /// исключение в Stream.
  Stream<AiChatChunk> chatStream(String message) async* {
    final sb = _sb;
    final session = sb.auth.currentSession;
    // Гость (без сессии) общается с ассистентом по device_id и анонимному
    // ключу — сервер применит гостевые дневные лимиты (как в приложении заказчика).
    final bool guest = session == null;
    final String bearer = guest ? Env.supabaseAnonKey : session.accessToken;
    final String? deviceId = guest ? await DeviceId.get() : null;
    final url = '${Env.supabaseUrl}/functions/v1/ai-chat-stream';
    final req = http.Request('POST', Uri.parse(url));
    req.headers['Content-Type']  = 'application/json';
    req.headers['Authorization'] = 'Bearer $bearer';
    req.headers['apikey']        = Env.supabaseAnonKey;
    req.body = jsonEncode(<String, dynamic>{
      'message': message,
      'app':     app,
      'session_id': ?_sessionIds[AiChatKind.chat],
      'device_id':  ?deviceId,
    });

    // ВАЖНО: держим Client в переменной, чтобы закрыть его в finally —
    // иначе на каждое сообщение в чате утекает Client + сокет из
    // keep-alive пула.
    final client = http.Client();
    try {
      final resp = await client.send(req);
      if (resp.statusCode == 402) {
        // Берём понятный текст из тела ответа сервера («дневной лимит…,
        // сбросится завтра, пользуйтесь обычным поиском»), а не куцее
        // «Лимит исчерпан». Тело может не прийти — тогда дружелюбный дефолт.
        String msg = 'Вы достигли дневного лимита запросов к ассистенту. '
            'Лимит сбросится завтра — а пока можно пользоваться обычным '
            'поиском и формой создания.';
        try {
          final body = await resp.stream.bytesToString();
          final dynamic obj = jsonDecode(body);
          if (obj is Map && obj['message'] is String) {
            msg = obj['message'] as String;
          }
        } catch (_) {/* тела нет/не JSON — оставляем дефолт */}
        throw AiQuotaExceeded(msg);
      }
      if (resp.statusCode == 429) {
        // Часовой лимит по IP (гость): показываем дружелюбный текст из тела.
        String msg = 'Слишком много запросов за короткое время. '
            'Попробуйте чуть позже или войдите в аккаунт.';
        try {
          final dynamic o = jsonDecode(await resp.stream.bytesToString());
          if (o is Map && o['message'] is String) msg = o['message'] as String;
        } catch (_) {/* тела нет — оставляем дефолт */}
        throw AiQuotaExceeded(msg);
      }
      if (resp.statusCode == 400) {
        // Слишком длинное / пустое сообщение: даём понятный текст, а не
        // generic-ошибку, которую экран показал бы как «проверьте интернет».
        String msg = 'Не удалось обработать сообщение. Попробуйте короче.';
        try {
          final dynamic o = jsonDecode(await resp.stream.bytesToString());
          if (o is Map && o['error'] == 'message_too_long') {
            msg = 'Сообщение слишком длинное. Сократите его и попробуйте снова.';
          }
        } catch (_) {/* тела нет — оставляем дефолт */}
        throw AiContentFilterError(msg);
      }
      if (resp.statusCode != 200) {
        throw Exception('ai_chat_stream_${resp.statusCode}');
      }

      // NDJSON: одно событие на строку.
      // Локально аккумулируем fullText из delta-кусков (сервер шлёт
      // только новые символы).
      String buf = '';
      String fullText = '';
      bool sawDone = false;

      Iterable<AiChatChunk> processLine(String line) sync* {
        if (line.isEmpty) return;
        Map<String, dynamic> obj;
        try {
          obj = jsonDecode(line) as Map<String, dynamic>;
        } catch (_) { return; }

        final kind = obj['kind'] as String?;
        if (kind == 'session') {
          final sid = obj['session_id'] as String?;
          if (sid != null && sid.isNotEmpty) {
            _sessionIds[AiChatKind.chat] = sid;
            _persistChatSession();
          }
        } else if (kind == 'delta') {
          final delta = obj['text'] as String? ?? '';
          fullText += delta;
          yield AiChatChunk(text: fullText, delta: delta, done: false);
        } else if (kind == 'done') {
          sawDone = true;
          final quotaMap = obj['quota'] is Map<String, dynamic>
              ? obj['quota'] as Map<String, dynamic> : null;
          yield AiChatChunk(
            text:  fullText,
            delta: '',
            done:  true,
            quota: quotaMap == null
                ? null
                : AiQuota(
                    used:  (quotaMap['used']  as num? ?? 0).toInt(),
                    total: (quotaMap['total'] as num? ?? 0).toInt(),
                  ),
            nav: AiNav.fromJson(obj['nav']),
          );
        } else if (kind == 'error') {
          final code = obj['code'] as String?;
          final msg  = obj['message'] as String? ?? 'Ошибка ассистента';
          if (code == 'content_filter') {
            throw AiContentFilterError(msg);
          }
          throw Exception(code ?? 'stream_error');
        }
      }

      await for (final chunk in resp.stream.transform(utf8.decoder)) {
        buf += chunk;
        int nl;
        while ((nl = buf.indexOf('\n')) >= 0) {
          final line = buf.substring(0, nl).trim();
          buf = buf.substring(nl + 1);
          for (final c in processLine(line)) {
            yield c;
            if (c.done) return;
          }
        }
      }
      // Хвост без финального \n — обработать остаток buf, иначе теряем
      // done-событие, если сервер забыл переносы строк.
      final tail = buf.trim();
      if (tail.isNotEmpty) {
        for (final c in processLine(tail)) {
          yield c;
        }
      }
      // Если done так и не пришёл — синтезируем его, чтобы UI закрыл
      // «печатает...» и зафиксировал результат.
      if (!sawDone) {
        yield AiChatChunk(text: fullText, delta: '', done: true);
      }
    } finally {
      client.close();
    }
  }

  Future<AiReply> search(String message) =>
      _invoke('ai-search', message, AiChatKind.search, null);

  Future<AiReply> slotFillOrder(String message) =>
      _invoke('ai-slot-fill', message, AiChatKind.slotFillOrder, 'create_order');

  Future<AiReply> slotFillService(String message) =>
      _invoke('ai-slot-fill', message, AiChatKind.slotFillService, 'create_service');

  /// Пошаговое заполнение карточки исполнителя через ассистента.
  Future<AiReply> slotFillCard(String message) =>
      _invoke('ai-slot-fill', message, AiChatKind.slotFillCard, 'create_card');

  Future<AiReply> _invoke(
    String functionName,
    String message,
    AiChatKind kind,
    String? intent,
  ) async {
    // Гость (без сессии) — передаём device_id для гостевой квоты ассистента
    // (поиск заказов). Создание (slot-fill) и общий не-стрим чат гостю
    // недоступны: сервер ответит 401, экран предложит войти.
    final String? deviceId =
        _sb.auth.currentSession == null ? await DeviceId.get() : null;
    final body = <String, dynamic>{
      'message': message,
      'app':     app,
      'session_id': ?_sessionIds[_sessionBucket(kind)],
      'intent':     ?intent,
      'device_id':  ?deviceId,
      // GPS-координаты пользователя (если он разрешил геолокацию): в поиске
      // сервер считает по ним точное расстояние «от вас», а при создании
      // услуги — сам определяет город/адрес по координатам (обратный
      // геокодер), чтобы не переспрашивать. Ключи опускаются, если координат нет.
      'origin_lat': ?UserLocation.lat,
      'origin_lng': ?UserLocation.lng,
    };

    // ВАЖНО: supabase_flutter functions_client@2.5.0 бросает
    // FunctionException на ЛЮБОМ не-2xx статусе ДО того, как мы успеем
    // прочитать res.status. Поэтому весь разбор кодов идёт в catch.
    try {
      final FunctionResponse res = await _sb.functions.invoke(
        functionName,
        body: body,
      );
      final data = res.data;
      final Map<String, dynamic> json = data is Map<String, dynamic>
          ? data
          : <String, dynamic>{};

      final reply = _buildReply(json);
      if (reply.sessionId.isNotEmpty) {
        final AiChatKind bucket = _sessionBucket(kind);
        _sessionIds[bucket] = reply.sessionId;
        if (bucket == AiChatKind.chat) {
          _persistChatSession();
        } else {
          _persistSlotSession(reply.sessionId); // slot-fill — сохраняем для истории
        }
      }
      return reply;
    } on FunctionException catch (e) {
      // Тело ошибки лежит в e.details — там же, что вернула Edge Function.
      final Map<String, dynamic> json = e.details is Map<String, dynamic>
          ? e.details as Map<String, dynamic>
          : <String, dynamic>{};
      final int status = e.status;

      // ВАЖНО: если сервер успел вернуть session_id даже при ошибке —
      // сохраняем его, чтобы следующий запрос продолжил ту же сессию.
      // Иначе теряем контекст разговора при content_filter.
      final String? newSid = json['session_id'] as String?;
      if (newSid != null && newSid.isNotEmpty) {
        final AiChatKind bucket = _sessionBucket(kind);
        _sessionIds[bucket] = newSid;
        if (bucket == AiChatKind.chat) {
          _persistChatSession();
        } else {
          _persistSlotSession(newSid);
        }
      }

      if (status == 402) {
        throw AiQuotaExceeded(json['message'] as String? ?? 'Лимит исчерпан');
      }
      if (status == 422 && json['error'] == 'content_filter') {
        throw AiContentFilterError(
          json['message'] as String? ?? 'Не удалось обработать запрос',
        );
      }
      if (status == 503) {
        throw AiQuotaExceeded(
          'Ассистент сейчас перегружен. Попробуйте через несколько минут.',
        );
      }
      if (status == 400 && json['error'] == 'message_too_long') {
        throw AiContentFilterError(
          'Сообщение слишком длинное. Сократите его и попробуйте снова.',
        );
      }
      if (kDebugMode) {
        debugPrint('[ai-client] $functionName status=$status error=${json['error']}');
      }
      rethrow;
    } on AiQuotaExceeded {
      rethrow;
    } on AiContentFilterError {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('[ai-client] $functionName failed: ${e.runtimeType}');
      rethrow;
    }
  }

  AiReply _buildReply(Map<String, dynamic> json) {
    return AiReply(
      sessionId: json['session_id'] as String? ?? '',
      text:      json['reply']      as String? ?? '',
      data:      json['data']       as Map<String, dynamic>?,
      cached:    json['cached']     as bool?   ?? false,
      nav:       AiNav.fromJson(json['nav']),
      quota: json['quota'] is Map<String, dynamic>
          ? AiQuota(
              used:  (json['quota']['used']  as num? ?? 0).toInt(),
              total: (json['quota']['total'] as num? ?? 0).toInt(),
            )
          : null,
    );
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
    final Map<String, dynamic> qp = <String, dynamic>{'format': format};
    // Для сырого PCM (фолбэк без Opus) серверу нужна частота дискретизации.
    if (format == 'lpcm') qp['sample_rate'] = '16000';
    // Гость: device_id + app для гостевой квоты голоса (тело занято аудио,
    // поэтому идентификаторы — в query-параметрах).
    if (_sb.auth.currentSession == null) {
      qp['device_id'] = await DeviceId.get();
      qp['app'] = app;
    }
    try {
      final FunctionResponse res = await _sb.functions.invoke(
        'stt-yandex',
        method:        HttpMethod.post,
        body:          bytes,
        queryParameters: qp,
      );
      final data = res.data;
      final Map<String, dynamic> json = data is Map<String, dynamic>
          ? data
          : <String, dynamic>{};
      if (json['text'] is String) {
        return (json['text'] as String).trim();
      }
      return '';
    } on FunctionException catch (e) {
      // Все не-2xx статусы прилетают сюда — раньше мы их разбирали
      // ПОСЛЕ invoke, но supabase_flutter бросает FunctionException
      // и до проверки status дело не доходит.
      final Map<String, dynamic> json = e.details is Map<String, dynamic>
          ? e.details as Map<String, dynamic>
          : <String, dynamic>{};
      final int status = e.status;
      if (status == 402) {
        throw AiQuotaExceeded(json['message'] as String? ?? 'Лимит исчерпан');
      }
      if (status == 413 || json['error'] == 'audio_too_large') {
        throw AiAudioTooLargeError();
      }
      if (status == 422 && json['error'] == 'invalid_format') {
        throw AiAudioInvalidFormatError();
      }
      if (status == 422) {
        throw AiAudioNoSpeechError();
      }
      if (status == 500 && json['error'] == 'stt_auth_error') {
        throw Exception('Ассистент временно недоступен (auth).');
      }
      if (kDebugMode) debugPrint('[ai-client] transcribe status=$status error=${json['error']}');
      rethrow;
    } on AiQuotaExceeded {
      rethrow;
    } on AiAudioTooLargeError {
      rethrow;
    } on AiAudioNoSpeechError {
      rethrow;
    } on AiAudioInvalidFormatError {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('[ai-client] transcribe failed: ${e.runtimeType}');
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

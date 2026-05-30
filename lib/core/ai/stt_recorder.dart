// =====================================================================
// stt_recorder.dart — обёртка над `record` для голосовых сообщений.
//
// Запись идёт в OGG/Opus 16 kHz mono — сжатый формат, который без
// конвертации принимает Yandex SpeechKit STT v1 (sync). На 30 сек
// — примерно 30-60 КБ, влезает в лимит API 1 МБ с большим запасом.
//
// Жизненный цикл:
//   1. ensurePermission() — однажды при первой записи.
//   2. start() — начинает запись во временный файл.
//   3. stop() — останавливает, возвращает File с аудио.
//      (либо cancel() — отменяет и удаляет файл).
//   4. Клиент передаёт File в AiClient.transcribeAudio() и получает текст.
// =====================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class SttRecorder {
  SttRecorder._();
  static final SttRecorder instance = SttRecorder._();

  /// SpeechKit sync API принимает аудио строго до 30 секунд. Останавливаем
  /// запись на 28с, чтобы оставить запас на сетевую задержку.
  static const Duration maxDuration = Duration(seconds: 28);

  final AudioRecorder _rec = AudioRecorder();
  String? _currentPath;
  Timer? _maxDurationTimer;

  /// Формат последней записи для параметра `?format=` в stt-yandex:
  /// 'oggopus' (по умолчанию) либо 'lpcm' (фолбэк на устройствах без Opus).
  String _lastFormat = 'oggopus';
  String get lastFormat => _lastFormat;

  /// Callback срабатывает, когда auto-stop по maxDuration сработал.
  /// Клиент использует его, чтобы отправить накопленную запись.
  void Function()? onAutoStop;

  Future<bool> isRecording() => _rec.isRecording();

  /// Запрашивает разрешение на микрофон. Возвращает true если можно писать.
  Future<bool> ensurePermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  /// Открывает настройки приложения (для случая permanently denied).
  Future<void> openSettings() => openAppSettings();

  Future<bool> start() async {
    final granted = await ensurePermission();
    if (!granted) return false;
    try {
      // Выбираем кодек под устройство. Предпочитаем Opus (компактный, ~30-60 КБ
      // на сообщение). Если нативного Opus-энкодера нет (часть Xiaomi/Huawei/
      // MediaTek), раньше тут был ЖЁСТКИЙ отказ — и голос на таких телефонах не
      // работал вовсе. Теперь фолбэк на сырой PCM (lpcm): он поддерживается
      // везде и его принимает SpeechKit. PCM тяжелее (~32 КБ/сек), но 28 сек ≈
      // 0.9 МБ — влезает в лимит API 1 МБ.
      final AudioEncoder encoder;
      final String ext;
      if (await _rec.isEncoderSupported(AudioEncoder.opus)) {
        encoder = AudioEncoder.opus;       ext = 'ogg'; _lastFormat = 'oggopus';
      } else if (await _rec.isEncoderSupported(AudioEncoder.pcm16bits)) {
        encoder = AudioEncoder.pcm16bits;  ext = 'pcm'; _lastFormat = 'lpcm';
      } else {
        if (kDebugMode) debugPrint('[stt-recorder] no supported encoder (opus/pcm16)');
        return false;
      }
      // Уникальное имя файла, чтобы не было коллизии при быстрых перезаписях.
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.$ext';
      _currentPath = path;
      await _rec.start(
        RecordConfig(
          encoder:      encoder,
          sampleRate:   16000,
          numChannels:  1,
          // По умолчанию у `record` подавление шума и AGC включены — это
          // хорошо для качества распознавания.
        ),
        path: path,
      );
      // Автостоп по верхней границе — иначе SpeechKit отвергнет 30+ сек.
      _maxDurationTimer?.cancel();
      _maxDurationTimer = Timer(maxDuration, () {
        try { onAutoStop?.call(); } catch (_) {}
      });
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[stt-recorder] start failed: $e');
      _currentPath = null;
      return false;
    }
  }

  /// Останавливает запись и возвращает файл. Если записи не было — null.
  Future<File?> stop() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    try {
      final path = await _rec.stop();
      _currentPath = null;
      if (path == null) return null;
      final f = File(path);
      // Если пустой файл — удалим и вернём null.
      if (!await f.exists()) return null;
      final len = await f.length();
      // Опускаем порог до 200 байт — короткие «да», «нет», «ага» в
      // OGG/Opus 16k mono весят ~200-400 байт. Раньше с порогом 500
      // их обрезали и юзер видел «слишком короткое сообщение».
      if (len < 200) {
        try { await f.delete(); } catch (_) {}
        return null;
      }
      return f;
    } catch (e) {
      if (kDebugMode) debugPrint('[stt-recorder] stop failed: $e');
      return null;
    }
  }

  Future<void> cancel() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    try {
      await _rec.cancel();
    } catch (_) {}
    final path = _currentPath;
    _currentPath = null;
    if (path != null) {
      try { await File(path).delete(); } catch (_) {}
    }
  }

  Future<void> dispose() => _rec.dispose();
}

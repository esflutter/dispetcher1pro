import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'config/env.dart';

/// Глобальный наблюдатель состояния сети.
///
/// Источники recheck'а:
///   1. Старт приложения (первое обращение к [instance]).
///   2. `connectivity_plus` — переключение Wi-Fi/мобильного.
///   3. Возврат app из фона ([AppLifecycleState.resumed]) — пока юзер
///      сидел в свёрнутом приложении, мог отвалиться VPN/Wi-Fi.
///   4. Периодический ping раз в 30 с пока app в foreground — ловим
///      случаи когда сеть «отвалилась» без события connectivity_plus
///      (упал VPN-туннель, легла LTE-сота, бэкенд пошёл на ребут).
///
/// Реальная проверка — TCP-connect на 443 порт Supabase-бэкенда. Это
/// устойчивее, чем DNS-lookup публичного домена (`example.com`):
///   * Если работает Supabase — приложение работает, и мы online,
///     даже если `example.com` через VPN не резолвится.
///   * Если Supabase недоступен — никакая «общая» проверка интернета
///     не спасёт: запросы к БД всё равно повиснут.
/// Параллельно пробуем Cloudflare anycast `1.1.1.1:443` как fallback,
/// если Supabase URL ещё не сконфигурирован (debug без --dart-define)
/// или сам бэкенд лежит, а интернет в принципе есть.
///
/// Анти-флаппинг: после `_failureThreshold` подряд провальных проб
/// флипаем на offline. Восстановление (online) — мгновенное по первому
/// успеху. На старте без интернета первый фейл всё-таки сразу даёт
/// offline (без 30 с таймаутов на пустом экране).
class NetworkStatus extends ChangeNotifier with WidgetsBindingObserver {
  NetworkStatus._() {
    // ensureInitialized — идемпотентен: если binding уже создан, возвращает
    // его, иначе создаёт. Без этого первое обращение к
    // `NetworkStatus.instance` до `runApp` (например, при инициализации
    // другого синглтона на старте) падало с LateInitializationError на
    // `WidgetsBinding.instance`.
    WidgetsFlutterBinding.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);
    _sub = Connectivity().onConnectivityChanged.listen((_) => _recheck());
    _startPeriodic();
    _recheck();
  }

  static final NetworkStatus instance = NetworkStatus._();

  // По умолчанию считаем online, чтобы при старте offline-экран не мигал
  // в первые 5 с пока идёт проверка. Если интернета реально нет —
  // первая же проба переведёт в offline (см. _recheck).
  bool _online = true;
  bool _everConfirmedOnline = false;
  int _consecutiveFailures = 0;

  static const bool _checkEnabled = true;
  static const Duration _probeTimeout = Duration(seconds: 5);
  static const Duration _periodicInterval = Duration(seconds: 30);
  // 2 провала подряд до флипа offline: даёт ~30–60 с тишины,
  // достаточно чтобы пережить кратковременный лаг VPN/тоннеля
  // и не моргать offline-экраном на ровном месте.
  static const int _failureThreshold = 2;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _periodic;

  bool get isOffline => !_online;

  /// Принудительно перепроверить соединение (например, по кнопке «Обновить»).
  Future<void> recheck() => _recheck();

  void _startPeriodic() {
    _periodic?.cancel();
    _periodic = Timer.periodic(_periodicInterval, (_) => _recheck());
  }

  void _stopPeriodic() {
    _periodic?.cancel();
    _periodic = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPeriodic();
      _recheck();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _stopPeriodic();
    }
  }

  Future<void> _recheck() async {
    if (!_checkEnabled) return;
    final bool ok = await _checkReachable();
    if (ok) {
      _everConfirmedOnline = true;
      _consecutiveFailures = 0;
      _setOnline(true);
    } else {
      _consecutiveFailures++;
      // Если ни разу не подтверждали online — флипаем сразу
      // (старт без сети, не маринуем юзера 30 с пустым экраном).
      // Иначе требуем 2 подряд провала, чтобы кратковременный лаг VPN
      // или потеря пакетов не вызывали ложную offline-плашку.
      if (!_everConfirmedOnline ||
          _consecutiveFailures >= _failureThreshold) {
        _setOnline(false);
      }
    }
  }

  void _setOnline(bool value) {
    if (_online == value) return;
    _online = value;
    notifyListeners();
  }

  /// Параллельно стучимся в бэкенд и в anycast-fallback. Любой успех —
  /// online, всё провалилось — offline. Параллельно, потому что VPN-выход
  /// может медленно пускать к одному из них, но быстро — к другому,
  /// и ждать всю цепочку 5+5=10 секунд незачем.
  Future<bool> _checkReachable() async {
    final List<Future<bool>> probes = <Future<bool>>[
      _probeBackend(),
      _probeIp('1.1.1.1', 443), // Cloudflare anycast — DNS-free fallback
    ];
    final Completer<bool> done = Completer<bool>();
    int remaining = probes.length;
    for (final Future<bool> p in probes) {
      // ignore: avoid_catches_without_on_clauses
      p.then((bool ok) {
        if (done.isCompleted) return;
        if (ok) {
          done.complete(true);
        } else if (--remaining == 0) {
          done.complete(false);
        }
      }).catchError((Object _) {
        if (done.isCompleted) return;
        if (--remaining == 0) done.complete(false);
      });
    }
    return done.future;
  }

  Future<bool> _probeBackend() async {
    final String url = Env.supabaseUrl;
    if (url.isEmpty) return false;
    String host;
    try {
      host = Uri.parse(url).host;
    } catch (_) {
      return false;
    }
    if (host.isEmpty) return false;
    try {
      final Socket s =
          await Socket.connect(host, 443, timeout: _probeTimeout);
      s.destroy();
      return true;
    } on SocketException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _probeIp(String ip, int port) async {
    try {
      final Socket s = await Socket.connect(
        InternetAddress(ip),
        port,
        timeout: _probeTimeout,
      );
      s.destroy();
      return true;
    } on SocketException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _stopPeriodic();
    super.dispose();
  }
}

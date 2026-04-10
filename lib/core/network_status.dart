import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Глобальный наблюдатель состояния сети.
///
/// Слушает [Connectivity] и при изменениях дополнительно проверяет
/// фактический выход в интернет (DNS-lookup), т.к. наличие Wi-Fi/мобильной
/// сети ещё не гарантирует доступ в сеть.
///
class NetworkStatus extends ChangeNotifier {
  NetworkStatus._() {
    _sub = Connectivity().onConnectivityChanged.listen((_) => _recheck());
    _recheck();
  }

  static final NetworkStatus instance = NetworkStatus._();

  bool _online = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool get isOffline => !_online;

  /// Принудительно перепроверить соединение (например, по кнопке «Обновить»).
  Future<void> recheck() => _recheck();

  Future<void> _recheck() async {
    bool ok = false;
    try {
      final List<InternetAddress> r =
          await InternetAddress.lookup('example.com')
              .timeout(const Duration(seconds: 4));
      ok = r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      ok = false;
    } catch (_) {
      ok = false;
    }
    if (_online != ok) {
      _online = ok;
      notifyListeners();
    } else {
      _online = ok;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

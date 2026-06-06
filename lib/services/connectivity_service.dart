import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Monitoreo de conectividad. Expone [isOnline] y un [stream] de cambios.
class ConnectivityService {
  static final _connectivity = Connectivity();
  static final _controller = StreamController<bool>.broadcast();
  static StreamSubscription? _sub;
  static bool _online = true;

  static bool get isOnline => _online;
  static Stream<bool> get stream => _controller.stream;

  static Future<void> init() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _online = results.any((r) => r != ConnectivityResult.none);

      _sub = _connectivity.onConnectivityChanged.listen((results) {
        final nowOnline = results.any((r) => r != ConnectivityResult.none);
        if (nowOnline != _online) {
          _online = nowOnline;
          _controller.add(_online);
          debugPrint('🌐 Conectividad: ${_online ? "online ✅" : "offline ❌"}');
        }
      });
    } catch (e) {
      debugPrint('ConnectivityService: init error: $e');
    }
  }

  static void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}

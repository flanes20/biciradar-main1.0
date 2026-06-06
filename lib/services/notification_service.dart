import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Servicio centralizado de notificaciones locales (alertas push).
///
/// Cubre el requerimiento del Acta/Informe: "Alertas push en tiempo real al
/// acercarse a incidentes activos en el trayecto". Las notificaciones son
/// locales (no requieren servidor push) y se disparan desde la propia app
/// cuando la lógica de proximidad lo determina.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _proximityChannelId = 'proximity_alerts';
  static const String _proximityChannelName = 'Alertas de proximidad';
  static const String _emergencyChannelId = 'emergency_alerts';
  static const String _emergencyChannelName = 'Emergencias';

  /// Inicializa el plugin y solicita permiso de notificaciones (Android 13+).
  Future<void> init() async {
    if (_initialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(initSettings);

      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidImpl?.requestNotificationsPermission();

      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  /// Notificación de un incidente cercano en la ruta del ciclista.
  Future<void> showProximityAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    await _ensureInit();
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _proximityChannelId,
            _proximityChannelName,
            channelDescription:
                'Avisa cuando te acercas a un incidente reportado',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (e) {
      debugPrint('showProximityAlert error: $e');
    }
  }

  /// Notificación de emergencia (usada por la detección de caídas).
  Future<void> showEmergencyAlert({
    required String title,
    required String body,
  }) async {
    await _ensureInit();
    try {
      await _plugin.show(
        99000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _emergencyChannelId,
            _emergencyChannelName,
            channelDescription: 'Avisos de seguridad y detección de caídas',
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
            color: Color(0xFFE53935),
          ),
        ),
      );
    } catch (e) {
      debugPrint('showEmergencyAlert error: $e');
    }
  }

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }
}

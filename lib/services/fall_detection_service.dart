import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Detector de caídas con lógica pura (sin dependencias de sensores), de modo
/// que puede probarse unitariamente alimentándolo con muestras de magnitud.
///
/// Patrón clásico de caída de un ciclista:
///   1. Caída libre breve → la magnitud de la aceleración cae cerca de 0.
///   2. Impacto contra el suelo → pico fuerte de magnitud.
/// También se dispara ante un impacto muy fuerte aunque no se haya detectado la
/// caída libre previa (golpe seco).
class FallDetector {
  FallDetector({
    this.freeFallThreshold = 3.0, // m/s² (en reposo la magnitud ≈ 9.8)
    this.impactThreshold = 28.0, // m/s² pico tras la caída
    this.hardImpactThreshold = 40.0, // m/s² golpe seco directo
    this.freeFallWindow = const Duration(milliseconds: 1200),
  });

  final double freeFallThreshold;
  final double impactThreshold;
  final double hardImpactThreshold;
  final Duration freeFallWindow;

  DateTime? _lastFreeFall;

  /// Magnitud euclidiana del vector de aceleración.
  static double magnitude(double x, double y, double z) =>
      math.sqrt(x * x + y * y + z * z);

  /// Procesa una muestra de magnitud en el instante [now]. Devuelve `true` si
  /// se reconoce una caída. Tras detectar una caída se reinicia el estado.
  bool process(double mag, DateTime now) {
    // Golpe seco directo: impacto extremo sin requerir caída libre previa.
    if (mag >= hardImpactThreshold) {
      _lastFreeFall = null;
      return true;
    }

    // Fase 1: caída libre.
    if (mag < freeFallThreshold) {
      _lastFreeFall = now;
      return false;
    }

    // Fase 2: impacto dentro de la ventana posterior a una caída libre.
    if (mag >= impactThreshold && _lastFreeFall != null) {
      if (now.difference(_lastFreeFall!) <= freeFallWindow) {
        _lastFreeFall = null;
        return true;
      }
    }
    return false;
  }

  void reset() => _lastFreeFall = null;
}

/// Servicio que conecta el [FallDetector] al acelerómetro del dispositivo y
/// notifica mediante un callback cuando ocurre una caída. Incluye un período
/// de enfriamiento para no disparar repetidamente por el mismo evento.
class FallDetectionService {
  FallDetectionService({FallDetector? detector})
    : _detector = detector ?? FallDetector();

  final FallDetector _detector;
  StreamSubscription<AccelerometerEvent>? _sub;
  DateTime? _lastTrigger;
  bool get isRunning => _sub != null;

  static const Duration _cooldown = Duration(seconds: 20);

  /// Comienza a escuchar el acelerómetro. [onFall] se invoca al detectar caída.
  void start(VoidCallback onFall) {
    if (_sub != null) return;
    _detector.reset();
    try {
      _sub =
          accelerometerEventStream(
            samplingPeriod: SensorInterval.gameInterval,
          ).listen((event) {
            final mag = FallDetector.magnitude(event.x, event.y, event.z);
            final now = DateTime.now();
            if (_detector.process(mag, now)) {
              if (_lastTrigger != null &&
                  now.difference(_lastTrigger!) < _cooldown) {
                return; // todavía en enfriamiento
              }
              _lastTrigger = now;
              onFall();
            }
          }, onError: (e) => debugPrint('FallDetectionService error: $e'));
    } catch (e) {
      debugPrint('No se pudo iniciar el acelerómetro: $e');
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _detector.reset();
  }
}

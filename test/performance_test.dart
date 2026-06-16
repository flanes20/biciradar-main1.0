// Pruebas de carga / rendimiento (stress tests) de la lógica crítica.
//
// Objetivo: verificar que la app procesa volúmenes grandes de datos de forma
// fluida, sin congelar la interfaz. Se estresan las funciones puras que más se
// ejecutan en caliente (cálculo de distancias y filtrado de alertas por
// proximidad en cada actualización del GPS) y el registro histórico de km.
//
// No cubren red (Supabase) ni el render nativo de Mapbox, que no son medibles
// de forma determinista en un test unitario; sí cubren la lógica que corre en
// el hilo de la app y que, si fuera lenta, causaría tirones (jank).
//
// Ejecutar:  flutter test test/performance_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:biciradar/services/proximity_alert_service.dart';
import 'package:biciradar/services/ride_stats_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Genera [n] alertas repartidas alrededor de un punto de Santiago.
  List<Map<String, dynamic>> fakeAlerts(int n) {
    const baseLat = -33.45;
    const baseLng = -70.66;
    return List.generate(n, (i) {
      // Dispersión de ~±0.05° (≈ ±5 km) en una grilla pseudoaleatoria.
      final dLat = ((i * 37) % 1000) / 1000 * 0.1 - 0.05;
      final dLng = ((i * 71) % 1000) / 1000 * 0.1 - 0.05;
      return {
        'id': 'a$i',
        'latitude': baseLat + dLat,
        'longitude': baseLng + dLng,
        'title': 'Incidente $i',
      };
    });
  }

  group('Stress · proximidad de alertas', () {
    test('filtra 5.000 alertas en cada fix de GPS sin trabarse', () {
      final svc = ProximityAlertService(radiusMeters: 150);
      final alerts = fakeAlerts(5000);

      final sw = Stopwatch()..start();
      // Simula 60 actualizaciones de GPS (≈ 1 min de pedaleo a 1 fix/seg).
      for (var i = 0; i < 60; i++) {
        svc.alertsToNotify(-33.45 + i * 0.0001, -70.66, alerts);
      }
      sw.stop();

      final msPorFix = sw.elapsedMilliseconds / 60;
      // ignore: avoid_print
      print('⏱️  60 fijaciones × 5.000 alertas: ${sw.elapsedMilliseconds} ms '
          '(${msPorFix.toStringAsFixed(2)} ms por fix de GPS)');

      // Cada fix debe resolverse muy por debajo de un frame (16 ms a 60 fps).
      expect(msPorFix, lessThan(16),
          reason: 'El filtrado por fix supera un frame → habría tirones');
    });

    test('soporta un pico de 10.000 alertas de una sola vez', () {
      final svc = ProximityAlertService(radiusMeters: 150);
      final alerts = fakeAlerts(10000);

      final sw = Stopwatch()..start();
      final near = svc.alertsToNotify(-33.45, -70.66, alerts);
      sw.stop();

      // ignore: avoid_print
      print('⏱️  Pico de 10.000 alertas: ${sw.elapsedMilliseconds} ms '
          '(${near.length} dentro del radio)');

      expect(sw.elapsedMilliseconds, lessThan(200));
    });
  });

  group('Stress · cálculo de distancias (Haversine)', () {
    test('200.000 cálculos de distancia bajo 1 segundo', () {
      final sw = Stopwatch()..start();
      var acc = 0.0;
      for (var i = 0; i < 200000; i++) {
        acc += ProximityAlertService.distanceMeters(
          -33.45, -70.66, -33.45 + i * 1e-6, -70.66 + i * 1e-6);
      }
      sw.stop();

      // ignore: avoid_print
      print('⏱️  200.000 cálculos Haversine: ${sw.elapsedMilliseconds} ms');

      expect(acc, greaterThan(0)); // evita que el compilador lo optimice
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('Stress · historial de kilómetros', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      RideStatsService.resetForTest();
      await RideStatsService.init();
    });

    test('procesa 2 años de registros diarios al instante', () async {
      // Sembramos 730 días con km variables (≈ 2 años de uso).
      final data = <String, double>{};
      var day = DateTime.now();
      for (var i = 0; i < 730; i++) {
        data[RideStatsService.dayKey(day)] = (i % 25) + 1.0;
        day = day.subtract(const Duration(days: 1));
      }
      await RideStatsService.debugSeed(data);

      final sw = Stopwatch()..start();
      final total = RideStatsService.totalKm();
      final streak = RideStatsService.currentStreak();
      final week = RideStatsService.last7Days();
      final best = RideStatsService.bestDayKm();
      sw.stop();

      // ignore: avoid_print
      print('⏱️  Agregados sobre 730 días: ${sw.elapsedMilliseconds} ms '
          '(total ${total.toStringAsFixed(0)} km, racha $streak, '
          'mejor ${best.toStringAsFixed(0)} km)');

      expect(week.length, 7);
      expect(total, greaterThan(0));
      expect(sw.elapsedMilliseconds, lessThan(100));
    });
  });
}

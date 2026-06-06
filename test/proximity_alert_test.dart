import 'package:flutter_test/flutter_test.dart';
import 'package:biciradar/services/proximity_alert_service.dart';

void main() {
  group('ProximityAlertService.distanceMeters', () {
    test('mismo punto = 0', () {
      expect(
        ProximityAlertService.distanceMeters(-33.45, -70.66, -33.45, -70.66),
        closeTo(0, 1e-6),
      );
    });

    test('1 grado de latitud ≈ 111 km', () {
      final d = ProximityAlertService.distanceMeters(0, 0, 1, 0);
      expect(d, closeTo(111195, 500));
    });
  });

  Map<String, dynamic> alert(String id, double lat, double lng) => {
    'id': id,
    'latitude': lat,
    'longitude': lng,
    'title': 'Incidente $id',
  };

  group('ProximityAlertService.alertsToNotify', () {
    test('notifica una alerta cercana una sola vez', () {
      final svc = ProximityAlertService(radiusMeters: 150);
      // ~50 m al norte
      final near = alert('a', -33.4505, -70.66);
      final user = [-33.45, -70.66];

      final first = svc.alertsToNotify(user[0], user[1], [near]);
      expect(first.length, 1);

      // Sigue cerca → no vuelve a notificar.
      final second = svc.alertsToNotify(user[0], user[1], [near]);
      expect(second, isEmpty);
    });

    test('no notifica alertas lejanas', () {
      final svc = ProximityAlertService(radiusMeters: 150);
      final far = alert('b', -33.50, -70.70); // varios km
      final result = svc.alertsToNotify(-33.45, -70.66, [far]);
      expect(result, isEmpty);
    });

    test('al alejarse y regresar vuelve a notificar', () {
      final svc = ProximityAlertService(radiusMeters: 150);
      final a = alert('c', -33.4505, -70.66);

      expect(svc.alertsToNotify(-33.45, -70.66, [a]).length, 1);
      // Usuario se aleja (lista evaluada sin alertas cercanas).
      expect(svc.alertsToNotify(-33.40, -70.50, [a]), isEmpty);
      // Regresa → debe volver a avisar.
      expect(svc.alertsToNotify(-33.45, -70.66, [a]).length, 1);
    });

    test('ignora alertas sin coordenadas', () {
      final svc = ProximityAlertService(radiusMeters: 150);
      final bad = {'id': 'x', 'title': 'sin coords'};
      expect(svc.alertsToNotify(-33.45, -70.66, [bad]), isEmpty);
    });

    test('reset permite volver a notificar', () {
      final svc = ProximityAlertService(radiusMeters: 150);
      final a = alert('d', -33.4505, -70.66);
      expect(svc.alertsToNotify(-33.45, -70.66, [a]).length, 1);
      svc.reset();
      expect(svc.alertsToNotify(-33.45, -70.66, [a]).length, 1);
    });
  });
}

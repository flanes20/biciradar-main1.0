import 'package:flutter_test/flutter_test.dart';
import 'package:biciradar/services/fall_detection_service.dart';

void main() {
  group('FallDetector.magnitude', () {
    test('vector en reposo (solo gravedad) ≈ 9.8', () {
      expect(FallDetector.magnitude(0, 9.8, 0), closeTo(9.8, 1e-9));
    });

    test('vector 3-4-0 da 5', () {
      expect(FallDetector.magnitude(3, 4, 0), closeTo(5, 1e-9));
    });
  });

  group('FallDetector.process', () {
    test('un golpe seco extremo dispara de inmediato', () {
      final d = FallDetector();
      expect(d.process(45, DateTime(2026)), isTrue);
    });

    test('caída libre seguida de impacto dispara', () {
      final d = FallDetector();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      expect(d.process(1.0, t0), isFalse); // caída libre
      expect(
        d.process(30.0, t0.add(const Duration(milliseconds: 400))),
        isTrue,
      ); // impacto
    });

    test('impacto moderado sin caída libre previa NO dispara', () {
      final d = FallDetector();
      expect(d.process(30.0, DateTime(2026)), isFalse);
    });

    test('impacto demasiado tarde tras la caída libre NO dispara', () {
      final d = FallDetector();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      expect(d.process(1.0, t0), isFalse);
      expect(
        d.process(30.0, t0.add(const Duration(seconds: 5))),
        isFalse,
      );
    });

    test('actividad normal (caminar/pedalear) NO dispara', () {
      final d = FallDetector();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      var fired = false;
      for (var i = 0; i < 50; i++) {
        // magnitudes típicas entre 8 y 14
        final mag = 9.8 + (i % 5) - 2;
        if (d.process(mag, t0.add(Duration(milliseconds: i * 50)))) {
          fired = true;
        }
      }
      expect(fired, isFalse);
    });

    test('reset olvida la caída libre previa', () {
      final d = FallDetector();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      d.process(1.0, t0);
      d.reset();
      expect(
        d.process(30.0, t0.add(const Duration(milliseconds: 300))),
        isFalse,
      );
    });
  });
}

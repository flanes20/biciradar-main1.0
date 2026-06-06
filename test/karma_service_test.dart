import 'package:flutter_test/flutter_test.dart';
import 'package:biciradar/services/karma_service.dart';

void main() {
  group('KarmaService.getLevel', () {
    test('karma negativo y bajo es Novato', () {
      expect(KarmaService.getLevel(-50).title, 'Novato');
      expect(KarmaService.getLevel(0).title, 'Novato');
      expect(KarmaService.getLevel(9).title, 'Novato');
    });

    test('10-29 es Explorador', () {
      expect(KarmaService.getLevel(10).title, 'Explorador');
      expect(KarmaService.getLevel(29).title, 'Explorador');
    });

    test('30-59 es Guardián', () {
      expect(KarmaService.getLevel(30).title, 'Guardián');
      expect(KarmaService.getLevel(59).title, 'Guardián');
    });

    test('60-99 es Héroe', () {
      expect(KarmaService.getLevel(60).title, 'Héroe');
      expect(KarmaService.getLevel(99).title, 'Héroe');
    });

    test('100 o más es Leyenda', () {
      expect(KarmaService.getLevel(100).title, 'Leyenda');
      expect(KarmaService.getLevel(99999).title, 'Leyenda');
    });
  });

  group('KarmaService.getLevelProgress', () {
    test('el nivel máximo (Leyenda) siempre está al 100%', () {
      expect(KarmaService.getLevelProgress(100), 1.0);
      expect(KarmaService.getLevelProgress(500), 1.0);
    });

    test('progreso al inicio de un nivel es ~0', () {
      // Explorador empieza en 10
      expect(KarmaService.getLevelProgress(10), closeTo(0.05, 0.05));
    });

    test('el progreso siempre está entre 0 y 1', () {
      for (final k in [-100, 0, 15, 45, 80, 100, 1000]) {
        final p = KarmaService.getLevelProgress(k);
        expect(p, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('KarmaService.levels', () {
    test('hay 5 niveles definidos', () {
      expect(KarmaService.levels.length, 5);
    });

    test('los niveles están ordenados por minKarma ascendente', () {
      for (var i = 1; i < KarmaService.levels.length; i++) {
        expect(
          KarmaService.levels[i].minKarma >
              KarmaService.levels[i - 1].minKarma,
          isTrue,
        );
      }
    });
  });
}

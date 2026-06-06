import 'package:flutter_test/flutter_test.dart';
import 'package:biciradar/services/co2_service.dart';

void main() {
  group('Co2Service.savedKg', () {
    test('0 km no ahorra nada', () {
      expect(Co2Service.savedKg(0), 0);
    });

    test('1 km ahorra 0.13 kg (130 g/km)', () {
      expect(Co2Service.savedKg(1), closeTo(0.13, 1e-9));
    });

    test('10 km ahorra 1.3 kg', () {
      expect(Co2Service.savedKg(10), closeTo(1.3, 1e-9));
    });

    test('escala linealmente', () {
      expect(Co2Service.savedKg(100), closeTo(13.0, 1e-9));
    });
  });

  group('Co2Service.format', () {
    test('menos de 1 kg se muestra en gramos', () {
      // 2 km -> 0.26 kg -> 260 g
      expect(Co2Service.format(Co2Service.savedKg(2)), '260 g');
    });

    test('entre 1 y 1000 kg se muestra en kg con 2 decimales', () {
      expect(Co2Service.format(1.5), '1.50 kg');
    });

    test('1000 kg o más se muestra en toneladas', () {
      expect(Co2Service.format(2100), '2.1 t');
    });

    test('exactamente 1 kg', () {
      expect(Co2Service.format(1), '1.00 kg');
    });
  });

  group('Co2Service.treeEquivalent', () {
    test('0 kg devuelve string vacío', () {
      expect(Co2Service.treeEquivalent(0), '');
    });

    test('valor negativo devuelve string vacío', () {
      expect(Co2Service.treeEquivalent(-5), '');
    });

    test('22 kg equivale a ~1 árbol/año', () {
      final result = Co2Service.treeEquivalent(22);
      expect(result.contains('árbol'), isTrue);
    });

    test('44 kg equivale a ~2 árboles/año (plural)', () {
      final result = Co2Service.treeEquivalent(44);
      expect(result.contains('árboles'), isTrue);
    });
  });
}

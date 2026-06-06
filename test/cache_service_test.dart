import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:biciradar/services/cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Estado limpio de SharedPreferences antes de cada test.
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();
  });

  final sampleAlerts = [
    {'id': '1', 'title': 'Bache', 'type': 'danger'},
    {'id': '2', 'title': 'Robo', 'type': 'theft'},
  ];

  group('CacheService alertas', () {
    test('guarda y recupera alertas', () async {
      await CacheService.saveAlerts(sampleAlerts);
      final loaded = CacheService.loadAlerts(ignoreExpiry: true);
      expect(loaded, isNotNull);
      expect(loaded!.length, 2);
      expect(loaded.first['title'], 'Bache');
    });

    test('sin datos devuelve null', () {
      expect(CacheService.loadAlerts(ignoreExpiry: true), isNull);
    });

    test('recién guardado no está expirado', () async {
      await CacheService.saveAlerts(sampleAlerts);
      expect(CacheService.loadAlerts(ignoreExpiry: false), isNotNull);
    });
  });

  group('CacheService eventos', () {
    test('guarda y recupera eventos', () async {
      final events = [
        {'id': 'e1', 'title': 'Cleta nocturna'},
      ];
      await CacheService.saveEvents(events);
      final loaded = CacheService.loadEvents(ignoreExpiry: true);
      expect(loaded, isNotNull);
      expect(loaded!.single['title'], 'Cleta nocturna');
    });
  });

  group('CacheService ciclovías', () {
    test('guarda y recupera el GeoJSON crudo', () async {
      const geo = '{"type":"FeatureCollection","features":[]}';
      await CacheService.saveCiclovias(geo);
      expect(CacheService.loadCiclovias(), geo);
    });

    test('sin datos devuelve null', () {
      expect(CacheService.loadCiclovias(), isNull);
    });
  });

  group('CacheService.clearAll', () {
    test('borra alertas y eventos pero conserva ciclovías', () async {
      await CacheService.saveAlerts(sampleAlerts);
      await CacheService.saveEvents([
        {'id': 'e1'},
      ]);
      await CacheService.saveCiclovias('{"x":1}');

      await CacheService.clearAll();

      expect(CacheService.loadAlerts(ignoreExpiry: true), isNull);
      expect(CacheService.loadEvents(ignoreExpiry: true), isNull);
      // clearAll NO borra ciclovías (no expiran).
      expect(CacheService.loadCiclovias(), '{"x":1}');
    });
  });
}

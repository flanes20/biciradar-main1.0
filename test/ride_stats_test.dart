import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:biciradar/services/ride_stats_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    RideStatsService.resetForTest();
    await RideStatsService.init();
  });

  String key(DateTime d) => RideStatsService.dayKey(d);

  test('dayKey formatea con ceros', () {
    expect(RideStatsService.dayKey(DateTime(2026, 3, 5)), '2026-03-05');
  });

  test('addKm acumula en el día de hoy', () async {
    await RideStatsService.addKm(2.0);
    await RideStatsService.addKm(1.5);
    expect(RideStatsService.todayKm(), closeTo(3.5, 1e-9));
  });

  test('addKm ignora valores no positivos', () async {
    await RideStatsService.addKm(0);
    await RideStatsService.addKm(-3);
    expect(RideStatsService.todayKm(), 0);
  });

  test('last7Days devuelve 7 días en orden', () async {
    final week = RideStatsService.last7Days();
    expect(week.length, 7);
    for (var i = 1; i < week.length; i++) {
      expect(week[i].date.isAfter(week[i - 1].date), isTrue);
    }
  });

  test('weekKm suma los últimos 7 días', () async {
    final now = DateTime(2026, 5, 30);
    await RideStatsService.debugSeed({
      key(now): 5.0,
      key(now.subtract(const Duration(days: 2))): 3.0,
      key(now.subtract(const Duration(days: 10))): 99.0, // fuera de la semana
    });
    expect(RideStatsService.weekKm(now: now), closeTo(8.0, 1e-9));
    expect(RideStatsService.totalKm(), closeTo(107.0, 1e-9));
  });

  group('currentStreak', () {
    test('cuenta días consecutivos hasta hoy', () async {
      final now = DateTime(2026, 5, 30);
      await RideStatsService.debugSeed({
        key(now): 4.0,
        key(now.subtract(const Duration(days: 1))): 2.0,
        key(now.subtract(const Duration(days: 2))): 1.0,
        // día -3 vacío → corta la racha
        key(now.subtract(const Duration(days: 4))): 9.0,
      });
      expect(RideStatsService.currentStreak(now: now), 3);
    });

    test('sigue contando desde ayer si hoy no hay actividad', () async {
      final now = DateTime(2026, 5, 30);
      await RideStatsService.debugSeed({
        key(now.subtract(const Duration(days: 1))): 2.0,
        key(now.subtract(const Duration(days: 2))): 1.0,
      });
      expect(RideStatsService.currentStreak(now: now), 2);
    });

    test('sin datos la racha es 0', () {
      expect(RideStatsService.currentStreak(), 0);
    });
  });

  test('bestDayKm devuelve el máximo', () async {
    final now = DateTime(2026, 5, 30);
    await RideStatsService.debugSeed({
      key(now): 4.0,
      key(now.subtract(const Duration(days: 1))): 12.5,
      key(now.subtract(const Duration(days: 2))): 7.0,
    });
    expect(RideStatsService.bestDayKm(), 12.5);
    expect(RideStatsService.activeDays(), 3);
  });
}

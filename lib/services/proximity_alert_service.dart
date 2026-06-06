import 'dart:math' as math;

/// Decide cuándo avisar al ciclista de que se acerca a un incidente activo.
///
/// Lógica pura (sin sensores ni red) para poder probarla unitariamente:
/// calcula la distancia con la fórmula de Haversine y recuerda qué alertas ya
/// fueron notificadas para no repetir el aviso mientras el usuario permanece
/// dentro del radio.
class ProximityAlertService {
  ProximityAlertService({this.radiusMeters = 150});

  /// Radio de disparo en metros.
  final double radiusMeters;

  /// IDs de alertas ya notificadas en la cercanía actual.
  final Set<String> _notified = {};

  static const double _earthRadiusM = 6371000;

  /// Distancia en metros entre dos coordenadas (Haversine).
  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusM * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  /// Dada la posición del usuario y la lista de alertas, devuelve aquellas
  /// dentro del radio que aún no han sido notificadas. Las marca como
  /// notificadas. Las alertas que salieron del radio se "olvidan" para poder
  /// volver a avisar si el usuario regresa más tarde.
  List<Map<String, dynamic>> alertsToNotify(
    double userLat,
    double userLng,
    List<Map<String, dynamic>> alerts,
  ) {
    final result = <Map<String, dynamic>>[];
    final stillNear = <String>{};

    for (final alert in alerts) {
      final id = alert['id']?.toString();
      final lat = (alert['latitude'] as num?)?.toDouble();
      final lng = (alert['longitude'] as num?)?.toDouble();
      if (id == null || lat == null || lng == null) continue;

      final dist = distanceMeters(userLat, userLng, lat, lng);
      if (dist <= radiusMeters) {
        stillNear.add(id);
        if (!_notified.contains(id)) {
          _notified.add(id);
          result.add(alert);
        }
      }
    }

    // Olvidar las alertas de las que ya nos alejamos (salieron del radio).
    _notified.removeWhere((id) => !stillNear.contains(id));

    return result;
  }

  void reset() => _notified.clear();
}

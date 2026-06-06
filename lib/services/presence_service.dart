import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;

class PresenceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> upsertMyLocation({
    required geo.Position position,
    required String username,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    await _supabase.from('user_locations').upsert({
      'user_id': user.id,
      'username': username,
      'lat': position.latitude,
      'lng': position.longitude,
      'heading': position.heading < 0 ? 0 : position.heading,
      'speed_kmh': position.speed < 0 ? 0 : position.speed * 3.6,
      'is_online': true,
      'last_seen': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Stream<List<Map<String, dynamic>>> streamActiveCyclists() {
    final currentUser = _supabase.auth.currentUser;

    return _supabase
        .from('user_locations')
        .stream(primaryKey: ['user_id'])
        .eq('is_online', true)
        .map(
          (rows) => rows
              .where((row) => row['user_id'] != currentUser?.id)
              .where((row) {
                final lastSeen = DateTime.tryParse(row['last_seen'] ?? '');
                if (lastSeen == null) return false;
                return DateTime.now().difference(lastSeen).inMinutes <= 5;
              })
              .toList(),
        );
  }

  /// Marca al usuario actual como desconectado (al cerrar la app o el mapa)
  /// para que no siga apareciendo "en línea" para los demás ciclistas.
  Future<void> clearMyLocation() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      await _supabase
          .from('user_locations')
          .update({
            'is_online': false,
            'last_seen': DateTime.now().toIso8601String(),
          })
          .eq('user_id', user.id);
    } catch (_) {
      // Sin red: el registro expirará solo a los 5 min por last_seen.
    }
  }
}

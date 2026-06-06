import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class FavoriteRoute {
  final String? id;
  final String name;
  final String icon;
  final List<Map<String, dynamic>> waypoints; // [{lat, lng, name}]
  final double? distanceKm;

  const FavoriteRoute({
    this.id,
    required this.name,
    required this.icon,
    required this.waypoints,
    this.distanceKm,
  });

  factory FavoriteRoute.fromMap(Map<String, dynamic> m) {
    final raw = m['waypoints'];
    final List<Map<String, dynamic>> wps = raw is List
        ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : [];
    return FavoriteRoute(
      id: m['id'] as String?,
      name: m['name'] as String? ?? '',
      icon: m['icon'] as String? ?? '📍',
      waypoints: wps,
      distanceKm: (m['distance_km'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'name': name,
        'icon': icon,
        'waypoints': waypoints,
        if (distanceKm != null) 'distance_km': distanceKm,
      };
}

/// Presets rápidos para crear favoritos desde la UI.
const kFavoritePresets = [
  {'name': 'Casa',        'icon': '🏠'},
  {'name': 'Trabajo',     'icon': '💼'},
  {'name': 'Universidad', 'icon': '🎓'},
  {'name': 'Gimnasio',    'icon': '🏋️'},
  {'name': 'Supermercado','icon': '🛒'},
];

class FavoritesService {
  final SupabaseClient _supabase = Supabase.instance.client;
  String? get _uid => _supabase.auth.currentUser?.id;

  Future<List<FavoriteRoute>> getAll() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _supabase
          .from('favorite_routes')
          .select()
          .eq('user_id', uid)
          .order('created_at');
      return rows.map((r) => FavoriteRoute.fromMap(r)).toList();
    } catch (e) {
      debugPrint('Error cargando favoritos: $e');
      return [];
    }
  }

  Future<FavoriteRoute?> save(FavoriteRoute route) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final data = route.toMap(uid);
      if (route.id != null) {
        await _supabase
            .from('favorite_routes')
            .update(data)
            .eq('id', route.id!);
        return route;
      } else {
        final row = await _supabase
            .from('favorite_routes')
            .insert(data)
            .select()
            .single();
        return FavoriteRoute.fromMap(row);
      }
    } catch (e) {
      debugPrint('Error guardando favorito: $e');
      return null;
    }
  }

  Future<bool> delete(String id) async {
    try {
      await _supabase.from('favorite_routes').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Error eliminando favorito: $e');
      return false;
    }
  }
}

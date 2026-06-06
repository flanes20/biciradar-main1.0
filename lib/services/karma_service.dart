import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class KarmaLevel {
  final String title;
  final String emoji;
  final int minKarma;
  final int maxKarma; // -1 = sin límite
  final int colorValue;

  const KarmaLevel({
    required this.title,
    required this.emoji,
    required this.minKarma,
    required this.maxKarma,
    required this.colorValue,
  });
}

class KarmaService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const List<KarmaLevel> levels = [
    KarmaLevel(
      title: 'Novato',
      emoji: '🌱',
      minKarma: -999,
      maxKarma: 9,
      colorValue: 0xFF9E9E9E,
    ),
    KarmaLevel(
      title: 'Explorador',
      emoji: '🚴',
      minKarma: 10,
      maxKarma: 29,
      colorValue: 0xFF64B5F6,
    ),
    KarmaLevel(
      title: 'Guardián',
      emoji: '🛡️',
      minKarma: 30,
      maxKarma: 59,
      colorValue: 0xFF81C784,
    ),
    KarmaLevel(
      title: 'Héroe',
      emoji: '⚡',
      minKarma: 60,
      maxKarma: 99,
      colorValue: 0xFFFFD54F,
    ),
    KarmaLevel(
      title: 'Leyenda',
      emoji: '🏆',
      minKarma: 100,
      maxKarma: -1,
      colorValue: 0xFFFF8A65,
    ),
  ];

  static KarmaLevel getLevel(int karma) {
    for (final level in levels.reversed) {
      if (karma >= level.minKarma) return level;
    }
    return levels.first;
  }

  static double getLevelProgress(int karma) {
    final level = getLevel(karma);
    if (level.maxKarma == -1) return 1.0;
    final range = level.maxKarma - level.minKarma + 1;
    final progress = (karma - level.minKarma) / range;
    return progress.clamp(0.0, 1.0);
  }

  /// Calcula el karma de un usuario basado en votos de sus alertas.
  /// karma = sum(votes_up) - sum(votes_down)
  Future<int> getUserKarma(String userId) async {
    try {
      final alerts = await _supabase
          .from('bike_alerts')
          .select('votes_up, votes_down')
          .eq('user_id', userId);

      int karma = 0;
      for (final alert in alerts) {
        karma += (alert['votes_up'] as int? ?? 0);
        karma -= (alert['votes_down'] as int? ?? 0);
      }
      return karma;
    } catch (e) {
      debugPrint('Error calculando karma: $e');
      return 0;
    }
  }

  /// Karma del usuario actual.
  Future<int> getMyKarma() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return 0;
    return getUserKarma(uid);
  }

  /// Top ciclistas ordenados por karma (alertas con más votos positivos netos).
  Future<List<Map<String, dynamic>>> getTopCyclists({int limit = 20}) async {
    try {
      // Obtenemos alertas y agrupamos por usuario manualmente
      final alerts = await _supabase
          .from('bike_alerts')
          .select('user_id, user_name, votes_up, votes_down');

      final Map<String, Map<String, dynamic>> byUser = {};
      for (final alert in alerts) {
        final uid = alert['user_id'] as String? ?? '';
        if (uid.isEmpty) continue;
        if (!byUser.containsKey(uid)) {
          byUser[uid] = {
            'user_id': uid,
            'user_name': alert['user_name'] ?? 'Usuario',
            'karma': 0,
            'alerts_count': 0,
          };
        }
        byUser[uid]!['karma'] = (byUser[uid]!['karma'] as int) +
            (alert['votes_up'] as int? ?? 0) -
            (alert['votes_down'] as int? ?? 0);
        byUser[uid]!['alerts_count'] = (byUser[uid]!['alerts_count'] as int) + 1;
      }

      // Enriquecer con datos de perfiles
      if (byUser.isNotEmpty) {
        try {
          final profiles = await _supabase
              .from('profiles')
              .select('id, username, full_name, avatar_url')
              .inFilter('id', byUser.keys.toList());
          for (final p in profiles) {
            final uid = p['id'] as String? ?? '';
            if (byUser.containsKey(uid)) {
              byUser[uid]!['username'] = p['username'] ?? byUser[uid]!['user_name'];
              byUser[uid]!['full_name'] = p['full_name'] ?? '';
              byUser[uid]!['avatar_url'] = p['avatar_url'] ?? '';
            }
          }
        } catch (_) {}
      }

      final list = byUser.values.toList();
      list.sort((a, b) => (b['karma'] as int).compareTo(a['karma'] as int));
      return list.take(limit).toList();
    } catch (e) {
      debugPrint('Error obteniendo top ciclistas: $e');
      return [];
    }
  }

  /// Ranking por comunas basado en cantidad de km (campo total_km en profiles, si existe).
  /// Si no hay datos de comunas, usa location_name de alertas como proxy.
  Future<List<Map<String, dynamic>>> getRankingByComunas() async {
    final Map<String, Map<String, dynamic>> byComunas = {};

    // Intentar leer comunas y km desde profiles (columnas opcionales)
    try {
      final profiles = await _supabase
          .from('profiles')
          .select('id, commune, total_km');

      for (final p in profiles) {
        final commune = (p['commune'] as String?)?.trim();
        if (commune == null || commune.isEmpty) continue;
        if (!byComunas.containsKey(commune)) {
          byComunas[commune] = {
            'commune': commune,
            'total_km': 0.0,
            'cyclists_count': 0,
          };
        }
        final km = (p['total_km'] as num?)?.toDouble() ?? 0.0;
        byComunas[commune]!['total_km'] =
            (byComunas[commune]!['total_km'] as double) + km;
        byComunas[commune]!['cyclists_count'] =
            (byComunas[commune]!['cyclists_count'] as int) + 1;
      }
    } catch (_) {
      // Columnas aún no existen en la DB — usar fallback
    }

    // Fallback: agrupar alertas por location_name como proxy de comunas
    if (byComunas.isEmpty) {
      try {
        final alerts = await _supabase
            .from('bike_alerts')
            .select('location_name, user_id')
            .eq('is_active', true);

        for (final a in alerts) {
          final loc = (a['location_name'] as String?)?.trim();
          if (loc == null || loc.isEmpty || loc == 'Ubicación sin nombre') continue;
          if (!byComunas.containsKey(loc)) {
            byComunas[loc] = {
              'commune': loc,
              'total_km': 0.0,
              'cyclists_count': 0,
              'alerts_count': 0,
            };
          }
          byComunas[loc]!['alerts_count'] =
              (byComunas[loc]!['alerts_count'] as int? ?? 0) + 1;
        }
      } catch (e) {
        debugPrint('Error obteniendo ranking comunas (fallback): $e');
      }
    }

    final list = byComunas.values.toList();
    list.sort(
      (a, b) => (b['total_km'] as double).compareTo(a['total_km'] as double),
    );
    return list;
  }
}

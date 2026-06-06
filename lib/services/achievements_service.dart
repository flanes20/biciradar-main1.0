import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class AchievementsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? get _userId => _supabase.auth.currentUser?.id;

  /// Devuelve todos los logros del catálogo junto con si el usuario los desbloqueó.
  Future<List<Map<String, dynamic>>> getAllWithStatus() async {
    final uid = _userId;
    if (uid == null) return [];

    try {
      final catalog = await _supabase
          .from('achievements')
          .select()
          .order('category')
          .order('requirement_value');

      final unlocked = await _supabase
          .from('user_achievements')
          .select('achievement_id, unlocked_at')
          .eq('user_id', uid);

      final unlockedMap = {
        for (final u in unlocked)
          u['achievement_id'] as String: u['unlocked_at'] as String,
      };

      return catalog.map<Map<String, dynamic>>((a) {
        final aid = a['id'] as String;
        return {
          ...a,
          'unlocked': unlockedMap.containsKey(aid),
          'unlocked_at': unlockedMap[aid],
        };
      }).toList();
    } catch (e) {
      debugPrint('Error obteniendo logros: $e');
      return [];
    }
  }

  /// Chequea todos los logros del usuario y desbloquea los que correspondan.
  /// Retorna los IDs de los logros recién desbloqueados.
  Future<List<String>> checkAndUnlock() async {
    final uid = _userId;
    if (uid == null) return [];

    try {
      // Obtener logros ya desbloqueados para no re-chequear
      final alreadyUnlocked = await _supabase
          .from('user_achievements')
          .select('achievement_id')
          .eq('user_id', uid);

      final done = {
        for (final u in alreadyUnlocked) u['achievement_id'] as String,
      };

      final toUnlock = <String>[];

      // --- Perfil completo ---
      if (!done.contains('profile_complete')) {
        final profile = await _supabase
            .from('profiles')
            .select('username, full_name, avatar_url')
            .eq('id', uid)
            .maybeSingle();
        if (profile != null &&
            (profile['username'] as String? ?? '').isNotEmpty &&
            (profile['full_name'] as String? ?? '').isNotEmpty &&
            (profile['avatar_url'] as String? ?? '').isNotEmpty) {
          toUnlock.add('profile_complete');
        }
      }

      // --- Alertas reportadas ---
      final alertsNeedCheck = {'first_alert', 'guardian_5', 'centinel_10', 'reporter_25', 'early_bird', 'night_owl'}
          .where((id) => !done.contains(id))
          .toSet();

      if (alertsNeedCheck.isNotEmpty) {
        final alerts = await _supabase
            .from('bike_alerts')
            .select('created_at')
            .eq('user_id', uid);

        final count = alerts.length;

        if (alertsNeedCheck.contains('first_alert') && count >= 1) {
          toUnlock.add('first_alert');
        }
        if (alertsNeedCheck.contains('guardian_5') && count >= 5) {
          toUnlock.add('guardian_5');
        }
        if (alertsNeedCheck.contains('centinel_10') && count >= 10) {
          toUnlock.add('centinel_10');
        }
        if (alertsNeedCheck.contains('reporter_25') && count >= 25) {
          toUnlock.add('reporter_25');
        }

        // Madrugador: alguna alerta creada antes de las 7am
        if (alertsNeedCheck.contains('early_bird')) {
          final hasEarly = alerts.any((a) {
            final dt = DateTime.tryParse(a['created_at'] as String? ?? '');
            if (dt == null) return false;
            final local = dt.toLocal();
            return local.hour < 7;
          });
          if (hasEarly) toUnlock.add('early_bird');
        }

        // Búho nocturno: alguna alerta creada después de las 22h
        if (alertsNeedCheck.contains('night_owl')) {
          final hasNight = alerts.any((a) {
            final dt = DateTime.tryParse(a['created_at'] as String? ?? '');
            if (dt == null) return false;
            final local = dt.toLocal();
            return local.hour >= 22;
          });
          if (hasNight) toUnlock.add('night_owl');
        }
      }

      // --- Eventos creados ---
      final eventsCreatedCheck = {'first_event_create', 'event_host_3'}
          .where((id) => !done.contains(id))
          .toSet();

      if (eventsCreatedCheck.isNotEmpty) {
        final created = await _supabase
            .from('events')
            .select('id')
            .eq('user_id', uid);

        final createdCount = created.length;
        if (eventsCreatedCheck.contains('first_event_create') && createdCount >= 1) {
          toUnlock.add('first_event_create');
        }
        if (eventsCreatedCheck.contains('event_host_3') && createdCount >= 3) {
          toUnlock.add('event_host_3');
        }
      }

      // --- Eventos en que participó ---
      final eventsJoinedCheck = {'first_event_join', 'event_social_5'}
          .where((id) => !done.contains(id))
          .toSet();

      if (eventsJoinedCheck.isNotEmpty) {
        final joined = await _supabase
            .from('events')
            .select('id')
            .contains('participants_ids', [uid]);

        final joinedCount = joined.length;
        if (eventsJoinedCheck.contains('first_event_join') && joinedCount >= 1) {
          toUnlock.add('first_event_join');
        }
        if (eventsJoinedCheck.contains('event_social_5') && joinedCount >= 5) {
          toUnlock.add('event_social_5');
        }
      }

      // Insertar los nuevos logros desbloqueados
      if (toUnlock.isNotEmpty) {
        await _supabase.from('user_achievements').insert(
          toUnlock
              .map((id) => {'user_id': uid, 'achievement_id': id})
              .toList(),
        );
      }

      return toUnlock;
    } catch (e) {
      debugPrint('Error chequeando logros: $e');
      return [];
    }
  }

  /// Cantidad de logros desbloqueados por el usuario.
  Future<int> unlockedCount() async {
    final uid = _userId;
    if (uid == null) return 0;
    try {
      final result = await _supabase
          .from('user_achievements')
          .select('id')
          .eq('user_id', uid);
      return result.length;
    } catch (_) {
      return 0;
    }
  }
}

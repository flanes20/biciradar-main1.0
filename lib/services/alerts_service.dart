import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class AlertsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Obtener todas las alertas activas
  Future<List<Map<String, dynamic>>> getAlerts() async {
    try {
      debugPrint('📡 Obteniendo alertas...');
      final response = await _supabase
          .from('bike_alerts')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false);

      debugPrint('✅ Alertas obtenidas: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error obteniendo alertas: $e');
      return [];
    }
  }

  // Crear una nueva alerta (VERSIÓN MEJORADA CON MÁS LOGS)
  Future<Map<String, dynamic>?> createAlert({
    required String type,
    required String title,
    required String description,
    required double latitude,
    required double longitude,
    String? locationName,
    String? photoUrl,
  }) async {
    try {
      debugPrint('🚨 ===== INICIANDO CREACIÓN DE ALERTA =====');
      debugPrint('📝 Título: $title');
      debugPrint('📍 Latitud: $latitude');
      debugPrint('📍 Longitud: $longitude');
      debugPrint('🔵 Tipo: $type');

      final userId = _supabase.auth.currentUser?.id;
      final userEmail = _supabase.auth.currentUser?.email;

      debugPrint('👤 User ID: $userId');
      debugPrint('📧 User Email: $userEmail');

      // Obtener nombre de usuario desde profiles
      String userName = 'Usuario';
      if (userId != null) {
        final profile = await _supabase
            .from('profiles')
            .select('username, full_name')
            .eq('id', userId)
            .maybeSingle();

        if (profile != null) {
          userName = profile['username'] ?? profile['full_name'] ?? 'Usuario';
          debugPrint('👤 Nombre de usuario: $userName');
        }
      }

      if (userId == null) {
        debugPrint('❌ Usuario no autenticado');
        return null;
      }

      final alertData = {
        'user_id': userId,
        'user_name': userName,
        'type': type,
        'title': title,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'location_name': locationName ?? 'Ubicación sin nombre',
        'votes_up': 0,
        'votes_down': 0,
        'voters_up': [],
        'voters_down': [],
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
        'photo_url': photoUrl,
      };

      debugPrint('📦 Datos a insertar: $alertData');

      final response = await _supabase
          .from('bike_alerts')
          .insert(alertData)
          .select()
          .single();

      debugPrint('✅ Alerta creada con ID: ${response['id']}');
      debugPrint(
        '📍 Coordenadas guardadas: (${response['latitude']}, ${response['longitude']})',
      );
      debugPrint('📊 Respuesta completa: $response');
      debugPrint('🚨 ===== FIN CREACIÓN EXITOSA =====');

      return response;
    } catch (e) {
      debugPrint('❌ ===== ERROR CREANDO ALERTA =====');
      debugPrint('❌ Tipo de error: ${e.runtimeType}');
      debugPrint('❌ Mensaje: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  // Votar positivo
  Future<bool> voteUp(String alertId) async {
    try {
      debugPrint('👍 Votando positivo a alerta: $alertId');
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Usuario no autenticado');
        return false;
      }

      final alert = await _supabase
          .from('bike_alerts')
          .select()
          .eq('id', alertId)
          .single();

      final votersUp = List<String>.from(alert['voters_up'] ?? []);
      final votersDown = List<String>.from(alert['voters_down'] ?? []);

      if (votersDown.contains(userId)) {
        votersDown.remove(userId);
        debugPrint('🔄 Voto negativo removido');
      }

      if (!votersUp.contains(userId)) {
        votersUp.add(userId);
        debugPrint('✅ Voto positivo agregado');
      } else {
        debugPrint('⚠️ Usuario ya había votado positivo');
        return false;
      }

      await _supabase
          .from('bike_alerts')
          .update({
            'voters_up': votersUp,
            'voters_down': votersDown,
            'votes_up': votersUp.length,
            'votes_down': votersDown.length,
          })
          .eq('id', alertId);

      debugPrint('✅ Voto positivo registrado');
      return true;
    } catch (e) {
      debugPrint('❌ Error votando up: $e');
      return false;
    }
  }

  // Votar negativo
  Future<bool> voteDown(String alertId) async {
    try {
      debugPrint('👎 Votando negativo a alerta: $alertId');
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Usuario no autenticado');
        return false;
      }

      final alert = await _supabase
          .from('bike_alerts')
          .select()
          .eq('id', alertId)
          .single();

      final votersUp = List<String>.from(alert['voters_up'] ?? []);
      final votersDown = List<String>.from(alert['voters_down'] ?? []);

      if (votersUp.contains(userId)) {
        votersUp.remove(userId);
        debugPrint('🔄 Voto positivo removido');
      }

      if (!votersDown.contains(userId)) {
        votersDown.add(userId);
        debugPrint('✅ Voto negativo agregado');
      } else {
        debugPrint('⚠️ Usuario ya había votado negativo');
        return false;
      }

      await _supabase
          .from('bike_alerts')
          .update({
            'voters_up': votersUp,
            'voters_down': votersDown,
            'votes_up': votersUp.length,
            'votes_down': votersDown.length,
          })
          .eq('id', alertId);

      debugPrint('✅ Voto negativo registrado');
      return true;
    } catch (e) {
      debugPrint('❌ Error votando down: $e');
      return false;
    }
  }

  // Quitar voto positivo
  Future<bool> removeVoteUp(String alertId) async {
    try {
      debugPrint('🗑️ Removiendo voto positivo de alerta: $alertId');
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Usuario no autenticado');
        return false;
      }

      final alert = await _supabase
          .from('bike_alerts')
          .select()
          .eq('id', alertId)
          .single();

      final votersUp = List<String>.from(alert['voters_up'] ?? []);

      if (votersUp.contains(userId)) {
        votersUp.remove(userId);
        debugPrint('✅ Voto positivo removido');
      } else {
        debugPrint('⚠️ Usuario no tenía voto positivo');
        return false;
      }

      await _supabase
          .from('bike_alerts')
          .update({'voters_up': votersUp, 'votes_up': votersUp.length})
          .eq('id', alertId);

      return true;
    } catch (e) {
      debugPrint('❌ Error removiendo voto up: $e');
      return false;
    }
  }

  // Quitar voto negativo
  Future<bool> removeVoteDown(String alertId) async {
    try {
      debugPrint('🗑️ Removiendo voto negativo de alerta: $alertId');
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Usuario no autenticado');
        return false;
      }

      final alert = await _supabase
          .from('bike_alerts')
          .select()
          .eq('id', alertId)
          .single();

      final votersDown = List<String>.from(alert['voters_down'] ?? []);

      if (votersDown.contains(userId)) {
        votersDown.remove(userId);
        debugPrint('✅ Voto negativo removido');
      } else {
        debugPrint('⚠️ Usuario no tenía voto negativo');
        return false;
      }

      await _supabase
          .from('bike_alerts')
          .update({'voters_down': votersDown, 'votes_down': votersDown.length})
          .eq('id', alertId);

      return true;
    } catch (e) {
      debugPrint('❌ Error removiendo voto down: $e');
      return false;
    }
  }

  // Eliminar alerta (solo creador)
  Future<bool> deleteAlert(String alertId) async {
    try {
      debugPrint('🗑️ Eliminando alerta: $alertId');
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Usuario no autenticado');
        return false;
      }

      // Borrado definitivo de la fila (más fiable que marcar is_active=false).
      // .select() devuelve las filas afectadas: si viene vacío, el borrado no
      // se aplicó (probablemente por una política RLS de Supabase).
      final res = await _supabase
          .from('bike_alerts')
          .delete()
          .eq('id', alertId)
          .eq('user_id', userId)
          .select();

      final rows = (res as List);
      if (rows.isEmpty) {
        debugPrint('⚠️ deleteAlert: 0 filas afectadas (revisar RLS de Supabase)');
        return false;
      }
      debugPrint('✅ Alerta eliminada: $alertId');
      return true;
    } catch (e) {
      debugPrint('❌ Error eliminando alerta: $e');
      return false;
    }
  }

  // STREAM de alertas en tiempo real (VERSIÓN MEJORADA)
  Stream<List<Map<String, dynamic>>> streamAlerts() {
    debugPrint('📡 Iniciando stream de alertas');
    return _supabase
        .from('bike_alerts')
        .stream(primaryKey: ['id'])
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .map((alerts) {
          debugPrint('📦 Stream recibió ${alerts.length} alertas');
          return List<Map<String, dynamic>>.from(alerts);
        });
  }

  // Obtener alerta por ID
  Future<Map<String, dynamic>?> getAlertById(String alertId) async {
    try {
      debugPrint('🔍 Buscando alerta: $alertId');
      final response = await _supabase
          .from('bike_alerts')
          .select()
          .eq('id', alertId)
          .single();

      return response;
    } catch (e) {
      debugPrint('❌ Error obteniendo alerta: $e');
      return null;
    }
  }

  // Obtener alertas por usuario
  Future<List<Map<String, dynamic>>> getUserAlerts() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      debugPrint('📡 Obteniendo alertas del usuario: $userId');
      final response = await _supabase
          .from('bike_alerts')
          .select()
          .eq('user_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error obteniendo alertas del usuario: $e');
      return [];
    }
  }

  // Actualizar alerta (solo título y descripción)
  Future<bool> updateAlert({
    required String alertId,
    String? title,
    String? description,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final updateData = <String, dynamic>{};
      if (title != null) updateData['title'] = title;
      if (description != null) updateData['description'] = description;

      if (updateData.isEmpty) return false;

      await _supabase
          .from('bike_alerts')
          .update(updateData)
          .eq('id', alertId)
          .eq('user_id', userId);

      debugPrint('✅ Alerta actualizada: $alertId');
      return true;
    } catch (e) {
      debugPrint('❌ Error actualizando alerta: $e');
      return false;
    }
  }
}

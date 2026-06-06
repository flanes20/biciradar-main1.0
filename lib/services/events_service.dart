import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart'; // Para debugPrint
import 'dart:async';

class EventsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Obtener eventos próximos (desde ahora hasta futuro)
  Future<List<Map<String, dynamic>>> getUpcomingEvents() async {
    try {
      final now = DateTime.now().toIso8601String();
      final response = await _supabase
          .from('events')
          .select()
          .gte('event_date', now)
          .eq('is_active', true)
          .order('event_date', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error obteniendo eventos: $e');
      return [];
    }
  }

  // Obtener eventos creados por el usuario actual
  Future<List<Map<String, dynamic>>> getMyEvents() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _supabase
          .from('events')
          .select()
          .eq('user_id', userId)
          .order('event_date', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error obteniendo mis eventos: $e');
      return [];
    }
  }

  // Crear un nuevo evento
  Future<Map<String, dynamic>?> createEvent({
    required String title,
    required String description,
    required DateTime eventDate,
    required String locationName,
    required double latitude,
    required double longitude,
    int? maxParticipants,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      final userEmail = _supabase.auth.currentUser?.email ?? 'Usuario';

      if (userId == null) return null;

      final eventData = {
        'user_id': userId,
        'title': title,
        'description': description,
        'event_date': eventDate.toIso8601String(),
        'location_name': locationName,
        'latitude': latitude,
        'longitude': longitude,
        'max_participants': maxParticipants,
        'participants_count': 1,
        'participants_ids': [userId],
        'created_by': userEmail,
        'is_active': true,
      };

      final response = await _supabase
          .from('events')
          .insert(eventData)
          .select()
          .single();

      return response;
    } catch (e) {
      debugPrint('Error creando evento: $e');
      return null;
    }
  }

  // Unirse a un evento
  Future<bool> joinEvent(String eventId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      // Obtener evento actual
      final response = await _supabase
          .from('events')
          .select()
          .eq('id', eventId);

      if (response.isEmpty) return false;

      final event = response.first;
      final participantsIds = List<String>.from(
        event['participants_ids'] ?? [],
      );

      // Si ya está unido, retornar false
      if (participantsIds.contains(userId)) {
        return false;
      }

      // Verificar límite de participantes
      if (event['max_participants'] != null &&
          participantsIds.length >= event['max_participants']) {
        return false;
      }

      // Agregar usuario
      participantsIds.add(userId);

      await _supabase
          .from('events')
          .update({
            'participants_ids': participantsIds,
            'participants_count': participantsIds.length,
          })
          .eq('id', eventId);

      return true;
    } catch (e) {
      debugPrint('Error uniéndose al evento: $e');
      return false;
    }
  }

  // Salir de un evento
  Future<bool> leaveEvent(String eventId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await _supabase
          .from('events')
          .select()
          .eq('id', eventId);

      if (response.isEmpty) return false;

      final event = response.first;
      final participantsIds = List<String>.from(
        event['participants_ids'] ?? [],
      );

      if (!participantsIds.contains(userId)) {
        return false;
      }

      participantsIds.remove(userId);

      await _supabase
          .from('events')
          .update({
            'participants_ids': participantsIds,
            'participants_count': participantsIds.length,
          })
          .eq('id', eventId);

      return true;
    } catch (e) {
      debugPrint('Error saliendo del evento: $e');
      return false;
    }
  }

  // Cancelar evento (solo creador)
  Future<bool> cancelEvent(String eventId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await _supabase
          .from('events')
          .update({'is_active': false})
          .eq('id', eventId)
          .eq('user_id', userId);

      return true;
    } catch (e) {
      debugPrint('Error cancelando evento: $e');
      return false;
    }
  }

  // Stream de eventos en tiempo real
  Stream<List<Map<String, dynamic>>> streamUpcomingEvents() {
    // ignore: unused_local_variable
    final now = DateTime.now().toIso8601String();
    return _supabase
        .from('events')
        .stream(primaryKey: ['id'])
        .eq('is_active', true) // Filtro corregido
        .map((events) {
          // Filtrar eventos futuros manualmente ya que el stream no soporta .gte
          final futureEvents = events.where((event) {
            final eventDate = DateTime.parse(event['event_date']);
            return eventDate.isAfter(DateTime.now());
          }).toList();

          // Ordenar por fecha
          futureEvents.sort((a, b) {
            final dateA = DateTime.parse(a['event_date']);
            final dateB = DateTime.parse(b['event_date']);
            return dateA.compareTo(dateB);
          });

          return List<Map<String, dynamic>>.from(futureEvents);
        });
  }
}

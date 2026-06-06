import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Caché persistente en disco para alertas, eventos y ciclovías.
/// Las alertas y eventos expiran a los 30 min; las ciclovías no expiran.
class CacheService {
  static const _keyAlerts     = 'cache_alerts_v1';
  static const _keyEvents     = 'cache_events_v1';
  static const _keyCiclovias  = 'cache_ciclovias_v1';
  static const _keyAlertTs    = 'cache_alerts_ts_v1';
  static const _keyEventTs    = 'cache_events_ts_v1';
  static const _maxAge        = Duration(minutes: 30);

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static bool _isExpired(String? tsStr) {
    if (tsStr == null) return true;
    final ts = DateTime.tryParse(tsStr);
    if (ts == null) return true;
    return DateTime.now().difference(ts) > _maxAge;
  }

  static List<Map<String, dynamic>>? _readList(String key) {
    try {
      final raw = _prefs?.getString(key);
      if (raw == null) return null;
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('CacheService: error leyendo $key: $e');
      return null;
    }
  }

  static Future<void> _writeList(
      String key, List<Map<String, dynamic>> data) async {
    try {
      await _prefs?.setString(key, jsonEncode(data));
    } catch (e) {
      debugPrint('CacheService: error escribiendo $key: $e');
    }
  }

  // ── Alertas ───────────────────────────────────────────────────────────────

  static Future<void> saveAlerts(List<Map<String, dynamic>> alerts) async {
    await _writeList(_keyAlerts, alerts);
    await _prefs?.setString(_keyAlertTs, DateTime.now().toIso8601String());
  }

  /// Devuelve las alertas en caché. Si [ignoreExpiry] es false y el caché
  /// venció, devuelve null para que el caller sepa que debe refrescar.
  static List<Map<String, dynamic>>? loadAlerts({bool ignoreExpiry = false}) {
    if (!ignoreExpiry && _isExpired(_prefs?.getString(_keyAlertTs))) return null;
    return _readList(_keyAlerts);
  }

  // ── Eventos ───────────────────────────────────────────────────────────────

  static Future<void> saveEvents(List<Map<String, dynamic>> events) async {
    await _writeList(_keyEvents, events);
    await _prefs?.setString(_keyEventTs, DateTime.now().toIso8601String());
  }

  static List<Map<String, dynamic>>? loadEvents({bool ignoreExpiry = false}) {
    if (!ignoreExpiry && _isExpired(_prefs?.getString(_keyEventTs))) return null;
    return _readList(_keyEvents);
  }

  // ── Ciclovías (sin expiración) ─────────────────────────────────────────────

  static Future<void> saveCiclovias(String geoJson) async {
    try {
      await _prefs?.setString(_keyCiclovias, geoJson);
    } catch (e) {
      debugPrint('CacheService: error guardando ciclovías: $e');
    }
  }

  static String? loadCiclovias() => _prefs?.getString(_keyCiclovias);

  // ── Limpieza ──────────────────────────────────────────────────────────────

  static Future<void> clearAll() async {
    await _prefs?.remove(_keyAlerts);
    await _prefs?.remove(_keyEvents);
    await _prefs?.remove(_keyAlertTs);
    await _prefs?.remove(_keyEventTs);
  }
}

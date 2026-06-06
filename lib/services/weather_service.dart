import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WeatherData {
  final double temperature;
  final double apparentTemperature;
  final double windSpeed;
  final double windDirection;
  final double precipitation;
  final int weatherCode;
  final double uvIndex;
  final double humidity;
  final String cityName;
  final DateTime fetchedAt;

  const WeatherData({
    required this.temperature,
    required this.apparentTemperature,
    required this.windSpeed,
    required this.windDirection,
    required this.precipitation,
    required this.weatherCode,
    required this.uvIndex,
    required this.humidity,
    required this.cityName,
    required this.fetchedAt,
  });

  String get emoji {
    if (weatherCode == 0) return '☀️';
    if (weatherCode <= 2) return '🌤️';
    if (weatherCode == 3) return '☁️';
    if (weatherCode <= 48) return '🌫️';
    if (weatherCode <= 57) return '🌦️';
    if (weatherCode <= 67) return '🌧️';
    if (weatherCode <= 77) return '❄️';
    if (weatherCode <= 82) return '🌧️';
    if (weatherCode <= 99) return '⛈️';
    return '🌡️';
  }

  String get weatherDescription {
    if (weatherCode == 0) return 'Cielo despejado';
    if (weatherCode == 1) return 'Mayormente despejado';
    if (weatherCode == 2) return 'Parcialmente nublado';
    if (weatherCode == 3) return 'Nublado';
    if (weatherCode <= 48) return 'Niebla';
    if (weatherCode <= 57) return 'Llovizna';
    if (weatherCode <= 67) return 'Lluvia';
    if (weatherCode <= 77) return 'Nieve';
    if (weatherCode <= 82) return 'Chaparrones';
    if (weatherCode <= 99) return 'Tormenta eléctrica';
    return 'Desconocido';
  }

  String get windCardinal {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    final idx = ((windDirection + 22.5) / 45).floor() % 8;
    return dirs[idx];
  }

  String get uvLabel {
    if (uvIndex < 3) return 'Bajo';
    if (uvIndex < 6) return 'Moderado';
    if (uvIndex < 8) return 'Alto';
    if (uvIndex < 11) return 'Muy alto';
    return 'Extremo';
  }

  bool get isRaining =>
      (weatherCode >= 51 && weatherCode <= 67) ||
      (weatherCode >= 80 && weatherCode <= 82);

  bool get isThunderstorm => weatherCode >= 95;

  bool get isSnowing => weatherCode >= 71 && weatherCode <= 77;

  bool get isFoggy => weatherCode >= 45 && weatherCode <= 48;

  /// Devuelve lista de recomendaciones para ciclistas.
  List<WeatherRecommendation> get recommendations {
    final recs = <WeatherRecommendation>[];

    if (isThunderstorm) {
      recs.add(const WeatherRecommendation(
        icon: '⛈️',
        text: 'Tormenta eléctrica — no salgas en bici',
        level: RecommendationLevel.danger,
      ));
      return recs; // Suficiente con este
    }

    if (isSnowing) {
      recs.add(const WeatherRecommendation(
        icon: '❄️',
        text: 'Nieve — camino resbaladizo, andá con mucho cuidado',
        level: RecommendationLevel.danger,
      ));
    }

    if (isRaining) {
      final heavy = precipitation > 5 || (weatherCode >= 63 && weatherCode <= 67);
      recs.add(WeatherRecommendation(
        icon: '🌧️',
        text: heavy
            ? 'Lluvia intensa — considerá no salir'
            : 'Llevá impermeable y protegé el calzado',
        level: heavy ? RecommendationLevel.warning : RecommendationLevel.info,
      ));
    }

    if (isFoggy) {
      recs.add(const WeatherRecommendation(
        icon: '🌫️',
        text: 'Niebla — usá luces y ropa reflectante',
        level: RecommendationLevel.warning,
      ));
    }

    if (temperature >= 30 && uvIndex >= 6) {
      recs.add(WeatherRecommendation(
        icon: '🧴',
        text: 'Calor + UV ${uvLabel.toLowerCase()} — ponete bloqueador solar',
        level: RecommendationLevel.warning,
      ));
    } else if (uvIndex >= 6) {
      recs.add(WeatherRecommendation(
        icon: '🧴',
        text: 'UV ${uvLabel.toLowerCase()} (${uvIndex.toStringAsFixed(0)}) — ponete bloqueador solar',
        level: RecommendationLevel.info,
      ));
    }

    if (temperature >= 35) {
      recs.add(const WeatherRecommendation(
        icon: '🥵',
        text: 'Temperatura muy alta — hidratate bien y andá temprano o al atardecer',
        level: RecommendationLevel.warning,
      ));
    }

    if (apparentTemperature < 6) {
      recs.add(WeatherRecommendation(
        icon: '🧥',
        text:
            'Mucho frío (sensación ${apparentTemperature.round()}°) — abrígate bien, cubrí manos y orejas',
        level: RecommendationLevel.warning,
      ));
    } else if (temperature < 12) {
      recs.add(const WeatherRecommendation(
        icon: '🧤',
        text: 'Frío — llevá guantes y ropa de abrigo',
        level: RecommendationLevel.info,
      ));
    } else if (apparentTemperature < temperature - 5) {
      recs.add(WeatherRecommendation(
        icon: '🌡️',
        text:
            'Sensación térmica de ${apparentTemperature.round()}°, más frío de lo que parece',
        level: RecommendationLevel.info,
      ));
    }

    if (windSpeed >= 40) {
      recs.add(WeatherRecommendation(
        icon: '💨',
        text:
            'Viento muy fuerte (${windSpeed.round()} km/h $windCardinal) — pedalear será muy difícil',
        level: RecommendationLevel.warning,
      ));
    } else if (windSpeed >= 25) {
      recs.add(WeatherRecommendation(
        icon: '💨',
        text: 'Viento moderado (${windSpeed.round()} km/h $windCardinal) — tené en cuenta la dirección',
        level: RecommendationLevel.info,
      ));
    }

    if (recs.isEmpty) {
      recs.add(const WeatherRecommendation(
        icon: '✅',
        text: 'Clima ideal para pedalear',
        level: RecommendationLevel.good,
      ));
    }

    return recs;
  }
}

enum RecommendationLevel { good, info, warning, danger }

class WeatherRecommendation {
  final String icon;
  final String text;
  final RecommendationLevel level;

  const WeatherRecommendation({
    required this.icon,
    required this.text,
    required this.level,
  });
}

class WeatherService {
  static final WeatherService _instance = WeatherService._();
  factory WeatherService() => _instance;
  WeatherService._();

  static const _cacheDuration = Duration(minutes: 10);

  WeatherData? _cached;
  DateTime? _lastFetch;
  double? _lastLat;
  double? _lastLng;

  WeatherData? get cached => _cached;

  Future<WeatherData?> fetch(double lat, double lng) async {
    // Devolver cache si es válido y la posición no cambió mucho
    if (_cached != null && _lastFetch != null && _lastLat != null && _lastLng != null) {
      final elapsed = DateTime.now().difference(_lastFetch!);
      final sameLoc =
          (lat - _lastLat!).abs() < 0.02 && (lng - _lastLng!).abs() < 0.02;
      if (elapsed < _cacheDuration && sameLoc) return _cached;
    }

    try {
      final weatherUri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lng'
        '&current=temperature_2m,apparent_temperature,wind_speed_10m,'
        'wind_direction_10m,precipitation,weather_code,uv_index,relative_humidity_2m'
        '&wind_speed_unit=kmh&timezone=auto',
      );

      final weatherRes =
          await http.get(weatherUri).timeout(const Duration(seconds: 8));
      if (weatherRes.statusCode != 200) return _cached;

      final weatherJson = json.decode(weatherRes.body) as Map<String, dynamic>;
      final current = weatherJson['current'] as Map<String, dynamic>;

      // Geocodificación inversa con Nominatim
      String cityName = '';
      try {
        final geoUri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?lat=$lat&lon=$lng&format=json&accept-language=es&zoom=14',
        );
        final geoRes = await http.get(geoUri, headers: {
          'User-Agent': 'biciradar/1.0',
        }).timeout(const Duration(seconds: 5));

        if (geoRes.statusCode == 200) {
          final geoJson = json.decode(geoRes.body) as Map<String, dynamic>;
          final address = geoJson['address'] as Map<String, dynamic>?;
          cityName = (address?['suburb'] as String? ??
                      address?['neighbourhood'] as String? ??
                      address?['city_district'] as String? ??
                      address?['city'] as String? ??
                      address?['town'] as String? ??
                      address?['municipality'] as String? ??
                      '')
              .trim();
        }
      } catch (_) {}

      // Parseo null-safe: si la API omite algún campo, no se cae todo el clima.
      double num2d(dynamic v) => (v as num?)?.toDouble() ?? 0;
      final data = WeatherData(
        temperature: num2d(current['temperature_2m']),
        apparentTemperature: num2d(current['apparent_temperature']),
        windSpeed: num2d(current['wind_speed_10m']),
        windDirection: num2d(current['wind_direction_10m']),
        precipitation: num2d(current['precipitation']),
        weatherCode: (current['weather_code'] as num?)?.toInt() ?? 0,
        uvIndex: num2d(current['uv_index']),
        humidity: num2d(current['relative_humidity_2m']),
        cityName: cityName,
        fetchedAt: DateTime.now(),
      );

      _cached = data;
      _lastFetch = DateTime.now();
      _lastLat = lat;
      _lastLng = lng;

      return data;
    } catch (e) {
      debugPrint('WeatherService error: $e');
      return _cached;
    }
  }
}

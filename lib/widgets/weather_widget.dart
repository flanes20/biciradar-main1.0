import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../services/weather_service.dart';
import '../core/glass.dart';

class WeatherPill extends StatefulWidget {
  final bool isDayMode;
  const WeatherPill({super.key, this.isDayMode = false});

  @override
  State<WeatherPill> createState() => _WeatherPillState();
}

class _WeatherPillState extends State<WeatherPill> {
  final _service = WeatherService();
  WeatherData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    // Reintenta varias veces: al arrancar la app el permiso/fix de GPS puede
    // no estar listo todavía, y antes el clima quedaba en error para siempre.
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        geo.Position? pos = await geo.Geolocator.getLastKnownPosition();
        pos ??= await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 8));

        final data = await _service.fetch(pos.latitude, pos.longitude);
        if (data != null) {
          if (mounted) setState(() { _data = data; _loading = false; });
          return;
        }
      } catch (e) {
        debugPrint('WeatherPill intento $attempt falló: $e');
      }
      // Espera antes de reintentar (da tiempo a que el GPS tenga fix).
      await Future.delayed(const Duration(seconds: 2));
    }

    if (mounted) setState(() => _loading = false);
  }

  void _showDetail() {
    final d = _data;
    if (d == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WeatherSheet(data: d, onRefresh: () async {
        Navigator.pop(context);
        setState(() { _loading = true; _data = null; });
        await _load();
      }),
    );
  }

  bool get _isDayMode => widget.isDayMode;
  Color get _textColor => _isDayMode ? const Color(0xFF1A1A2E) : Colors.white;
  Color get _subtextColor => _isDayMode ? const Color(0xFF555577) : Colors.white60;
  BoxDecoration _pillDecoration() => _isDayMode
      ? BoxDecoration(
          color: Colors.white.withOpacity(0.0), // ya está dentro de la top bar
          borderRadius: BorderRadius.circular(20),
        )
      : glassDecoration(radius: 20, opacity: 0.08, borderOpacity: 0.15);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: 14, height: 14,
        child: CircularProgressIndicator(
          color: _isDayMode ? const Color(0xFF00A86B) : Colors.white54,
          strokeWidth: 1.5,
        ),
      );
    }

    if (_data == null) {
      return GestureDetector(
        onTap: () { setState(() => _loading = true); _load(); },
        child: const Text('🌡️', style: TextStyle(fontSize: 14)),
      );
    }

    final d = _data!;
    return GestureDetector(
      onTap: _showDetail,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(d.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            '${d.temperature.round()}°',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: _textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (d.windSpeed >= 20) ...[
            const SizedBox(width: 5),
            const Text('💨', style: TextStyle(fontSize: 11)),
            Text(
              '${d.windSpeed.round()}',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: _subtextColor,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeatherSheet extends StatelessWidget {
  final WeatherData data;
  final VoidCallback onRefresh;

  const _WeatherSheet({required this.data, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final recs = data.recommendations;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: glassDecoration(radius: 28, opacity: 0.14, borderOpacity: 0.2),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header: ciudad + hora
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (data.cityName.isNotEmpty)
                        Text(
                          data.cityName,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        _formatTime(data.fetchedAt),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onRefresh,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: glassDecoration(radius: 12, opacity: 0.08),
                    child: const Icon(Icons.refresh, color: Colors.white54, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Temperatura principal
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.emoji, style: const TextStyle(fontSize: 48)),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${data.temperature.round()}°C',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    Text(
                      data.weatherDescription,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stats grid
            Container(
              decoration: glassDecoration(radius: 16, opacity: 0.07, borderOpacity: 0.1),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Column(
                children: [
                  _statRow('🌡️', 'Sensación térmica', '${data.apparentTemperature.round()}°C'),
                  _divider(),
                  _statRow('💨', 'Viento', '${data.windSpeed.round()} km/h ${data.windCardinal}'),
                  _divider(),
                  _statRow('💧', 'Humedad', '${data.humidity.round()}%'),
                  _divider(),
                  _statRow('🌧️', 'Precipitación', '${data.precipitation} mm'),
                  _divider(),
                  _statRow(
                    '☀️',
                    'Índice UV',
                    '${data.uvIndex.toStringAsFixed(1)} · ${data.uvLabel}',
                    valueColor: _uvColor(data.uvIndex),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Recomendaciones
            const Text(
              'RECOMENDACIONES',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            ...recs.map((r) => _recTile(r)),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: valueColor ?? Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.white.withOpacity(0.06));

  Widget _recTile(WeatherRecommendation rec) {
    final colors = {
      RecommendationLevel.good: Colors.greenAccent,
      RecommendationLevel.info: Colors.lightBlueAccent,
      RecommendationLevel.warning: Colors.orangeAccent,
      RecommendationLevel.danger: Colors.redAccent,
    };
    final bgColors = {
      RecommendationLevel.good: Colors.greenAccent,
      RecommendationLevel.info: Colors.lightBlueAccent,
      RecommendationLevel.warning: Colors.orangeAccent,
      RecommendationLevel.danger: Colors.redAccent,
    };
    final color = colors[rec.level]!;
    final bg = bgColors[rec.level]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bg.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Text(rec.icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rec.text,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _uvColor(double uv) {
    if (uv < 3) return Colors.greenAccent;
    if (uv < 6) return Colors.yellowAccent;
    if (uv < 8) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return 'Actualizado a las $h:$m';
  }
}

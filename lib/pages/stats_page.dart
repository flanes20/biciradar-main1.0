import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/glass.dart';
import '../services/ride_stats_service.dart';
import '../services/co2_service.dart';

/// Pantalla de progreso del ciclista: hoy, semana, racha y totales.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  static const _accent = Color(0xFF69FF47);

  late List<DayStat> _week;
  late double _today;
  late double _weekKm;
  late double _total;
  late int _streak;
  late int _activeDays;
  late double _bestDay;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _week = RideStatsService.last7Days();
    _today = RideStatsService.todayKm();
    _weekKm = RideStatsService.weekKm();
    _total = RideStatsService.totalKm();
    _streak = RideStatsService.currentStreak();
    _activeDays = RideStatsService.activeDays();
    _bestDay = RideStatsService.bestDayKm();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: kPageGradient,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    _buildTodayHero(),
                    const SizedBox(height: 16),
                    _buildWeekChart(),
                    const SizedBox(height: 16),
                    _buildStatGrid(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'Mis estadísticas',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded, color: _accent),
            tooltip: 'Compartir resumen',
            onPressed: _openShareSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
            onPressed: _refresh,
          ),
        ],
      ),
    );
  }

  void _openShareSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(
        today: _today,
        total: _total,
        weekKm: _weekKm,
        streak: _streak,
        bestDay: _bestDay,
        activeDays: _activeDays,
      ),
    );
  }

  Widget _buildTodayHero() {
    final co2 = Co2Service.savedKg(_today);
    final tree = Co2Service.treeEquivalent(co2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accent.withOpacity(0.18), _accent.withOpacity(0.04)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HOY',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _today.toStringAsFixed(1),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'km',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: _accent,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.eco_rounded, color: _accent, size: 18),
              const SizedBox(width: 6),
              Text(
                '${Co2Service.format(co2)} de CO₂ ahorrado hoy',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (tree.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                tree,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeekChart() {
    final maxKm = _week.fold<double>(
      0.1,
      (m, e) => e.km > m ? e.km : m,
    );
    const labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D']; // weekday 1..7
    final todayKey = RideStatsService.dayKey(DateTime.now());

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      decoration: glassDecoration(radius: 22, opacity: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Últimos 7 días',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${_weekKm.toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: _accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _week.map((d) {
                final isToday = RideStatsService.dayKey(d.date) == todayKey;
                final h = (d.km / maxKm) * 96;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        d.km > 0 ? d.km.toStringAsFixed(1) : '',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: isToday ? _accent : Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 18,
                        height: h < 4 ? 4 : h,
                        decoration: BoxDecoration(
                          color: isToday
                              ? _accent
                              : Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        labels[d.date.weekday - 1],
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: isToday ? _accent : Colors.white38,
                          fontSize: 11,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatGrid() {
    final co2Total = Co2Service.savedKg(_total);
    final tiles = [
      _StatTile('🔥', 'Racha', '$_streak ${_streak == 1 ? "día" : "días"}',
          'seguidos'),
      _StatTile('🏆', 'Mejor día', _bestDay.toStringAsFixed(1), 'km'),
      _StatTile('🛣️', 'Total', _total.toStringAsFixed(1), 'km'),
      _StatTile('📅', 'Días activos', '$_activeDays', 'días'),
      _StatTile('🌱', 'CO₂ total', Co2Service.format(co2Total), 'ahorrado'),
      _StatTile('🚴', 'Esta semana', _weekKm.toStringAsFixed(1), 'km'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: tiles,
    );
  }
}

/// Hoja inferior con la tarjeta de resumen lista para compartir como imagen.
class _ShareSheet extends StatefulWidget {
  final double today;
  final double total;
  final double weekKm;
  final int streak;
  final double bestDay;
  final int activeDays;
  const _ShareSheet({
    required this.today,
    required this.total,
    required this.weekKm,
    required this.streak,
    required this.bestDay,
    required this.activeDays,
  });

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Pequeña espera para garantizar que la tarjeta esté pintada.
      await Future.delayed(const Duration(milliseconds: 60));
      final boundary =
          _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('No se pudo generar la imagen');
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/biciradar_resumen_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());

      final co2 = Co2Service.savedKg(widget.total);
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            '🚴 Mi resumen en BiciRadar: ${widget.total.toStringAsFixed(1)} km '
            'pedaleados y ${Co2Service.format(co2)} de CO₂ ahorrado. '
            '¡Pedalea Santiago! 🌱',
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo compartir: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF50A0A12),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // La tarjeta que se exporta como imagen.
          RepaintBoundary(
            key: _cardKey,
            child: _ShareCard(
              today: widget.today,
              total: widget.total,
              weekKm: widget.weekKm,
              streak: widget.streak,
              bestDay: widget.bestDay,
              activeDays: widget.activeDays,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(_sharing ? 'Generando...' : 'Compartir mi resumen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF69FF47),
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta visual del resumen (diseño pensado para redes sociales).
class _ShareCard extends StatelessWidget {
  final double today;
  final double total;
  final double weekKm;
  final int streak;
  final double bestDay;
  final int activeDays;
  const _ShareCard({
    required this.today,
    required this.total,
    required this.weekKm,
    required this.streak,
    required this.bestDay,
    required this.activeDays,
  });

  static const _accent = Color(0xFF69FF47);

  @override
  Widget build(BuildContext context) {
    final co2 = Co2Service.savedKg(total);
    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E2A18), Color(0xFF06060C)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accent.withOpacity(0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Marca
          Row(
            children: [
              Image.asset(
                'assets/icono_ciclista.png',
                width: 28,
                height: 28,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.directions_bike, color: _accent, size: 26),
              ),
              const SizedBox(width: 8),
              const Text(
                'BiciRadar',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              const Text(
                '🚴',
                style: TextStyle(fontSize: 20),
              ),
            ],
          ),
          const SizedBox(height: 22),
          // Total destacado
          const Text(
            'KILÓMETROS PEDALEADOS',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                total.toStringAsFixed(1),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'km',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: _accent,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white12),
          const SizedBox(height: 18),
          // Mini-stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _miniStat('🔥', '$streak', streak == 1 ? 'día racha' : 'días racha'),
              _miniStat('🏆', bestDay.toStringAsFixed(0), 'mejor día'),
              _miniStat('📅', '$activeDays', 'días activo'),
            ],
          ),
          const SizedBox(height: 18),
          // CO2
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.eco_rounded, color: _accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${Co2Service.format(co2)} de CO₂ que no contaminaste',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'BiciRadar · Pedalea Santiago 🇨🇱',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String emoji, String value, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white54,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final String unit;
  const _StatTile(this.emoji, this.label, this.value, this.unit);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: glassDecoration(radius: 18, opacity: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

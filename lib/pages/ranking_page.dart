import 'package:flutter/material.dart';
import '../core/glass.dart';
import '../services/karma_service.dart';

class RankingPage extends StatefulWidget {
  const RankingPage({super.key});

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final KarmaService _karmaService = KarmaService();

  List<Map<String, dynamic>> _topCyclists = [];
  List<Map<String, dynamic>> _comunasRanking = [];
  bool _loadingCyclists = true;
  bool _loadingComunas = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final cyclists = await _karmaService.getTopCyclists();
    final comunas = await _karmaService.getRankingByComunas();
    if (mounted) {
      setState(() {
        _topCyclists = cyclists;
        _loadingCyclists = false;
        _comunasRanking = comunas;
        _loadingComunas = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: kPageGradient,
        child: Column(
          children: [
            // ── AppBar ─────────────────────────────────────────────
            SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: glassDecoration(radius: 12),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Ranking Local',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _loadingCyclists = true;
                          _loadingComunas = true;
                        });
                        _loadData();
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: glassDecoration(radius: 12),
                        child: const Icon(
                          Icons.refresh,
                          color: Colors.greenAccent,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Tabs ───────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                decoration: glassDecoration(radius: 14),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.greenAccent.withOpacity(0.35)),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.greenAccent,
                  unselectedLabelColor: Colors.white38,
                  labelStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: 13,
                  ),
                  tabs: const [
                    Tab(text: 'Por Comunas'),
                    Tab(text: 'Top Ciclistas'),
                  ],
                ),
              ),
            ),

            // ── Contenido ──────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildComunasTab(),
                  _buildCyclistsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab: Comunas ───────────────────────────────────────────────────────────

  Widget _buildComunasTab() {
    if (_loadingComunas) {
      return const Center(
        child: CircularProgressIndicator(
            color: Colors.greenAccent, strokeWidth: 2),
      );
    }

    if (_comunasRanking.isEmpty) {
      return _buildEmptyState(
        icon: Icons.location_city_outlined,
        title: 'Sin datos de comunas',
        subtitle:
            'Activa el GPS y pedalea para que tu comuna aparezca aquí.\nAsegúrate de reportar alertas con nombre de ubicación.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: Colors.greenAccent,
      backgroundColor: kBgCard,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          // Podio top 3
          if (_comunasRanking.length >= 3) ...[
            _buildPodio(_comunasRanking),
            const SizedBox(height: 16),
          ],
          // Tabla resto
          Container(
            decoration: glassDecoration(radius: 18),
            child: Column(
              children: [
                _tableHeader(
                    ['#', 'Comuna', 'Km totales', 'Ciclistas']),
                const Divider(height: 1, color: Colors.white10),
                ...List.generate(_comunasRanking.length, (i) {
                  final c = _comunasRanking[i];
                  final km =
                      (c['total_km'] as double? ?? 0.0).toStringAsFixed(1);
                  final cyclists = c['cyclists_count'] as int? ?? 0;
                  final alerts = c['alerts_count'] as int? ?? 0;
                  final secondary =
                      cyclists > 0 ? '$cyclists cic.' : '$alerts alertas';
                  return _tableRow(
                    position: i + 1,
                    name: c['commune'] as String? ?? '—',
                    value: '$km km',
                    secondary: secondary,
                    isTop3: i < 3,
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildKmHint(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Tab: Top Ciclistas ─────────────────────────────────────────────────────

  Widget _buildCyclistsTab() {
    if (_loadingCyclists) {
      return const Center(
        child: CircularProgressIndicator(
            color: Colors.greenAccent, strokeWidth: 2),
      );
    }

    if (_topCyclists.isEmpty) {
      return _buildEmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'Sin datos todavía',
        subtitle:
            'Reporta alertas y recibe votos de la comunidad\npara aparecer en el ranking.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: Colors.greenAccent,
      backgroundColor: kBgCard,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          if (_topCyclists.length >= 3) ...[
            _buildCyclistPodio(_topCyclists),
            const SizedBox(height: 16),
          ],
          Container(
            decoration: glassDecoration(radius: 18),
            child: Column(
              children: [
                _tableHeader(['#', 'Ciclista', 'Karma', 'Nivel']),
                const Divider(height: 1, color: Colors.white10),
                ...List.generate(_topCyclists.length, (i) {
                  final c = _topCyclists[i];
                  final karma = c['karma'] as int? ?? 0;
                  final level = KarmaService.getLevel(karma);
                  final name = (c['username'] as String? ?? '').isNotEmpty
                      ? '@${c['username']}'
                      : (c['user_name'] as String? ?? 'Usuario');
                  return _tableRow(
                    position: i + 1,
                    name: name,
                    value: '$karma pts',
                    secondary: '${level.emoji} ${level.title}',
                    isTop3: i < 3,
                    karmaColor: Color(level.colorValue),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Widgets reutilizables ─────────────────────────────────────────────────

  Widget _buildPodio(List<Map<String, dynamic>> list) {
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2do
          Expanded(child: _podioCard(list[1], 2, 100)),
          const SizedBox(width: 8),
          // 1ro
          Expanded(child: _podioCard(list[0], 1, 130)),
          const SizedBox(width: 8),
          // 3ro
          Expanded(child: _podioCard(list[2], 3, 80)),
        ],
      ),
    );
  }

  Widget _buildCyclistPodio(List<Map<String, dynamic>> list) {
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _cyclistPodioCard(list[1], 2, 100)),
          const SizedBox(width: 8),
          Expanded(child: _cyclistPodioCard(list[0], 1, 130)),
          const SizedBox(width: 8),
          Expanded(child: _cyclistPodioCard(list[2], 3, 80)),
        ],
      ),
    );
  }

  Widget _podioCard(Map<String, dynamic> c, int pos, double height) {
    final colors = {
      1: Colors.amber,
      2: Colors.blueGrey,
      3: const Color(0xFFCD7F32),
    };
    final color = colors[pos]!;
    final km = (c['total_km'] as double? ?? 0.0).toStringAsFixed(1);
    return Container(
      height: height,
      decoration: glassDecoration(
        radius: 16,
        tint: color,
        opacity: 0.08,
        borderOpacity: 0.2,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(['🥇', '🥈', '🥉'][pos - 1],
              style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              c['commune'] as String? ?? '—',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$km km',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.7),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cyclistPodioCard(
      Map<String, dynamic> c, int pos, double height) {
    final colors = {
      1: Colors.amber,
      2: Colors.blueGrey,
      3: const Color(0xFFCD7F32),
    };
    final color = colors[pos]!;
    final karma = c['karma'] as int? ?? 0;
    final level = KarmaService.getLevel(karma);
    final name = (c['username'] as String? ?? '').isNotEmpty
        ? '@${c['username']}'
        : (c['user_name'] as String? ?? 'Usuario');
    return Container(
      height: height,
      decoration: glassDecoration(
        radius: 16,
        tint: color,
        opacity: 0.08,
        borderOpacity: 0.2,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(['🥇', '🥈', '🥉'][pos - 1],
              style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              name,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${level.emoji} $karma pts',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.7),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(List<String> cols) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
              width: 28,
              child: Text(cols[0], style: _headerStyle())),
          Expanded(
              flex: 3,
              child: Text(cols[1], style: _headerStyle())),
          Expanded(
              flex: 2,
              child: Text(cols[2],
                  style: _headerStyle(), textAlign: TextAlign.center)),
          Expanded(
              flex: 2,
              child: Text(cols[3],
                  style: _headerStyle(), textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _tableRow({
    required int position,
    required String name,
    required String value,
    required String secondary,
    required bool isTop3,
    Color? karmaColor,
  }) {
    final posColors = [Colors.amber, Colors.blueGrey, const Color(0xFFCD7F32)];
    final posColor = isTop3 ? posColors[position - 1] : Colors.white38;
    return Container(
      decoration: BoxDecoration(
        color: isTop3
            ? posColor.withOpacity(0.04)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              isTop3 ? ['🥇', '🥈', '🥉'][position - 1] : '$position',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: posColor,
                fontSize: isTop3 ? 16 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              name,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: isTop3 ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight:
                    isTop3 ? FontWeight.w600 : FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: karmaColor ?? Colors.greenAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              secondary,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white38,
                fontSize: 11,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white24, size: 56),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white54,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white24,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKmHint() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: glassDecoration(
        radius: 14,
        tint: Colors.blueAccent,
        opacity: 0.06,
        borderOpacity: 0.12,
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline,
              color: Colors.lightBlueAccent, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Los km se acumulan mientras pedaleas con GPS activo. Asegúrate de tener el modo activo encendido.',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white38,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _headerStyle() => const TextStyle(
        fontFamily: 'Poppins',
        color: Colors.white24,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      );
}

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/glass.dart';
import '../core/constants.dart';
import '../services/co2_service.dart';
import '../services/favorites_service.dart';

// ── Modelo de parada ──────────────────────────────────────────────────────────

class Waypoint {
  final double lat;
  final double lng;
  String label;
  Waypoint({required this.lat, required this.lng, this.label = ''});
  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng, 'name': label};
}

// ── Página ────────────────────────────────────────────────────────────────────

class RoutePlannerPage extends StatefulWidget {
  final List<Waypoint>? initial;
  const RoutePlannerPage({super.key, this.initial});

  @override
  State<RoutePlannerPage> createState() => _RoutePlannerPageState();
}

class _RoutePlannerPageState extends State<RoutePlannerPage> {
  MapboxMap? _map;
  final List<Waypoint> _wps = [];
  bool _addMode = false;
  bool _calculating = false;
  double? _distKm;
  double? _durMin;
  bool _routeDrawn = false;

  static const _routeSrcId  = 'rp-route-src';
  static const _routeLyrId  = 'rp-route-lyr';
  static const _wpSrcId     = 'rp-wp-src';
  static const _wpCircleLyr = 'rp-wp-circle';

  final FavoritesService _favSvc = FavoritesService();

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _wps.addAll(widget.initial!);
  }

  // ── Mapa ──────────────────────────────────────────────────────────────────

  void _onMapCreated(MapboxMap map) {
    _map = map;
    _tryGoToUserLocation();
    if (_wps.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 600), _redrawAll);
    }
  }

  Future<void> _tryGoToUserLocation() async {
    try {
      final pos = await geo.Geolocator.getCurrentPosition();
      _map?.setCamera(CameraOptions(
        center: Point(coordinates: Position(pos.longitude, pos.latitude)),
        zoom: 14,
      ));
    } catch (_) {}
  }

  void _onMapTap(MapContentGestureContext ctx) {
    if (!_addMode) return;
    final lat = ctx.point.coordinates.lat.toDouble();
    final lng = ctx.point.coordinates.lng.toDouble();
    final idx = _wps.length + 1;
    setState(() {
      _wps.add(Waypoint(lat: lat, lng: lng, label: 'Parada $idx'));
      _addMode = false;
      _distKm = null;
      _durMin = null;
      _routeDrawn = false;
    });
    _redrawAll();
  }

  // ── Capas (orden: route → circles) ────────────────────────────────────────

  Future<void> _clearLayers() async {
    if (_map == null) return;
    final style = _map!.style;
    try {
      if (await style.styleLayerExists(_wpCircleLyr)) {
        await style.removeStyleLayer(_wpCircleLyr);
      }
      if (await style.styleSourceExists(_wpSrcId)) {
        await style.removeStyleSource(_wpSrcId);
      }
      if (await style.styleLayerExists(_routeLyrId)) {
        await style.removeStyleLayer(_routeLyrId);
      }
      if (await style.styleSourceExists(_routeSrcId)) {
        await style.removeStyleSource(_routeSrcId);
      }
    } catch (e) {
      debugPrint('Error clearLayers: $e');
    }
  }

  /// Redibuja todo: primero la ruta (si existe), luego los pins encima.
  Future<void> _redrawAll({List<dynamic>? routeCoords}) async {
    if (_map == null) return;
    await _clearLayers();
    if (routeCoords != null) await _addRouteLayer(routeCoords);
    await _addWaypointsLayer();
  }

  Future<void> _addRouteLayer(List<dynamic> coords) async {
    final style = _map!.style;
    final positions = coords
        .map((c) => [c[0].toDouble(), c[1].toDouble()])
        .toList();
    final fc = jsonEncode({
      'type': 'Feature',
      'geometry': {'type': 'LineString', 'coordinates': positions},
      'properties': {},
    });
    try {
      await style.addSource(GeoJsonSource(id: _routeSrcId, data: fc));
      await style.addLayer(LineLayer(
        id: _routeLyrId,
        sourceId: _routeSrcId,
        lineColor: Colors.greenAccent.value,
        lineWidth: 5.0,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
        lineOpacity: 0.85,
      ));
    } catch (e) {
      debugPrint('Error addRouteLayer: $e');
    }
  }

  Future<void> _addWaypointsLayer() async {
    if (_wps.isEmpty) return;
    final style = _map!.style;
    final features = _wps.asMap().entries.map((e) => {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [e.value.lng, e.value.lat],
          },
          'properties': {'idx': e.key + 1},
        }).toList();
    final fc = jsonEncode({'type': 'FeatureCollection', 'features': features});
    try {
      await style.addSource(GeoJsonSource(id: _wpSrcId, data: fc));
      await style.addLayer(CircleLayer(
        id: _wpCircleLyr,
        sourceId: _wpSrcId,
        circleRadius: 14.0,
        circleColor: Colors.greenAccent.value,
        circleStrokeWidth: 2.5,
        circleStrokeColor: Colors.white.value,
      ));
    } catch (e) {
      debugPrint('Error addWaypointsLayer: $e');
    }
  }

  void _fitCamera() {
    if (_wps.length < 2 || _map == null) return;
    final midLat =
        _wps.map((w) => w.lat).reduce((a, b) => a + b) / _wps.length;
    final midLng =
        _wps.map((w) => w.lng).reduce((a, b) => a + b) / _wps.length;
    _map!.setCamera(CameraOptions(
      center: Point(coordinates: Position(midLng, midLat)),
      zoom: 12.5,
    ));
  }

  // ── Directions API ────────────────────────────────────────────────────────

  Future<void> _calcRoute() async {
    if (_wps.length < 2) {
      _snack('Añade al menos 2 paradas', error: false);
      return;
    }
    setState(() => _calculating = true);
    try {
      final coords = _wps.map((w) => '${w.lng},${w.lat}').join(';');
      final url =
          'https://api.mapbox.com/directions/v5/mapbox/cycling/$coords'
          '?geometries=geojson&access_token=$kMapboxToken';

      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) throw Exception('Sin rutas');

      final route   = routes[0] as Map<String, dynamic>;
      final distM   = (route['distance'] as num).toDouble();
      final durS    = (route['duration'] as num).toDouble();
      final geom    = route['geometry'] as Map<String, dynamic>;
      final lineCoords = geom['coordinates'] as List;

      setState(() {
        _distKm     = distM / 1000;
        _durMin     = durS / 60;
        _routeDrawn = true;
        _calculating = false;
      });
      await _redrawAll(routeCoords: lineCoords);
      _fitCamera();
    } catch (e) {
      setState(() => _calculating = false);
      _snack('Error calculando ruta: $e');
    }
  }

  // ── Favoritos ─────────────────────────────────────────────────────────────

  void _showSaveFavoriteDialog() {
    String selName = 'Mi ruta';
    String selIcon = '📍';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          final nameCtrl = TextEditingController(text: selName);
          return Container(
            margin: const EdgeInsets.all(16),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              top: 24, left: 20, right: 20,
            ),
            decoration: glassDecoration(radius: 24, opacity: 0.18, borderOpacity: 0.25),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Guardar como favorito',
                    style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: kFavoritePresets.map((p) {
                    final active = selName == p['name'] && selIcon == p['icon'];
                    return GestureDetector(
                      onTap: () => setModal(() {
                        selName = p['name']!;
                        selIcon = p['icon']!;
                        nameCtrl.text = selName;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: glassDecoration(
                          radius: 20,
                          tint: active ? Colors.greenAccent : Colors.white,
                          opacity: active ? 0.15 : 0.05,
                          borderOpacity: active ? 0.35 : 0.1,
                        ),
                        child: Text('${p['icon']} ${p['name']}',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: active ? Colors.greenAccent : Colors.white54,
                              fontSize: 13,
                              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                            )),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  onChanged: (v) => selName = v,
                  style: const TextStyle(fontFamily: 'Poppins', color: Colors.white),
                  decoration: glassInput('Nombre personalizado', Icons.edit_outlined,
                      accentColor: Colors.greenAccent),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final saved = await _favSvc.save(FavoriteRoute(
                        name: selName, icon: selIcon,
                        waypoints: _wps.map((w) => w.toMap()).toList(),
                        distanceKm: _distKm,
                      ));
                      if (mounted) {
                        _snack(
                          saved != null ? 'Guardado como "$selName"' : 'Error al guardar',
                          error: saved == null,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    child: const Text('Guardar favorito'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showFavoritesList() async {
    final favs = await _favSvc.getAll();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: glassDecoration(radius: 24, opacity: 0.18, borderOpacity: 0.25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mis favoritos',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (favs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No tienes rutas guardadas aún',
                    style: TextStyle(fontFamily: 'Poppins', color: Colors.white38, fontSize: 14))),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView(
                  shrinkWrap: true,
                  children: favs.map((f) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text(f.icon, style: const TextStyle(fontSize: 22)),
                    title: Text(f.name, style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: f.distanceKm != null
                        ? Text('${f.distanceKm!.toStringAsFixed(1)} km',
                            style: const TextStyle(fontFamily: 'Poppins', color: Colors.white38, fontSize: 12))
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.play_arrow, color: Colors.greenAccent, size: 20),
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              _wps.clear();
                              _wps.addAll(f.waypoints.map((w) => Waypoint(
                                    lat: (w['lat'] as num).toDouble(),
                                    lng: (w['lng'] as num).toDouble(),
                                    label: w['name'] as String? ?? '',
                                  )));
                              _distKm = f.distanceKm;
                              _routeDrawn = false;
                            });
                            Future.delayed(const Duration(milliseconds: 400), _redrawAll);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          onPressed: () async {
                            if (f.id != null) await _favSvc.delete(f.id!);
                            if (mounted) {
                              Navigator.pop(context);
                              _showFavoritesList();
                            }
                          },
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _snack(String msg, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: error ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _removeWaypoint(int idx) {
    setState(() {
      _wps.removeAt(idx);
      _distKm = null; _durMin = null; _routeDrawn = false;
    });
    _redrawAll();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    MapboxOptions.setAccessToken(kMapboxToken);
    return Scaffold(
      backgroundColor: kBgDark,
      body: Stack(
        children: [
          Positioned.fill(
            child: MapWidget(
              styleUri: autoDarkMapStyle(),
              cameraOptions: CameraOptions(
                center: Point(coordinates: Position(-70.6483, -33.4569)),
                zoom: 13,
              ),
              onMapCreated: _onMapCreated,
              onTapListener: _onMapTap,
            ),
          ),

          // AppBar flotante
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40, height: 40,
                      decoration: glassDecoration(radius: 12, opacity: 0.35, borderOpacity: 0.3),
                      child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: glassDecoration(radius: 14, opacity: 0.35, borderOpacity: 0.3),
                      child: const Text('Planificador de ruta',
                          style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _showFavoritesList,
                    child: Container(
                      width: 40, height: 40,
                      decoration: glassDecoration(radius: 12, tint: Colors.amberAccent, opacity: 0.15, borderOpacity: 0.3),
                      child: const Icon(Icons.star_outline, color: Colors.amberAccent, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Botón añadir parada
          Positioned(
            right: 16, top: 110,
            child: GestureDetector(
              onTap: () => setState(() => _addMode = !_addMode),
              child: Container(
                width: 48, height: 48,
                decoration: glassDecoration(
                  radius: 14,
                  tint: _addMode ? Colors.greenAccent : Colors.white,
                  opacity: _addMode ? 0.25 : 0.15,
                  borderOpacity: _addMode ? 0.45 : 0.2,
                ),
                child: Icon(
                  _addMode ? Icons.touch_app : Icons.add_location_alt_outlined,
                  color: _addMode ? Colors.greenAccent : Colors.white70,
                  size: 22,
                ),
              ),
            ),
          ),

          if (_addMode)
            Positioned(
              top: 170, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: glassDecoration(radius: 20, opacity: 0.45, borderOpacity: 0.35),
                  child: const Text('Toca el mapa para añadir una parada',
                      style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 13)),
                ),
              ),
            ),

          // Panel inferior
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _buildBottomPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF2080810),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),

          if (_wps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('Toca + para añadir paradas a tu ruta',
                  style: TextStyle(fontFamily: 'Poppins', color: Colors.white38, fontSize: 13)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _wps.length,
                onReorder: (oldIdx, newIdx) {
                  setState(() {
                    if (newIdx > oldIdx) newIdx--;
                    final wp = _wps.removeAt(oldIdx);
                    _wps.insert(newIdx, wp);
                  });
                  _redrawAll();
                },
                itemBuilder: (_, i) => _WaypointTile(
                  key: ValueKey('wp-$i-${_wps[i].lat}'),
                  index: i,
                  wp: _wps[i],
                  onRemove: () => _removeWaypoint(i),
                ),
              ),
            ),

          if (_distKm != null) _buildResults(),

          Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, MediaQuery.of(context).padding.bottom + 12),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _wps.length >= 2 && !_calculating ? _calcRoute : null,
                      icon: _calculating
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                          : const Icon(Icons.route, size: 18),
                      label: Text(_calculating ? 'Calculando...' : 'Calcular ruta'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white24,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ),
                ),
                if (_routeDrawn) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _showSaveFavoriteDialog,
                    child: Container(
                      width: 48, height: 48,
                      decoration: glassDecoration(radius: 14, tint: Colors.amberAccent, opacity: 0.12, borderOpacity: 0.25),
                      child: const Icon(Icons.star, color: Colors.amberAccent, size: 22),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() { _wps.clear(); _distKm = null; _durMin = null; _routeDrawn = false; });
                    _redrawAll();
                  },
                  child: Container(
                    width: 48, height: 48,
                    decoration: glassDecoration(radius: 14, tint: Colors.redAccent, opacity: 0.10, borderOpacity: 0.2),
                    child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final co2    = Co2Service.savedKg(_distKm!);
    final co2Str = Co2Service.format(co2);
    final durStr = _durMin != null
        ? (_durMin! >= 60
            ? '${(_durMin! / 60).toStringAsFixed(1)} h'
            : '${_durMin!.toStringAsFixed(0)} min')
        : '—';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: glassDecoration(radius: 16, tint: Colors.greenAccent, opacity: 0.06, borderOpacity: 0.14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statChip(Icons.straighten, '${_distKm!.toStringAsFixed(1)} km', 'Distancia', Colors.greenAccent),
          _statChip(Icons.timer_outlined, durStr, 'Tiempo est.', Colors.lightBlueAccent),
          _statChip(Icons.eco_outlined, co2Str, 'CO₂ ahorra', Colors.lightGreenAccent),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontFamily: 'Poppins', color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        Text(label, style: const TextStyle(fontFamily: 'Poppins', color: Colors.white38, fontSize: 9)),
      ],
    );
  }
}

// ── Tile de parada ────────────────────────────────────────────────────────────

class _WaypointTile extends StatelessWidget {
  final int index;
  final Waypoint wp;
  final VoidCallback onRemove;

  const _WaypointTile({
    required super.key,
    required this.index,
    required this.wp,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: glassDecoration(radius: 12, opacity: 0.06, borderOpacity: 0.12),
      child: Row(
        children: [
          Container(
            width: 24, height: 24,
            decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
            child: Center(
              child: Text('${index + 1}',
                  style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              wp.label.isNotEmpty
                  ? wp.label
                  : '${wp.lat.toStringAsFixed(4)}, ${wp.lng.toStringAsFixed(4)}',
              style: const TextStyle(fontFamily: 'Poppins', color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white38, size: 16),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          const Icon(Icons.drag_handle, color: Colors.white24, size: 18),
        ],
      ),
    );
  }
}

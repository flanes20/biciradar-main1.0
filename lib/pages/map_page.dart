// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        rootBundle,
        HapticFeedback,
        SystemChrome,
        SystemUiOverlayStyle,
        SystemUiMode,
        SystemUiOverlay;
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide ImageSource;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import '../services/presence_service.dart';
import '../services/events_service.dart';
import '../services/alerts_service.dart';
import '../services/co2_service.dart';
import '../services/favorites_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/fall_detection_service.dart';
import '../services/proximity_alert_service.dart';
import '../services/notification_service.dart';
import '../services/ride_stats_service.dart';
import '../pages/auth_page.dart';
import '../pages/events_page.dart';
import '../pages/create_event_page.dart';
import '../pages/event_chat_page.dart';
import '../pages/profile_page.dart';
import '../pages/ranking_page.dart';
import '../pages/route_planner_page.dart';
import '../pages/stats_page.dart';
import '../core/glass.dart';
import '../core/constants.dart';
import '../widgets/weather_widget.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  MapboxMap? mapboxMap;
  StreamSubscription<geo.Position>? _positionStreamSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _cyclistsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _eventsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _alertsSubscription;

  final PresenceService _presenceService = PresenceService();
  final EventsService _eventsService = EventsService();
  final AlertsService _alertsService = AlertsService();

  bool _isFollowingUser = false;
  bool _cicloviasAdded = false;
  String?
  _cicloviasGeoJson; // caché para no re-llamar a Overpass tras cambio de estilo
  final bool _cyclistsLayerAdded = false;
  bool _cyclistsIconAdded = false;
  bool _eventsIconAdded = false;
  bool _alertsIconAdded = false;
  bool _alertsLayerAdded = false;

  // ── Estacionamientos de bici (OSM) ────────────────────────────────────────
  bool _showBikeParkings = true;
  bool _bikeParkingsLoading = false;
  bool _bikeParkingsIconAdded = false;
  List<Map<String, dynamic>> _bikeParkings = [];

  // ── BiciMetro ─────────────────────────────────────────────────────────────
  bool _showBicimetro = true;
  bool _bicimetroIconAdded = false;

  // ── Servicios para bici (inflado / talleres / gasolineras con aire) ───────
  bool _showBikeServices = true;
  bool _autoLayersTriggered = false; // las capas por defecto se cargan 1 vez

  // ── CicloRecreoVía (cierres de calles dominicales para ciclistas) ─────────
  bool _showCicloRecreo = true;
  bool _cicloRecreoIconAdded = false;
  List<Map<String, dynamic>> _cicloRecreoPoints = [];
  static const _crvSrcId = 'ciclorecreovia-src';
  static const _crvLyrId = 'ciclorecreovia-lyr';
  bool _bikeServicesLoading = false;
  bool _bikeServicesIconsAdded = false;
  List<Map<String, dynamic>> _bikeServices = [];

  // ── Dificultad de ruta ───────────────────────────────────────────────────
  String? _routeDifficulty;
  double? _routeElevGain;
  bool _elevationLoading = false;

  // Estado previo de capas opcionales (para restaurar al cerrar la ruta)
  bool _prevShowBikeParkings = false;
  bool _prevShowBicimetro = false;
  bool _prevShowBikeServices = false;

  bool _modoActivo = true;
  bool _autoDarkMode = true;

  bool get _isDayMode => _autoDarkMode && _currentStyle == kMapStyleDay;

  // ── Helpers de estilo día/noche para overlays ─────────────────────────────
  Color get _overlayBg => _isDayMode
      ? Colors.white.withOpacity(0.92)
      : Colors.white.withOpacity(0.12);
  Color get _overlayText => _isDayMode ? const Color(0xFF1A1A2E) : Colors.white;
  Color get _overlaySubtext =>
      _isDayMode ? const Color(0xFF555577) : Colors.white60;

  BoxDecoration _dayNightBox({double radius = 20}) => BoxDecoration(
    color: _overlayBg,
    borderRadius: BorderRadius.circular(radius),
    border: _isDayMode
        ? null
        : Border.all(color: Colors.white.withOpacity(0.18)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(_isDayMode ? 0.12 : 0.30),
        blurRadius: _isDayMode ? 8 : 20,
        offset: const Offset(0, 3),
      ),
    ],
  );

  // Tracking de km
  geo.Position? _lastPosition;
  double _sessionKm = 0;
  double _unsavedKm = 0;

  // Nombre de usuario real (cargado desde profiles) para la presencia en vivo
  String _myUsername = 'Ciclista';

  // Conteo de km en segundo plano (servicio en primer plano con GPS)
  bool _bgTrackingEnabled = false;

  // ── Seguridad: detección de caídas + alertas de proximidad ────────────────
  final FallDetectionService _fallService = FallDetectionService();
  final ProximityAlertService _proximityService = ProximityAlertService();
  bool _fallDetectionEnabled = true;
  bool _proximityAlertsEnabled = true;
  bool _fallDialogOpen = false;

  // ── Modo pasajero: detectar por velocidad si vas en auto/micro/metro ──────
  // Una bici urbana rara vez sostiene >32 km/h; si pasa, preguntamos si es
  // pasajero para NO contar esos km como pedaleo (calidad de las estadísticas).
  bool _isPassenger = false;
  String _passengerVehicle = 'auto'; // 'auto' | 'micro' | 'metro'
  bool _passengerPromptOpen = false;
  DateTime? _highSpeedSince;
  DateTime? _lowSpeedSince;
  DateTime? _passengerSnoozeUntil;

  // Timer para modo oscuro automático
  Timer? _styleCheckTimer;
  String _currentStyle = kMapStyleNight;

  // Timer que vuelve a ocultar la barra de navegación tras revelarla
  Timer? _immersiveTimer;

  // ── Planificador de rutas overlay ─────────────────────────────────────────
  bool _routePlannerOpen = false;
  bool _routeAddMode = false;
  bool _routeCalculating = false;
  final List<_RouteWp> _routeWps = [];
  double? _routeDistKm;
  double? _routeDurMin;
  List<FavoriteRoute> _savedRoutes = [];
  bool _loadingFavorites = false;

  // Progreso de navegación (borrar ruta recorrida)
  bool _navigating = false;
  List<List<double>> _routeCoords = [];
  int _routeProgressIdx = 0;
  static const _rpRouteSrc = 'rp-route-src';
  static const _rpRouteLyr = 'rp-route-lyr';
  static const _rpWpSrc = 'rp-wp-src';
  static const _rpWpLyr = 'rp-wp-lyr';

  // ── Estacionamientos / BiciMetro layer IDs ───────────────────────────────
  static const _parkingSrcId = 'bike-parking-src';
  static const _parkingLyrId = 'bike-parking-lyr';
  static const _parkingIconId = 'bike-parking-icon';
  static const _bicimetroSrcId = 'bicimetro-src';
  static const _bicimetroLyrId = 'bicimetro-lyr';
  static const _bicimetroIconId = 'bicimetro-icon';
  static const _servicesSrcId = 'bike-services-src';
  static const _servicesLyrId = 'bike-services-lyr';

  // ── Estaciones Metro de Santiago con BiciMetro ────────────────────────────
  static const _kBicimetroStations = <Map<String, Object>>[
    {'name': 'Baquedano', 'line': 'L1 / L2', 'lat': -33.4372, 'lng': -70.6326},
    {'name': 'Universidad de Chile', 'line': 'L1', 'lat': -33.4423, 'lng': -70.6503},
    {'name': 'Los Héroes', 'line': 'L1 / L2', 'lat': -33.4514, 'lng': -70.6623},
    {'name': 'Tobalaba', 'line': 'L1 / L4', 'lat': -33.4208, 'lng': -70.5979},
    {'name': 'Salvador', 'line': 'L1', 'lat': -33.4381, 'lng': -70.6142},
    {'name': 'Manuel Montt', 'line': 'L1', 'lat': -33.4274, 'lng': -70.6219},
    {'name': 'La Cisterna', 'line': 'L2 / L4A', 'lat': -33.5316, 'lng': -70.6591},
    {'name': 'Parque O\'Higgins', 'line': 'L2 / L6', 'lat': -33.4591, 'lng': -70.6552},
    {'name': 'Puente Cal y Canto', 'line': 'L2 / L3', 'lat': -33.4391, 'lng': -70.6571},
    {'name': 'Santa Ana', 'line': 'L1 / L5', 'lat': -33.4388, 'lng': -70.6749},
    {'name': 'Ñuble', 'line': 'L5 / L9', 'lat': -33.4618, 'lng': -70.6258},
    {'name': 'Ñuñoa', 'line': 'L6', 'lat': -33.4564, 'lng': -70.6012},
    {'name': 'Vicente Valdés', 'line': 'L4', 'lat': -33.5044, 'lng': -70.5803},
    {'name': 'Quilín', 'line': 'L4', 'lat': -33.4751, 'lng': -70.5672},
    {'name': 'Bicentenario', 'line': 'L6', 'lat': -33.3990, 'lng': -70.6340},
  ];

  // Feedback visual para long press
  OverlayEntry? _longPressOverlay;
  Offset? _longPressTapPosition;

  // Variables para el modo de selección de ubicación (para eventos)
  final bool _isSelectingLocation = false;
  Point? _selectedLocation;
  Map<String, dynamic>? _pendingAlertData;
  bool _isConfirming = false;

  final ValueNotifier<double> _speedNotifier = ValueNotifier(0.0);

  final String _cyclistsSourceId = "cyclists-source";
  final String _cyclistsLayerId = "cyclists-layer";
  final String _cyclistsIconImageId = "bike-icon-others";

  final String _eventsSourceId = "events-source";
  final String _eventsLayerId = "events-layer";
  final String _eventsIconImageId = "event-icon";

  final String _alertsSourceId = "alerts-source";
  final String _alertsLayerId = "alerts-layer";
  final String _alertsIconImageId = "alert-icon";

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<Map<String, dynamic>> _currentEvents = [];
  List<Map<String, dynamic>> _currentAlerts = [];

  // ── Conectividad ──────────────────────────────────────────────────────────
  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;

  // Capa para el pin de selección
  final String _selectionSourceId = "selection-source";
  final String _selectionLayerId = "selection-layer";
  bool _selectionLayerAdded = false;

  // Para long press manual
  Timer? _longPressTimer;
  Point? _longPressPoint;
  final bool _isLongPressDetected = false;

  VoidCallback? get _confirmLocationAndCreateAlert => null;

  GestureLongPressCallback? get _onLongPressFromGesture => null;

  @override
  void initState() {
    super.initState();
    // Oculta SOLO la barra de navegación inferior pero mantiene la barra de
    // estado superior (hora, batería, ícono de ubicación compartida).
    // Un temporizador la vuelve a ocultar tras revelarla (no se queda fija).
    _applyImmersiveBottom();
    _immersiveTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _applyImmersiveBottom(),
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Color(0xFF08080F),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    _currentStyle = _autoDarkMode ? autoDarkMapStyle() : kMapStyleNight;
    _checkLocationPermission();
    _loadMyUsername();
    if (_fallDetectionEnabled) _fallService.start(_onFallDetected);

    // Restaurar preferencia de conteo en segundo plano.
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      if (p.getBool('bg_tracking') ?? false) {
        setState(() => _bgTrackingEnabled = true);
        _restartGps();
      }
    });

    // Cargar el dataset incluido de servicios (Copec, talleres, aire) — no
    // depende de internet ni del GPS, así siempre se muestran por defecto.
    _loadBundledServices().then((d) {
      if (!mounted) return;
      _bikeServices = d;
      if (_showBikeServices) _updateBikeServicesLayer();
    });

    // CicloRecreoVía (cierres dominicales) — dataset incluido.
    _loadCicloRecreo().then((d) {
      if (!mounted) return;
      _cicloRecreoPoints = d;
      if (_showCicloRecreo) _updateCicloRecreoLayer();
    });

    // Cargar caché inmediatamente (datos mientras carga el mapa)
    _loadCachedData();

    // Chequear modo oscuro cada 5 minutos
    _styleCheckTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted) return;
      final newStyle = _autoDarkMode ? autoDarkMapStyle() : kMapStyleNight;
      if (newStyle != _currentStyle && mapboxMap != null) {
        setState(() => _currentStyle = newStyle);
        mapboxMap!.loadStyleURI(newStyle);
      }
    });

    // Monitorear conectividad
    _isOffline = !ConnectivityService.isOnline;
    _connectivitySub = ConnectivityService.stream.listen((online) {
      if (!mounted) return;
      setState(() => _isOffline = !online);
      if (online) {
        // Reconectar streams cuando vuelve la red
        debugPrint('🌐 Red restaurada → reconectando streams');
        _listenToAlerts();
        _listenToEvents();
        _listenToActiveCyclists();
      }
    });
  }

  void _loadCachedData() {
    final cachedAlerts = CacheService.loadAlerts(ignoreExpiry: true);
    final cachedEvents = CacheService.loadEvents(ignoreExpiry: true);
    if (cachedAlerts != null || cachedEvents != null) {
      setState(() {
        if (cachedAlerts != null) _currentAlerts = cachedAlerts;
        if (cachedEvents != null) _currentEvents = cachedEvents;
      });
    }
    final cachedCiclovias = CacheService.loadCiclovias();
    if (cachedCiclovias != null) {
      _cicloviasGeoJson = cachedCiclovias;
    } else {
      // Sin caché → usar las ciclovías incluidas en la app (no dependen de red).
      rootBundle.loadString('assets/data/ciclovias_scl.json').then((geo) {
        if (!mounted || _cicloviasGeoJson != null) return;
        _cicloviasGeoJson = geo;
        _cicloviasAdded = false;
        _addCicloviasLayer();
      }).catchError((Object e) {
        debugPrint('Error ciclovías incluidas: $e');
      });
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _cyclistsSubscription?.cancel();
    _eventsSubscription?.cancel();
    _alertsSubscription?.cancel();
    _connectivitySub?.cancel();
    _speedNotifier.dispose();
    _longPressTimer?.cancel();
    _styleCheckTimer?.cancel();
    _immersiveTimer?.cancel();
    _fallService.stop();
    _presenceService.clearMyLocation(); // marcar offline al salir
    // Restaurar las barras del sistema al salir del mapa.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Detección de caídas → auto-SOS ─────────────────────────────────────────

  /// Se invoca cuando el acelerómetro detecta una posible caída. Muestra una
  /// cuenta regresiva; si el usuario no la cancela, llama a Carabineros (133).
  void _onFallDetected() {
    if (!mounted || _fallDialogOpen) return;
    _fallDialogOpen = true;
    HapticFeedback.heavyImpact(); // vibración para llamar la atención
    NotificationService.instance.showEmergencyAlert(
      title: '⚠️ Posible caída detectada',
      body: 'Confirma que estás bien o se llamará a emergencias.',
    );
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FallCountdownDialog(
        onCall: (number) async {
          final uri = Uri(scheme: 'tel', path: number);
          if (await canLaunchUrl(uri)) await launchUrl(uri);
        },
      ),
    ).whenComplete(() => _fallDialogOpen = false);
  }

  // ── Alertas push de proximidad ──────────────────────────────────────────────

  /// Revisa si el ciclista entró en el radio de algún incidente activo y, de
  /// ser así, dispara una notificación local (una sola vez por alerta).
  void _checkProximityAlerts(geo.Position position) {
    if (_currentAlerts.isEmpty) return;
    final nearby = _proximityService.alertsToNotify(
      position.latitude,
      position.longitude,
      _currentAlerts,
    );
    for (final alert in nearby) {
      final type = alert['type'] as String? ?? 'other';
      NotificationService.instance.showProximityAlert(
        id: (alert['id']?.toString() ?? '').hashCode & 0x7fffffff,
        title: '⚠️ Incidente cerca: ${_alertTypeLabel(type)}',
        body: alert['title'] as String? ?? 'Hay un reporte en tu trayecto',
      );
    }
  }

  String _alertTypeLabel(String type) {
    switch (type) {
      case 'danger':
        return 'Peligro';
      case 'theft':
        return 'Robo';
      case 'construction':
        return 'Obras';
      case 'accident':
        return 'Accidente';
      default:
        return 'Aviso';
    }
  }

  /// Oculta la barra de navegación inferior dejando visible solo la superior.
  void _applyImmersiveBottom() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
  }

  Future<void> _checkLocationPermission() async {
    final status = await Permission.location.status;
    if (status.isDenied) {
      await Permission.location.request();
    }
  }

  /// Carga el nombre de usuario real desde la tabla `profiles` para mostrarlo
  /// en la presencia en vivo (antes estaba hardcodeado como "Grace").
  Future<void> _loadMyUsername() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Fallback inmediato con los metadatos del registro
      final metaName = user.userMetadata?['username'] as String?;
      if (metaName != null && metaName.trim().isNotEmpty) {
        _myUsername = metaName.trim();
      }

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('username, full_name')
          .eq('id', user.id)
          .maybeSingle();

      final name = (profile?['username'] as String?)?.trim();
      final fullName = (profile?['full_name'] as String?)?.trim();
      if (name != null && name.isNotEmpty) {
        _myUsername = name;
      } else if (fullName != null && fullName.isNotEmpty) {
        _myUsername = fullName;
      }
    } catch (e) {
      debugPrint('No se pudo cargar el username: $e');
    }
  }

  void _stopFollowingByGesture() {
    if (_isFollowingUser && mounted) {
      setState(() => _isFollowingUser = false);
    }
  }

  /// Ajusta la precisión del GPS según el estado.
  /// Navegando o siguiendo al usuario: máxima precisión + filtro 5m (cámara
  /// fluida). Idle: precisión alta + filtro 15m (ahorra ~50% batería).
  geo.LocationSettings _gpsSettings() {
    final bool precise = _navigating || _isFollowingUser;
    final accuracy = precise
        ? geo.LocationAccuracy.bestForNavigation
        : geo.LocationAccuracy.high;
    final filter = precise ? 5 : 15;

    // Con tracking en segundo plano: servicio en primer plano (notificación
    // fija) para seguir contando km aunque la app no esté visible.
    if (_bgTrackingEnabled) {
      return geo.AndroidSettings(
        accuracy: accuracy,
        distanceFilter: filter,
        foregroundNotificationConfig: const geo.ForegroundNotificationConfig(
          notificationTitle: 'BiciRadar',
          notificationText: 'Contando tus kilómetros 🚴',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return geo.LocationSettings(accuracy: accuracy, distanceFilter: filter);
  }

  void _startFollowing() {
    if (_positionStreamSubscription != null) return;
    _positionStreamSubscription = geo.Geolocator.getPositionStream(
      locationSettings: _gpsSettings(),
    ).listen((position) async {
      if (!mounted) return;

      final curSpeedKmh = position.speed < 0 ? 0.0 : position.speed * 3.6;
      _speedNotifier.value = curSpeedKmh;

      // Detección de modo pasajero (auto/micro/metro) según la velocidad.
      _maybeHandlePassengerMode(curSpeedKmh);

      // Tracking de km — solo cuenta cuando el usuario realmente se mueve,
      // para no sumar el "ruido" del GPS estando quieto. En modo pasajero NO
      // se cuenta (esos km no son pedaleo).
      if (_modoActivo && !_isPassenger && _lastPosition != null) {
        final distM = geo.Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        final speedKmh = position.speed < 0 ? 0 : position.speed * 3.6;
        final accuracyOk = position.accuracy <= 30; // descartar fixes imprecisos
        final isMoving = speedKmh >= 3.0;            // ~ritmo de pedaleo lento
        // Cuenta solo desplazamientos reales (8 m–200 m), con buena precisión
        // y velocidad de movimiento; así el jitter estando detenido no suma.
        if (distM >= 8 && distM < 200 && accuracyOk && isMoving) {
          _sessionKm += distM / 1000;
          _unsavedKm += distM / 1000;
          if (_unsavedKm >= 0.5) {
            _saveKmToProfile(_unsavedKm); // total histórico (Supabase)
            RideStatsService.addKm(_unsavedKm); // registro diario local
            _unsavedKm = 0;
          }
        }
      }
      _lastPosition = position;

      // Primer fix de GPS → cargar las capas por defecto alrededor del usuario.
      _maybeAutoLoadLayers();

      if (_navigating && _routeCoords.isNotEmpty) {
        _advanceRouteProgress(position.latitude, position.longitude);
      }

      // Alertas push de proximidad: avisar al acercarse a un incidente activo.
      if (_proximityAlertsEnabled) {
        _checkProximityAlerts(position);
      }

      if (_modoActivo) {
        await _presenceService.upsertMyLocation(
          position: position,
          username: _myUsername,
        );
      }

      if (mapboxMap != null && _isFollowingUser) {
        _moveCameraInstant(position);
      }
    });
  }

  /// Reinicia el stream de GPS con la configuración correcta para el estado actual.
  void _restartGps() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _startFollowing();
  }

  // ── Modo pasajero ─────────────────────────────────────────────────────────

  /// Evalúa la velocidad para entrar/salir del modo pasajero.
  void _maybeHandlePassengerMode(double speedKmh) {
    const highKmh = 32.0; // sobre esto, difícil que sea pedaleo
    const lowKmh = 6.0; // bajo esto, probablemente ya bajaste del vehículo
    final now = DateTime.now();

    if (_isPassenger) {
      _highSpeedSince = null;
      // Salir automáticamente si la velocidad baja de forma sostenida.
      if (speedKmh < lowKmh) {
        _lowSpeedSince ??= now;
        if (now.difference(_lowSpeedSince!) > const Duration(seconds: 15)) {
          _exitPassengerMode(auto: true);
        }
      } else {
        _lowSpeedSince = null;
      }
      return;
    }

    // No es pasajero: ¿lleva varios segundos a velocidad de vehículo?
    if (speedKmh >= highKmh) {
      _highSpeedSince ??= now;
      final sustained =
          now.difference(_highSpeedSince!) > const Duration(seconds: 6);
      final snoozed = _passengerSnoozeUntil != null &&
          now.isBefore(_passengerSnoozeUntil!);
      if (sustained && !_passengerPromptOpen && !snoozed && mounted) {
        _showPassengerPrompt();
      }
    } else {
      _highSpeedSince = null;
    }
  }

  Future<void> _showPassengerPrompt() async {
    _passengerPromptOpen = true;
    HapticFeedback.mediumImpact();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (_) => _PassengerPrompt(speedKmh: _speedNotifier.value.round()),
    );
    _passengerPromptOpen = false;
    if (!mounted) return;

    if (result == null || result == 'bici') {
      // Sigo pedaleando: no volver a preguntar por un rato.
      _passengerSnoozeUntil = DateTime.now().add(const Duration(minutes: 5));
      _highSpeedSince = null;
    } else {
      _enterPassengerMode(result); // 'auto' | 'micro' | 'metro'
    }
  }

  void _enterPassengerMode(String vehicle) {
    // Guardar km pendientes antes de dejar de contar.
    if (_unsavedKm > 0) {
      _saveKmToProfile(_unsavedKm);
      RideStatsService.addKm(_unsavedKm);
      _unsavedKm = 0;
    }
    _fallService.stop(); // sin falsos positivos por frenadas del vehículo
    setState(() {
      _isPassenger = true;
      _passengerVehicle = vehicle;
      _lowSpeedSince = null;
      _highSpeedSince = null;
    });
  }

  void _exitPassengerMode({bool auto = false}) {
    if (_fallDetectionEnabled) _fallService.start(_onFallDetected);
    setState(() {
      _isPassenger = false;
      _lowSpeedSince = null;
      _highSpeedSince = null;
      // Tras salir, deja un pequeño margen antes de volver a preguntar.
      _passengerSnoozeUntil =
          DateTime.now().add(const Duration(seconds: 30));
    });
    if (auto && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🚴 De vuelta en modo ciclista'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  ({String emoji, String label}) _vehicleInfo(String v) {
    switch (v) {
      case 'micro':
        return (emoji: '🚌', label: 'Micro');
      case 'metro':
        return (emoji: '🚇', label: 'Metro');
      default:
        return (emoji: '🚗', label: 'Auto');
    }
  }

  void _listenToActiveCyclists() {
    _cyclistsSubscription?.cancel();
    _cyclistsSubscription = _presenceService.streamActiveCyclists().listen((
      cyclists,
    ) async {
      await _updateCyclistsLayer(cyclists);
    });
  }

  void _listenToEvents() {
    _eventsSubscription?.cancel();
    _eventsSubscription = _eventsService.streamUpcomingEvents().listen(
      (events) {
        debugPrint('📦 Eventos recibidos: ${events.length}');
        setState(() => _currentEvents = events);
        _updateEventsLayer(events);
        CacheService.saveEvents(events); // Guardar en caché
      },
      onError: (error) {
        debugPrint('❌ Error stream eventos: $error');
        // Intentar usar caché si hay error de red
        final cached = CacheService.loadEvents(ignoreExpiry: true);
        if (cached != null && mounted) {
          setState(() => _currentEvents = cached);
          _updateEventsLayer(cached);
        }
      },
    );
  }

  void _listenToAlerts() {
    _alertsSubscription?.cancel();
    _alertsSubscription = _alertsService.streamAlerts().listen(
      (alerts) {
        debugPrint('🚨 Alertas recibidas: ${alerts.length}');
        setState(() => _currentAlerts = alerts);
        _updateAlertsLayer(alerts);
        CacheService.saveAlerts(alerts); // Guardar en caché
      },
      onError: (error) {
        debugPrint('❌ Error stream alertas: $error');
        // Intentar usar caché si hay error de red
        final cached = CacheService.loadAlerts(ignoreExpiry: true);
        if (cached != null && mounted) {
          setState(() => _currentAlerts = cached);
          _updateAlertsLayer(cached);
        }
      },
    );
  }

  void _moveCameraInstant(geo.Position position) {
    if (mapboxMap == null) return;
    mapboxMap!.setCamera(
      CameraOptions(
        center: Point(
          coordinates: Position(position.longitude, position.latitude),
        ),
        zoom: 17.5,
        pitch: 0.0,
      ),
    );
  }

  Future<void> _setupUserPuck() async {
    if (mapboxMap == null) return;
    try {
      final ByteData bytes = await rootBundle.load("assets/icono_ciclista.png");
      final Uint8List bikeBytes = bytes.buffer.asUint8List();
      await mapboxMap!.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          puckBearingEnabled: true,
          puckBearing: PuckBearing.HEADING,
          showAccuracyRing: false,
          pulsingEnabled: false,
          locationPuck: LocationPuck(
            locationPuck2D: DefaultLocationPuck2D(
              topImage: bikeBytes,
              bearingImage: Uint8List.fromList([]),
              shadowImage: Uint8List.fromList([]),
              scaleExpression:
                  '["interpolate",["linear"],["zoom"],0,0.40,22,0.40]',
              opacity: 1.0,
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint("Error configurando puck personalizado: $e");
    }
  }

  Future<void> _ensureCyclistsIcon() async {
    if (mapboxMap == null || _cyclistsIconAdded) return;
    try {
      final style = mapboxMap!.style;
      if (await style.hasStyleImage(_cyclistsIconImageId)) {
        _cyclistsIconAdded = true;
        return;
      }
      final ByteData data = await rootBundle.load("assets/icono_ciclista.png");
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 64,
        targetHeight: 64,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return;
      await style.addStyleImage(
        _cyclistsIconImageId,
        1.0,
        MbxImage(
          width: frame.image.width,
          height: frame.image.height,
          data: byteData.buffer.asUint8List(),
        ),
        false, [], [], null,
      );
      _cyclistsIconAdded = true;
    } catch (e) {
      debugPrint("Error agregando icono de ciclistas: $e");
    }
  }

  Future<void> _ensureEventsIcon() async {
    if (mapboxMap == null || _eventsIconAdded) return;
    try {
      final style = mapboxMap!.style;
      if (await style.hasStyleImage(_eventsIconImageId)) {
        _eventsIconAdded = true;
        return;
      }
      // Decodificar PNG → bytes RGBA crudos que requiere MbxImage
      final ByteData data = await rootBundle.load("assets/icono_ciclista.png");
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 64,
        targetHeight: 64,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return;
      await style.addStyleImage(
        _eventsIconImageId,
        1.0,
        MbxImage(
          width: frame.image.width,
          height: frame.image.height,
          data: byteData.buffer.asUint8List(),
        ),
        false, [], [], null,
      );
      _eventsIconAdded = true;
      debugPrint('✅ Ícono de eventos registrado');
    } catch (e) {
      debugPrint("Error agregando icono de eventos: $e");
    }
  }

  /// Dibuja un círculo de color con el ícono Material encima y lo devuelve como PNG.
  Future<Uint8List> _renderAlertIcon(Color color, IconData iconData) async {
    const double size = 80;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Sombra exterior
    final shadowPaint = ui.Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawCircle(
      const ui.Offset(size / 2, size / 2 + 3),
      size / 2 - 2,
      shadowPaint,
    );

    // Relleno del círculo
    final fillPaint = ui.Paint()..color = color;
    canvas.drawCircle(
      const ui.Offset(size / 2, size / 2),
      size / 2 - 2,
      fillPaint,
    );

    // Borde blanco
    final borderPaint = ui.Paint()
      ..color = Colors.white
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(
      const ui.Offset(size / 2, size / 2),
      size / 2 - 2,
      borderPaint,
    );

    // Ícono Material centrado
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: 38,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      ui.Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Dibuja un pin tipo "globito" (cabeza circular con ícono + punta abajo).
  /// La punta apunta exactamente a la ubicación (usar iconAnchor BOTTOM).
  Future<Uint8List> _renderPinIcon(Color color, IconData iconData) async {
    const double w = 84;
    const double h = 108;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final center = const ui.Offset(w / 2, w / 2 + 2); // centro de la cabeza
    final headR = w / 2 - 6;
    final tip = const ui.Offset(w / 2, h - 3); // punta inferior

    // Sombra
    final shadow = ui.Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawCircle(center.translate(0, 3), headR, shadow);

    // Cuerpo del pin: triángulo de color hacia la punta + aro de color
    final body = ui.Path()
      ..moveTo(center.dx - headR * 0.6, center.dy + headR * 0.72)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(center.dx + headR * 0.6, center.dy + headR * 0.72)
      ..close();
    final colorPaint = ui.Paint()..color = color;
    canvas.drawPath(body, colorPaint);
    canvas.drawCircle(center, headR, colorPaint); // aro de color exterior

    // Cabeza blanca (badge) donde va el ícono/logo, para que resalte
    final whitePaint = ui.Paint()..color = Colors.white;
    canvas.drawCircle(center, headR - 5, whitePaint);

    // Ícono en el color de la categoría, centrado en la cabeza blanca
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: 38,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      ui.Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  Future<void> _ensureAlertsIcon() async {
    if (mapboxMap == null) return;
    try {
      final style = mapboxMap!.style;

      final alertTypes = <String, (Color, IconData)>{
        'danger': (Colors.red, Icons.warning_rounded),
        'theft': (Colors.purple, Icons.no_accounts),
        'construction': (Colors.orange, Icons.construction),
        'accident': (Colors.deepOrange, Icons.car_crash),
        'other': (Colors.blue, Icons.info),
      };

      for (final entry in alertTypes.entries) {
        final imageId = 'alert-icon-${entry.key}';
        if (await style.hasStyleImage(imageId)) continue;

        final bytes = await _renderAlertIcon(entry.value.$1, entry.value.$2);
        await style.addStyleImage(
          imageId,
          1.0, // scale 1:1 → 80dp nativos
          MbxImage(width: 80, height: 80, data: bytes),
          false,
          [],
          [],
          null,
        );
        debugPrint('✅ Ícono de alerta "$imageId" registrado');
      }

      _alertsIconAdded = true;
    } catch (e) {
      debugPrint("Error agregando íconos de alertas: $e");
    }
  }

  Future<void> _removeSelectionLayer() async {
    if (mapboxMap == null) return;
    try {
      final style = mapboxMap!.style;
      if (await style.styleLayerExists(_selectionLayerId)) {
        await style.removeStyleLayer(_selectionLayerId);
      }
      if (await style.styleSourceExists(_selectionSourceId)) {
        await style.removeStyleSource(_selectionSourceId);
      }
      _selectionLayerAdded = false;
    } catch (e) {
      debugPrint('❌ Error removiendo capa de selección: $e');
    }
  }

  // ✅ Mostrar formulario de alerta en el punto de long press
  void _showAlertFormAtLocation(Point point) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _SimpleAlertFormDialog(point: point),
    );

    if (result != null && mounted) {
      await _createAlertAtLocation(point, result);
    }
  }

  // ✅ Crear alerta directamente en la ubicación
  Future<void> _createAlertAtLocation(
    Point point,
    Map<String, dynamic> alertData,
  ) async {
    if (_isConfirming) return;
    _isConfirming = true;

    try {
      // Subir foto a Supabase Storage si existe
      String? photoUrl;
      final photoFile = alertData['photoFile'] as File?;
      if (photoFile != null) {
        try {
          final userId =
              Supabase.instance.client.auth.currentUser?.id ?? 'anon';
          final fileName =
              '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
          await Supabase.instance.client.storage
              .from('alert-photos')
              .upload(fileName, photoFile);
          photoUrl = Supabase.instance.client.storage
              .from('alert-photos')
              .getPublicUrl(fileName);
          debugPrint('📸 Foto subida: $photoUrl');
        } catch (e) {
          debugPrint('⚠️ Error subiendo foto (continúa sin foto): $e');
        }
      }

      final newAlert = await _alertsService.createAlert(
        type: alertData['type'],
        title: alertData['title'],
        description: alertData['description'],
        latitude: point.coordinates.lat.toDouble(),
        longitude: point.coordinates.lng.toDouble(),
        locationName: alertData['locationName'],
        photoUrl: photoUrl,
      );

      if (newAlert != null) {
        setState(() {
          _currentAlerts.add(newAlert);
        });
        await _updateAlertsLayer(_currentAlerts);

        // Mostrar pin verde temporalmente
        await _showTemporaryPin(point);

        debugPrint('✅ Alerta guardada en BD y mostrada en mapa');

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Alerta creada con éxito'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error creando alerta: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      _isConfirming = false;
    }
  }

  // ✅ Mostrar pin temporal para feedback visual
  Future<void> _showTemporaryPin(Point point) async {
    if (mapboxMap == null) return;
    try {
      final style = mapboxMap!.style;

      final features = [
        {
          "type": "Feature",
          "properties": {"type": "temp_pin"},
          "geometry": {
            "type": "Point",
            "coordinates": [point.coordinates.lng, point.coordinates.lat],
          },
        },
      ];

      final featureCollection = jsonEncode({
        "type": "FeatureCollection",
        "features": features,
      });

      final tempSourceId = "temp-pin-source";
      final tempLayerId = "temp-pin-layer";

      if (await style.styleSourceExists(tempSourceId)) {
        await style.removeStyleSource(tempSourceId);
      }
      if (await style.styleLayerExists(tempLayerId)) {
        await style.removeStyleLayer(tempLayerId);
      }

      await style.addSource(
        GeoJsonSource(id: tempSourceId, data: featureCollection),
      );

      await style.addLayer(
        SymbolLayer(
          id: tempLayerId,
          sourceId: tempSourceId,
          iconImage: "marker-15",
          iconSize: 2.5,
          iconColor: Colors.greenAccent.value,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );

      // Eliminar el pin después de 2 segundos
      Future.delayed(const Duration(seconds: 2), () async {
        if (await style.styleLayerExists(tempLayerId)) {
          await style.removeStyleLayer(tempLayerId);
        }
        if (await style.styleSourceExists(tempSourceId)) {
          await style.removeStyleSource(tempSourceId);
        }
      });
    } catch (e) {
      debugPrint('❌ Error mostrando pin temporal: $e');
    }
  }

  Future<void> _updateSelectionLayer() async {
    if (mapboxMap == null || _selectedLocation == null) return;

    try {
      final style = mapboxMap!.style;

      final features = [
        {
          "type": "Feature",
          "properties": {"type": "selection"},
          "geometry": {
            "type": "Point",
            "coordinates": [
              _selectedLocation!.coordinates.lng,
              _selectedLocation!.coordinates.lat,
            ],
          },
        },
      ];

      final featureCollection = jsonEncode({
        "type": "FeatureCollection",
        "features": features,
      });

      if (await style.styleSourceExists(_selectionSourceId)) {
        await style.removeStyleSource(_selectionSourceId);
      }
      if (await style.styleLayerExists(_selectionLayerId)) {
        await style.removeStyleLayer(_selectionLayerId);
      }

      await style.addSource(
        GeoJsonSource(id: _selectionSourceId, data: featureCollection),
      );

      await style.addLayer(
        SymbolLayer(
          id: _selectionLayerId,
          sourceId: _selectionSourceId,
          iconImage: "marker-15",
          iconSize: 2.5,
          iconColor: Colors.greenAccent.value,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );

      _selectionLayerAdded = true;
      debugPrint('✅ Pin de selección actualizado');
    } catch (e) {
      debugPrint('❌ Error actualizando capa de selección: $e');
    }
  }

  Future<void> _updateEventsLayer(List<Map<String, dynamic>> events) async {
    if (mapboxMap == null) {
      debugPrint('⚠️ mapboxMap es null, no se puede actualizar eventos');
      return;
    }
    try {
      final style = mapboxMap!.style;
      await _ensureEventsIcon();

      final features = <Map<String, dynamic>>[];
      for (var event in events) {
        final lat = (event["latitude"] as num?)?.toDouble();
        final lng = (event["longitude"] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        features.add({
          "type": "Feature",
          "properties": {"id": event["id"], "title": event["title"]},
          "geometry": {
            "type": "Point",
            "coordinates": [lng, lat],
          },
        });
      }

      if (features.isEmpty) {
        if (await style.styleLayerExists(_eventsLayerId)) {
          await style.removeStyleLayer(_eventsLayerId);
        }
        if (await style.styleSourceExists(_eventsSourceId)) {
          await style.removeStyleSource(_eventsSourceId);
        }
        return;
      }

      final featureCollection = jsonEncode({
        "type": "FeatureCollection",
        "features": features,
      });

      if (await style.styleLayerExists(_eventsLayerId)) {
        await style.removeStyleLayer(_eventsLayerId);
      }
      if (await style.styleSourceExists(_eventsSourceId)) {
        await style.removeStyleSource(_eventsSourceId);
      }

      await style.addSource(
        GeoJsonSource(id: _eventsSourceId, data: featureCollection),
      );

      await style.addLayer(
        SymbolLayer(
          id: _eventsLayerId,
          sourceId: _eventsSourceId,
          iconImage: _eventsIconImageId,
          iconSize: 0.4,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconColor: Colors.green.value,
        ),
      );
    } catch (e) {
      debugPrint('❌ Error actualizando eventos: $e');
    }
  }

  Future<void> _updateAlertsLayer(List<Map<String, dynamic>> alerts) async {
    if (mapboxMap == null) return;
    try {
      final style = mapboxMap!.style;
      await _ensureAlertsIcon();

      final features = <Map<String, dynamic>>[];
      for (var alert in alerts) {
        final lat = (alert["latitude"] as num?)?.toDouble();
        final lng = (alert["longitude"] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final alertType = alert["type"] as String? ?? 'other';
        final validTypes = {'danger', 'theft', 'construction', 'accident'};
        final iconId = validTypes.contains(alertType)
            ? 'alert-icon-$alertType'
            : 'alert-icon-other';

        features.add({
          "type": "Feature",
          "properties": {
            "id": alert["id"],
            "type": alertType,
            "icon_id": iconId,
            "title": alert["title"],
            "description": alert["description"],
            "user_name": alert["user_name"],
            "votes_up": alert["votes_up"],
            "votes_down": alert["votes_down"],
          },
          "geometry": {
            "type": "Point",
            "coordinates": [lng, lat],
          },
        });
      }

      if (features.isEmpty) {
        if (await style.styleLayerExists(_alertsLayerId)) {
          await style.removeStyleLayer(_alertsLayerId);
        }
        if (await style.styleSourceExists(_alertsSourceId)) {
          await style.removeStyleSource(_alertsSourceId);
        }
        _alertsLayerAdded = false;
        return;
      }

      final featureCollection = jsonEncode({
        "type": "FeatureCollection",
        "features": features,
      });

      // IMPORTANTE: primero capa, después source (orden obligatorio en Mapbox)
      if (await style.styleLayerExists(_alertsLayerId)) {
        await style.removeStyleLayer(_alertsLayerId);
      }
      if (await style.styleSourceExists(_alertsSourceId)) {
        await style.removeStyleSource(_alertsSourceId);
      }

      await style.addSource(
        GeoJsonSource(id: _alertsSourceId, data: featureCollection),
      );

      await style.addLayer(
        SymbolLayer(
          id: _alertsLayerId,
          sourceId: _alertsSourceId,
          iconImage: 'alert-icon-other', // se sobreescribe abajo
          iconSize: 0.35, // 80dp × 0.35 = 28dp
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );

      // Ícono correcto según tipo del feature
      await style.setStyleLayerProperty(
        _alertsLayerId,
        'icon-image',
        jsonEncode(['get', 'icon_id']),
      );

      _alertsLayerAdded = true;
    } catch (e) {
      debugPrint('❌ Error actualizando alertas: $e');
    }
  }

  void _showLongPressIndicator(Offset position) {
    _removeLongPressIndicator();
    _longPressOverlay = OverlayEntry(
      builder: (_) => _LongPressRipple(position: position),
    );
    Overlay.of(context).insert(_longPressOverlay!);
  }

  void _removeLongPressIndicator() {
    _longPressOverlay?.remove();
    _longPressOverlay = null;
  }

  // Tap corto: muestra info de la alerta/evento tocado
  Future<void> _onMapTap(Point point) async {
    // Modo planificador: añadir parada
    if (_routePlannerOpen && _routeAddMode) {
      _addRouteWp(point);
      return;
    }
    if (mapboxMap == null) return;
    try {
      final screenPos = await mapboxMap!.pixelForCoordinate(point);
      debugPrint('🖱️ Tap en pantalla: (${screenPos.x}, ${screenPos.y})');

      final features = await mapboxMap!.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenBox(
          ScreenBox(
            min: ScreenCoordinate(x: screenPos.x - 50, y: screenPos.y - 50),
            max: ScreenCoordinate(x: screenPos.x + 50, y: screenPos.y + 50),
          ),
        ),
        RenderedQueryOptions(
          layerIds: [_alertsLayerId, _eventsLayerId, _parkingLyrId, _bicimetroLyrId, _servicesLyrId, _crvLyrId],
          filter: null,
        ),
      );

      debugPrint('🔍 Features encontrados: ${features.length}');

      // Elegir el pin MÁS CERCANO al toque (no el primero), para abrir
      // exactamente el que el usuario apuntó aunque toque un poco al lado.
      final tapLng = point.coordinates.lng.toDouble();
      final tapLat = point.coordinates.lat.toDouble();
      Map<String, dynamic>? best;
      List<String> bestLayers = [];
      double bestDist = double.infinity;

      for (var featureInfo in features) {
        final inLayers = featureInfo?.layers ?? [];
        final feature = featureInfo?.queriedFeature.feature;
        if (feature == null) continue;
        final rawProps = feature["properties"];
        if (rawProps == null) continue;
        final props = Map<String, dynamic>.from(rawProps as Map);

        double dist = 0;
        final geom = feature["geometry"];
        if (geom is Map && geom["coordinates"] is List) {
          final c = geom["coordinates"] as List;
          if (c.length >= 2) {
            final dLng = (c[0] as num).toDouble() - tapLng;
            final dLat = (c[1] as num).toDouble() - tapLat;
            dist = dLng * dLng + dLat * dLat;
          }
        }
        if (dist < bestDist) {
          bestDist = dist;
          best = props;
          bestLayers = List<String>.from(inLayers.whereType<String>());
        }
      }

      if (best == null) return;

      if (bestLayers.contains(_parkingLyrId)) { _showBikeParkingModal(best); return; }
      if (bestLayers.contains(_servicesLyrId)) { _showBikeServiceModal(best); return; }
      if (bestLayers.contains(_crvLyrId)) { _showCicloRecreoModal(best); return; }
      if (bestLayers.contains(_bicimetroLyrId)) { _showBicimetroModal(best); return; }

      final idStr = best["id"]?.toString() ?? '';
      if (idStr.isNotEmpty) {
        final alert = _currentAlerts.firstWhere(
          (a) => a["id"].toString() == idStr,
          orElse: () => {},
        );
        if (alert.isNotEmpty) { _showAlertModal(alert); return; }
        final event = _currentEvents.firstWhere(
          (e) => e["id"].toString() == idStr,
          orElse: () => {},
        );
        if (event.isNotEmpty) { _showEventModal(event); return; }
      }
    } catch (e) {
      debugPrint('❌ Error procesando tap: $e');
    }
  }

  // ✅ MANEJAR LONG PRESS para crear alerta
  void _onLongPress(Point point) {
    debugPrint(
      '📍 Long press detectado en: ${point.coordinates.lat}, ${point.coordinates.lng}',
    );
    _showAlertFormAtLocation(point);
  }

  void _showFullPhoto(BuildContext ctx, String url) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(dialogCtx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAlertModal(Map<String, dynamic> alert) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final isCreator = alert['user_id'] == userId;
    final hasVotedUp = (alert['voters_up'] as List?)?.contains(userId) ?? false;
    final hasVotedDown =
        (alert['voters_down'] as List?)?.contains(userId) ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.13)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _getAlertColor(alert['type']).withOpacity(0.12),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.07)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getAlertColor(alert['type']),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getAlertIcon(alert['type']),
                      color: Colors.black,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert['title'],
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          alert['location_name'] ?? 'Ubicación sin nombre',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Foto de la alerta
            if (alert['photo_url'] != null &&
                (alert['photo_url'] as String).isNotEmpty)
              GestureDetector(
                onTap: () => _showFullPhoto(context, alert['photo_url']),
                child: ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: Image.network(
                    alert['photo_url'],
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : Container(
                            height: 180,
                            color: Colors.white.withOpacity(0.05),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.greenAccent,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (alert['description'] != null &&
                      alert['description'].isNotEmpty) ...[
                    const Text(
                      'Descripción',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert['description'],
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      const Icon(
                        Icons.person,
                        color: Colors.greenAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Reportado por: ${alert['user_name']}',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: Colors.greenAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(DateTime.parse(alert['created_at'])),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildVoteButton(
                        icon: Icons.thumb_up,
                        count: alert['votes_up'] ?? 0,
                        isActive: hasVotedUp,
                        color: Colors.green,
                        onTap: () => _handleVote(alert['id'], 'up', hasVotedUp),
                      ),
                      Container(width: 1, height: 30, color: Colors.white24),
                      _buildVoteButton(
                        icon: Icons.thumb_down,
                        count: alert['votes_down'] ?? 0,
                        isActive: hasVotedDown,
                        color: Colors.red,
                        onTap: () =>
                            _handleVote(alert['id'], 'down', hasVotedDown),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  if (isCreator)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(context);
                              final confirm = await _showDeleteAlertDialog();
                              if (confirm != true) return;
                              final id = alert['id'].toString();
                              final ok =
                                  await _alertsService.deleteAlert(alert['id']);
                              if (!ok) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        '⚠️ No se pudo eliminar: falta permiso en la base de datos (RLS)'),
                                    backgroundColor: Colors.redAccent,
                                    duration: Duration(seconds: 4),
                                  ),
                                );
                                return;
                              }
                              // Quitar el pin de inmediato (sin esperar al tiempo real)
                              if (mounted) {
                                setState(() => _currentAlerts.removeWhere(
                                    (a) => a['id'].toString() == id));
                              }
                              await _updateAlertsLayer(_currentAlerts);
                              CacheService.saveAlerts(_currentAlerts);
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('🗑️ Alerta eliminada'),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text(
                              'Eliminar alerta',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoteButton({
    required IconData icon,
    required int count,
    required bool isActive,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: isActive ? color : Colors.grey, size: 28),
              const SizedBox(height: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: isActive ? color : Colors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleVote(
    String alertId,
    String voteType,
    bool hasVoted,
  ) async {
    Navigator.pop(context);

    if (hasVoted) {
      if (voteType == 'up') {
        await _alertsService.removeVoteUp(alertId);
      } else {
        await _alertsService.removeVoteDown(alertId);
      }
    } else {
      if (voteType == 'up') {
        await _alertsService.voteUp(alertId);
      } else {
        await _alertsService.voteDown(alertId);
      }
    }
  }

  Future<bool?> _showDeleteAlertDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.13)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Eliminar alerta',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '¿Estás seguro de que quieres eliminar esta alerta?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white60,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(
                      'No',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white38,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Sí, eliminar',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getAlertColor(String type) {
    switch (type) {
      case 'danger':
        return Colors.red;
      case 'theft':
        return Colors.purple;
      case 'construction':
        return Colors.orange;
      case 'accident':
        return Colors.deepOrange;
      default:
        return Colors.blue;
    }
  }

  IconData _getAlertIcon(String type) {
    switch (type) {
      case 'danger':
        return Icons.warning;
      case 'theft':
        return Icons.no_accounts;
      case 'construction':
        return Icons.construction;
      case 'accident':
        return Icons.car_crash;
      default:
        return Icons.info;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return 'Hace ${difference.inDays} día${difference.inDays > 1 ? 's' : ''}';
    } else if (difference.inHours > 0) {
      return 'Hace ${difference.inHours} hora${difference.inHours > 1 ? 's' : ''}';
    } else if (difference.inMinutes > 0) {
      return 'Hace ${difference.inMinutes} minuto${difference.inMinutes > 1 ? 's' : ''}';
    } else {
      return 'Ahora mismo';
    }
  }

  void _showEventModal(Map<String, dynamic> event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.13)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                event['title'] ?? 'Evento',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedometer() {
    return ValueListenableBuilder<double>(
      valueListenable: _speedNotifier,
      builder: (context, speed, _) {
        String? mensaje;
        Color mensajeColor = Colors.orangeAccent;
        if (_isPassenger) {
          final v = _vehicleInfo(_passengerVehicle);
          mensaje = "${v.emoji} Vas en ${v.label} · no cuenta como pedaleo";
          mensajeColor = Colors.lightBlueAccent;
        } else if (speed > 35) {
          mensaje = "⚠️ ¡MUY RÁPIDO! Considera reducir la velocidad";
          mensajeColor = Colors.redAccent;
        } else if (speed > 30) {
          mensaje = "💧 Hidrátate, vas muy rápido";
          mensajeColor = Colors.orangeAccent;
        } else if (speed > 25) {
          mensaje = "⚡ Buen ritmo, ¡sigue así!";
          mensajeColor = Colors.greenAccent;
        } else if (speed > 0 && speed <= 25) {
          mensaje = "🚴 Pedalea, ¡buen paseo!";
          mensajeColor = Colors.lightBlueAccent;
        }
        final accentColor = _isDayMode
            ? const Color(0xFF00A86B)
            : Colors.greenAccent;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mensaje != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: _dayNightBox(radius: 20),
                child: Text(
                  mensaje,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: _isDayMode
                        ? mensajeColor.withOpacity(0.85)
                        : mensajeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Container(
              width: 85,
              height: 85,
              decoration: _dayNightBox(radius: 50),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    speed.toStringAsFixed(0),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: _overlayText,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    "km/h",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar() {
    final statusColor =
        _isPassenger ? Colors.lightBlueAccent : Colors.greenAccent;
    final vInfo = _vehicleInfo(_passengerVehicle);
    final statusIcon = _isPassenger
        ? (_passengerVehicle == 'micro'
              ? Icons.directions_bus_rounded
              : _passengerVehicle == 'metro'
                    ? Icons.subway_rounded
                    : Icons.directions_car_rounded)
        : Icons.directions_bike;
    final statusText =
        _isPassenger ? 'PASAJERO · ${vInfo.label.toUpperCase()}' : 'CICLISTA ACTIVO';
    return Container(
      decoration: _dayNightBox(radius: 16),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            statusIcon,
            color: _isPassenger
                ? Colors.lightBlue
                : (_isDayMode ? const Color(0xFF00A86B) : Colors.greenAccent),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: _overlayText,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (_isPassenger)
            GestureDetector(
              onTap: () => _exitPassengerMode(),
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
                ),
                child: const Text(
                  '🚴 Pedalear',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            WeatherPill(isDayMode: _isDayMode),
        ],
      ),
    );
  }

  void _resetNorth() {
    if (mapboxMap != null) {
      mapboxMap!.setCamera(CameraOptions(bearing: 0.0));
    }
  }

  // ── Planificador de rutas ─────────────────────────────────────────────────

  void _addRouteWp(Point point) {
    setState(() {
      _routeWps.add(
        _RouteWp(
          lat: point.coordinates.lat.toDouble(),
          lng: point.coordinates.lng.toDouble(),
          label: 'Parada ${_routeWps.length + 1}',
        ),
      );
      _routeAddMode = false;
      _routeDistKm = null;
      _routeDurMin = null;
    });
    _redrawRoutePins();
  }

  Future<void> _redrawRoutePins() async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    try {
      if (await style.styleLayerExists(_rpWpLyr)) {
        await style.removeStyleLayer(_rpWpLyr);
      }
      if (await style.styleSourceExists(_rpWpSrc)) {
        await style.removeStyleSource(_rpWpSrc);
      }
      if (_routeWps.isEmpty) return;
      final lastIdx = _routeWps.length - 1;
      final features = _routeWps
          .asMap()
          .entries
          .map(
            (e) => {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [e.value.lng, e.value.lat],
              },
              'properties': {
                'idx': e.key + 1,
                'isFirst': e.key == 0,
                'isLast': e.key == lastIdx,
              },
            },
          )
          .toList();
      final fc = jsonEncode({
        'type': 'FeatureCollection',
        'features': features,
      });
      await style.addSource(GeoJsonSource(id: _rpWpSrc, data: fc));
      await style.addLayer(
        CircleLayer(
          id: _rpWpLyr,
          sourceId: _rpWpSrc,
          circleRadius: 14.0,
          circleColor: Colors.greenAccent.value,
          circleStrokeWidth: 3.0,
          circleStrokeColor: Colors.white.value,
        ),
      );
      // Origen verde, destino rojo (más grande), intermedios naranjo.
      await style.setStyleLayerProperty(
        _rpWpLyr,
        'circle-color',
        jsonEncode([
          'case',
          ['get', 'isFirst'], '#00E676',
          ['get', 'isLast'], '#FF1744',
          '#FF9100',
        ]),
      );
      await style.setStyleLayerProperty(
        _rpWpLyr,
        'circle-radius',
        jsonEncode(['case', ['get', 'isLast'], 18.0, 13.0]),
      );
    } catch (e) {
      debugPrint('Error redrawRoutePins: $e');
    }
  }

  Future<void> _drawRouteLine(List<dynamic> coords) async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    try {
      if (await style.styleLayerExists(_rpRouteLyr)) {
        await style.removeStyleLayer(_rpRouteLyr);
      }
      if (await style.styleSourceExists(_rpRouteSrc)) {
        await style.removeStyleSource(_rpRouteSrc);
      }
      final positions = coords
          .map((c) => [c[0].toDouble(), c[1].toDouble()])
          .toList();
      // Guardar coords completas para borrar lo recorrido
      _routeCoords = positions.map((p) => List<double>.from(p)).toList();
      _routeProgressIdx = 0;
      final fc = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {'type': 'LineString', 'coordinates': positions},
            'properties': {},
          }
        ],
      });
      await style.addSource(GeoJsonSource(id: _rpRouteSrc, data: fc));
      await style.addLayer(
        LineLayer(
          id: _rpRouteLyr,
          sourceId: _rpRouteSrc,
          lineColor: const Color(0xFF2962FF).value, // azul fuerte (ruta)
          lineWidth: 5.0,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
          lineOpacity: 0.88,
        ),
      );
      // Pins encima de la línea
      await _redrawRoutePins();
      // Centrar cámara
      if (_routeWps.length >= 2) {
        final midLat =
            _routeWps.map((w) => w.lat).reduce((a, b) => a + b) /
            _routeWps.length;
        final midLng =
            _routeWps.map((w) => w.lng).reduce((a, b) => a + b) /
            _routeWps.length;
        mapboxMap!.setCamera(
          CameraOptions(
            center: Point(coordinates: Position(midLng, midLat)),
            zoom: 12.5,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error drawRouteLine: $e');
    }
  }

  Future<void> _clearRouteLayers() async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    try {
      if (await style.styleLayerExists(_rpWpLyr)) {
        await style.removeStyleLayer(_rpWpLyr);
      }
      if (await style.styleSourceExists(_rpWpSrc)) {
        await style.removeStyleSource(_rpWpSrc);
      }
      if (await style.styleLayerExists(_rpRouteLyr)) {
        await style.removeStyleLayer(_rpRouteLyr);
      }
      if (await style.styleSourceExists(_rpRouteSrc)) {
        await style.removeStyleSource(_rpRouteSrc);
      }
    } catch (_) {}
  }

  Future<void> _calcRoute() async {
    if (_routeWps.length < 2) return;
    setState(() => _routeCalculating = true);
    try {
      final coords = _routeWps.map((w) => '${w.lng},${w.lat}').join(';');
      final url =
          'https://api.mapbox.com/directions/v5/mapbox/cycling/$coords'
          '?geometries=geojson&overview=full&steps=false&access_token=$kMapboxToken';
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) throw Exception('Sin rutas');
      final route = routes[0] as Map<String, dynamic>;

      setState(() {
        _routeDistKm = (route['distance'] as num).toDouble() / 1000;
        _routeDurMin = (route['duration'] as num).toDouble() / 60;
        _routeCalculating = false;
        _routeDifficulty = null;
        _routeElevGain = null;
      });
      await _drawRouteLine((route['geometry'] as Map)['coordinates'] as List);
      _fetchRouteElevation(); // Fire-and-forget; actualiza dificultad cuando llega
    } catch (e) {
      setState(() => _routeCalculating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  void _closeRoutePlanner() {
    final restoreParking = _prevShowBikeParkings;
    final restoreBicimetro = _prevShowBicimetro;
    final restoreServices = _prevShowBikeServices;
    setState(() {
      _routePlannerOpen = false;
      _routeAddMode = false;
      _routeWps.clear();
      _routeDistKm = null;
      _routeDurMin = null;
      _routeCalculating = false;
      _navigating = false;
      _routeCoords = [];
      _routeProgressIdx = 0;
      _routeDifficulty = null;
      _routeElevGain = null;
      _elevationLoading = false;
      // Restaurar capas que se ocultaron al iniciar la ruta
      _showBikeParkings = restoreParking;
      _showBicimetro = restoreBicimetro;
      _showBikeServices = restoreServices;
      _prevShowBikeParkings = false;
      _prevShowBicimetro = false;
      _prevShowBikeServices = false;
    });
    _clearRouteLayers();
    _restartGps();
    // Re-mostrar las capas si estaban activas
    if (restoreParking) _updateBikeParkingsLayer();
    if (restoreBicimetro) _updateBicimetroLayer();
    if (restoreServices) _updateBikeServicesLayer();
  }

  // ── Panel UI del planificador ─────────────────────────────────────────────

  Widget _buildRoutePlannerPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF5080810),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle + título
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.route,
                  color: Colors.lightBlueAccent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Planificador de ruta',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _closeRoutePlanner,
                  child: const Icon(
                    Icons.close,
                    color: Colors.white38,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          // ── Rutas guardadas ───────────────────────────────────────────
          if (_loadingFavorites)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.amberAccent,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else if (_savedRoutes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Colors.amberAccent, size: 13),
                  const SizedBox(width: 6),
                  const Text(
                    'RUTAS GUARDADAS',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.amberAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _loadFavorites,
                    child: const Icon(
                      Icons.refresh,
                      color: Colors.white24,
                      size: 14,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _savedRoutes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final fav = _savedRoutes[i];
                  return GestureDetector(
                    onTap: () => _loadFavoriteRoute(fav),
                    onLongPress: () => _confirmDeleteFavorite(fav),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: glassDecoration(
                        radius: 12,
                        tint: Colors.amberAccent,
                        opacity: 0.08,
                        borderOpacity: 0.2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(fav.icon, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            fav.name,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (fav.distanceKm != null) ...[
                            const SizedBox(width: 5),
                            Text(
                              '${fav.distanceKm!.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.amberAccent,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Lista de paradas
          if (_routeWps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Toca "+" y luego el mapa para añadir paradas',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white38,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                itemCount: _routeWps.length,
                itemBuilder: (_, i) => _rpWpTile(i),
              ),
            ),

          // Resultados
          if (_routeDistKm != null) _rpResults(),

          // Botón Iniciar (visible cuando hay ≥2 paradas, calculado o no)
          if (_routeWps.length >= 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (_routeCalculating || _routeDistKm == null)
                      ? null
                      : _startNavigationMode,
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('Iniciar navegación'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0057FF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white12,
                    disabledForegroundColor: Colors.white24,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),

          // Botones
          Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              6,
              12,
              MediaQuery.of(context).padding.bottom + 12,
            ),
            child: Row(
              children: [
                // Añadir parada
                GestureDetector(
                  onTap: () => setState(() => _routeAddMode = !_routeAddMode),
                  child: Container(
                    height: 44,
                    width: 44,
                    decoration: glassDecoration(
                      radius: 12,
                      tint: _routeAddMode ? Colors.greenAccent : Colors.white,
                      opacity: _routeAddMode ? 0.18 : 0.08,
                      borderOpacity: _routeAddMode ? 0.4 : 0.15,
                    ),
                    child: Icon(
                      _routeAddMode
                          ? Icons.touch_app
                          : Icons.add_location_alt_outlined,
                      color: _routeAddMode
                          ? Colors.greenAccent
                          : Colors.white54,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Calcular
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _routeWps.length >= 2 && !_routeCalculating
                          ? _calcRoute
                          : null,
                      icon: _routeCalculating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.route, size: 16),
                      label: Text(
                        _routeCalculating ? 'Calculando...' : 'Calcular',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white24,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_routeWps.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  // Guardar favorito
                  GestureDetector(
                    onTap: () => _showSaveRouteFavorite(),
                    child: Container(
                      height: 44,
                      width: 44,
                      decoration: glassDecoration(
                        radius: 12,
                        tint: Colors.amberAccent,
                        opacity: 0.10,
                        borderOpacity: 0.22,
                      ),
                      child: const Icon(
                        Icons.star_outline,
                        color: Colors.amberAccent,
                        size: 20,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // Limpiar
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _routeWps.clear();
                      _routeDistKm = null;
                      _routeDurMin = null;
                    });
                    _clearRouteLayers();
                  },
                  child: Container(
                    height: 44,
                    width: 44,
                    decoration: glassDecoration(
                      radius: 12,
                      tint: Colors.redAccent,
                      opacity: 0.08,
                      borderOpacity: 0.18,
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rpWpTile(int i) {
    final wp = _routeWps[i];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: glassDecoration(
        radius: 10,
        opacity: 0.06,
        borderOpacity: 0.10,
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Colors.greenAccent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              wp.label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white70,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _routeWps.removeAt(i);
                _routeDistKm = null;
                _routeDurMin = null;
              });
              _clearRouteLayers();
              if (_routeWps.isNotEmpty) _redrawRoutePins();
            },
            child: const Icon(Icons.close, color: Colors.white24, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _rpResults() {
    final co2 = Co2Service.savedKg(_routeDistKm!);
    final durStr = _routeDurMin != null
        ? (_routeDurMin! >= 60
              ? '${(_routeDurMin! / 60).toStringAsFixed(1)}h'
              : '${_routeDurMin!.toStringAsFixed(0)} min')
        : '—';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: glassDecoration(
        radius: 14,
        tint: Colors.greenAccent,
        opacity: 0.06,
        borderOpacity: 0.12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _rpStat(
            Icons.straighten,
            '${_routeDistKm!.toStringAsFixed(1)} km',
            'Distancia',
            Colors.greenAccent,
          ),
          _rpStat(
            Icons.timer_outlined,
            durStr,
            'Tiempo',
            Colors.lightBlueAccent,
          ),
          _rpStat(
            Icons.eco_outlined,
            Co2Service.format(co2),
            'CO₂ ahorr.',
            Colors.lightGreenAccent,
          ),
          _rpStat(
            Icons.terrain,
            _elevationLoading
                ? '...'
                : (_routeDifficulty != null
                    ? (_routeElevGain != null
                        ? '${_routeElevGain!.toStringAsFixed(0)}m'
                        : _routeDifficulty!)
                    : '—'),
            _routeDifficulty ?? 'Dificultad',
            _routeDifficulty == 'Fácil'
                ? Colors.greenAccent
                : _routeDifficulty == 'Moderada'
                    ? Colors.orangeAccent
                    : _routeDifficulty == 'Difícil'
                        ? Colors.redAccent
                        : Colors.white38,
          ),
        ],
      ),
    );
  }

  Widget _rpStat(IconData icon, String val, String label, Color color) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(height: 2),
          Text(
            val,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white38,
              fontSize: 9,
            ),
          ),
        ],
      );

  void _showSaveRouteFavorite() async {
    final favSvc = FavoritesService();
    String selName = 'Mi ruta';
    String selIcon = '📍';
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          return Container(
            margin: const EdgeInsets.all(16),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              top: 20,
              left: 16,
              right: 16,
            ),
            decoration: glassDecoration(
              radius: 24,
              opacity: 0.18,
              borderOpacity: 0.25,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Guardar ruta favorita',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kFavoritePresets.map((p) {
                    final active = selName == p['name'] && selIcon == p['icon'];
                    return GestureDetector(
                      onTap: () => setModal(() {
                        selName = p['name']!;
                        selIcon = p['icon']!;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: glassDecoration(
                          radius: 20,
                          tint: active ? Colors.greenAccent : Colors.white,
                          opacity: active ? 0.15 : 0.05,
                          borderOpacity: active ? 0.35 : 0.1,
                        ),
                        child: Text(
                          '${p['icon']} ${p['name']}',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: active ? Colors.greenAccent : Colors.white54,
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await favSvc.save(
                        FavoriteRoute(
                          name: selName,
                          icon: selIcon,
                          waypoints: _routeWps
                              .map(
                                (w) => {
                                  'lat': w.lat,
                                  'lng': w.lng,
                                  'name': w.label,
                                },
                              )
                              .toList(),
                          distanceKm: _routeDistKm,
                        ),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Ruta "$selName" guardada',
                              style: const TextStyle(fontFamily: 'Poppins'),
                            ),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.all(16),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Guardar'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Avanza el índice de progreso al coord más cercano adelante del usuario
  DateTime _lastTrim = DateTime(0);

  void _advanceRouteProgress(double lat, double lng) {
    if (_routeCoords.isEmpty) return;
    // Throttle: max una actualización cada 2 segundos
    final now = DateTime.now();
    if (now.difference(_lastTrim).inSeconds < 2) return;

    final searchEnd = (_routeProgressIdx + 100).clamp(0, _routeCoords.length);
    double minDist = double.infinity;
    int bestIdx = _routeProgressIdx;
    for (int i = _routeProgressIdx; i < searchEnd; i++) {
      final d = geo.Geolocator.distanceBetween(
        lat,
        lng,
        _routeCoords[i][1],
        _routeCoords[i][0],
      );
      if (d < minDist) {
        minDist = d;
        bestIdx = i;
      } else if (d > minDist + 80) {
        break;
      }
    }
    // Solo recortar si nos acercamos menos de 30m y avanzamos al menos 1 coord
    if (bestIdx > _routeProgressIdx && minDist < 30) {
      _routeProgressIdx = bestIdx;
      _lastTrim = now;
      _trimRouteLine();
    }
  }

  // Redibuja la línea de ruta con solo los coords restantes (remove+re-add)
  Future<void> _trimRouteLine() async {
    if (mapboxMap == null || _routeCoords.isEmpty) return;
    final remaining = _routeCoords.sublist(_routeProgressIdx);
    if (remaining.length < 2) return;
    final style = mapboxMap!.style;
    try {
      if (await style.styleLayerExists(_rpRouteLyr)) {
        await style.removeStyleLayer(_rpRouteLyr);
      }
      if (await style.styleSourceExists(_rpRouteSrc)) {
        await style.removeStyleSource(_rpRouteSrc);
      }
      final fc = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {'type': 'LineString', 'coordinates': remaining},
            'properties': {},
          }
        ],
      });
      await style.addSource(GeoJsonSource(id: _rpRouteSrc, data: fc));
      await style.addLayer(
        LineLayer(
          id: _rpRouteLyr,
          sourceId: _rpRouteSrc,
          lineColor: const Color(0xFF2962FF).value, // azul fuerte (ruta)
          lineWidth: 5.0,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
          lineOpacity: 0.88,
        ),
      );
      // Pins siempre encima
      await _redrawRoutePins();
    } catch (e) {
      debugPrint('Error trimming route: $e');
    }
  }

  void _startNavigationMode() {
    if (_routeWps.length < 2) return;
    setState(() {
      _navigating = true;
      _routeProgressIdx = 0;
      _isFollowingUser = true;
      _routePlannerOpen = false;
      _routeAddMode = false;
    });
    _restartGps(); // Cambiar a GPS de máxima precisión
    if (_routeCoords.isNotEmpty) _trimRouteLine();
  }

  void _confirmDeleteFavorite(FavoriteRoute fav) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Eliminar ${fav.icon} ${fav.name}',
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 15,
          ),
        ),
        content: const Text(
          '¿Borrar esta ruta favorita?',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white54,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok == true && fav.id != null) {
      await FavoritesService().delete(fav.id!);
      _loadFavorites();
    }
  }

  Future<void> _loadFavorites() async {
    if (_loadingFavorites) return;
    setState(() => _loadingFavorites = true);
    final routes = await FavoritesService().getAll();
    if (mounted) {
      setState(() {
        _savedRoutes = routes;
        _loadingFavorites = false;
      });
    }
  }

  void _loadFavoriteRoute(FavoriteRoute fav) {
    final wps = fav.waypoints
        .map(
          (w) => _RouteWp(
            lat: (w['lat'] as num).toDouble(),
            lng: (w['lng'] as num).toDouble(),
            label: w['name'] as String? ?? '${fav.icon} ${fav.name}',
          ),
        )
        .toList();
    setState(() {
      _routeWps.clear();
      _routeWps.addAll(wps);
      _routeDistKm = null;
      _routeDurMin = null;
    });
    _clearRouteLayers();
    if (wps.isNotEmpty) {
      _redrawRoutePins();
      if (wps.length >= 2) _calcRoute();
    }
  }

  /// Activa/desactiva el conteo de km en segundo plano. Requiere permiso de
  /// ubicación "Permitir todo el tiempo".
  Future<void> _toggleBgTracking(bool val) async {
    if (val) {
      final status = await Permission.locationAlways.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Activa la ubicación "Permitir todo el tiempo" en Ajustes para contar km en segundo plano',
              ),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return; // no se activa si no hay permiso
      }
    }
    setState(() => _bgTrackingEnabled = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bg_tracking', val);
    _restartGps(); // re-crea el stream con/sin servicio en primer plano
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(val
              ? '✅ Contando km en segundo plano'
              : 'Conteo en segundo plano desactivado'),
          backgroundColor: val ? Colors.green : Colors.grey[800],
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveKmToProfile(double km) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client.rpc(
        'increment_total_km',
        params: {'uid': uid, 'km_delta': km},
      );
    } catch (_) {
      // Si el RPC no existe, actualizamos con fetch+update
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('total_km')
            .eq('id', uid)
            .maybeSingle();
        final current = (profile?['total_km'] as num?)?.toDouble() ?? 0.0;
        await Supabase.instance.client
            .from('profiles')
            .update({'total_km': current + km})
            .eq('id', uid);
      } catch (e) {
        debugPrint('Error guardando km: $e');
      }
    }
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthPage()),
        (route) => false,
      );
    }
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xF8080810),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            InkWell(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                );
              },
              child: DrawerHeader(
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.07),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.07)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _ProfileButton(),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Supabase
                                        .instance
                                        .client
                                        .auth
                                        .currentUser
                                        ?.userMetadata?['full_name']
                                    as String? ??
                                Supabase
                                    .instance
                                    .client
                                    .auth
                                    .currentUser
                                    ?.email ??
                                "BiciRadar",
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Ver perfil",
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.greenAccent.withOpacity(0.8),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.white38,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
              child: Text(
                "ACTIVIDAD",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_rounded,
                  color: Colors.greenAccent),
              title: const Text(
                "Mis estadísticas",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                "Km de hoy, semana y racha",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              trailing:
                  const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StatsPage()),
                );
              },
            ),
            SwitchListTile(
              value: _modoActivo,
              activeThumbColor: Colors.greenAccent,
              title: const Text(
                "Modo activo",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                _modoActivo ? "Visible para otros" : "No visible",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              onChanged: (value) {
                setState(() => _modoActivo = value);
                if (!value) {
                  _presenceService.clearMyLocation();
                }
              },
            ),
            SwitchListTile(
              value: _bgTrackingEnabled,
              activeThumbColor: Colors.greenAccent,
              secondary: const Icon(Icons.gps_fixed, color: Colors.greenAccent),
              title: const Text(
                "Contar km en segundo plano",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                "Suma tus km aunque no tengas la app abierta (usa más batería)",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              onChanged: _toggleBgTracking,
            ),
            const Divider(color: Colors.white24, height: 24),
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Text(
                "EVENTOS",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.event, color: Colors.greenAccent),
              title: const Text(
                "Próximos eventos",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                "Encuentra ciclistas cerca",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EventsPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.add_location,
                color: Colors.greenAccent,
              ),
              title: const Text(
                "Crear evento",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                "Organiza una salida",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateEventPage()),
                );
              },
            ),
            const Divider(color: Colors.white24, height: 24),
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Text(
                "COMUNIDAD",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.leaderboard, color: Colors.amberAccent),
              title: const Text(
                "Ranking local",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                "Top comunas y ciclistas",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RankingPage()),
                );
              },
            ),
            const Divider(color: Colors.white24, height: 24),
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Text(
                "ALERTAS COMUNITARIAS",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_alert, color: Colors.redAccent),
              title: const Text(
                "Reportar problema",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: const Text(
                "Mantén presionado el mapa donde ocurre el problema",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.grey),
              ),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      '💡 Mantén presionado el mapa en el lugar del problema para crear una alerta',
                    ),
                    backgroundColor: Colors.blue,
                    duration: Duration(seconds: 3),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.route, color: Colors.lightBlueAccent),
              title: const Text(
                "Planificar ruta",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                "Multiparada con CO₂ estimado",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() => _routePlannerOpen = true);
                _loadFavorites();
              },
            ),
            const Divider(color: Colors.white24, height: 24),
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Text(
                "MAPA",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            SwitchListTile(
              value: _autoDarkMode,
              activeThumbColor: Colors.blueAccent,
              title: const Text(
                "Modo oscuro automático",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                _autoDarkMode
                    ? "Noche 7pm–7am, día 7am–7pm"
                    : "Siempre modo noche",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _autoDarkMode = val;
                  _currentStyle = val ? autoDarkMapStyle() : kMapStyleNight;
                });
                mapboxMap?.loadStyleURI(_currentStyle);
              },
            ),
            const Divider(color: Colors.white24, height: 24),
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Text(
                "CAPAS DEL MAPA",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            SwitchListTile(
              value: _showBikeParkings,
              activeThumbColor: const Color(0xFF00BCD4),
              secondary: _bikeParkingsLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFF00BCD4),
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.local_parking, color: Color(0xFF00BCD4)),
              title: const Text(
                "Estacionamientos de bici",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                "Biciparkings de OpenStreetMap",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.grey[400], fontSize: 12),
              ),
              onChanged: (_) => _toggleBikeParkings(),
            ),
            SwitchListTile(
              value: _showBicimetro,
              activeThumbColor: const Color(0xFF7C3AED),
              secondary: const Icon(Icons.train, color: Color(0xFF7C3AED)),
              title: const Text(
                "BiciMetro",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                "Estaciones Metro que permiten bici",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.grey[400], fontSize: 12),
              ),
              onChanged: (_) => _toggleBicimetro(),
            ),
            SwitchListTile(
              value: _showBikeServices,
              activeThumbColor: const Color(0xFF22C55E),
              secondary: _bikeServicesLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFF22C55E),
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.pedal_bike, color: Color(0xFF22C55E)),
              title: const Text(
                "Inflado, talleres y agua",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                "Aire, talleres, gasolineras y puntos de agua",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              onChanged: (_) => _toggleBikeServices(),
            ),
            SwitchListTile(
              value: _showCicloRecreo,
              activeThumbColor: const Color(0xFF7CB342),
              secondary: const Icon(Icons.event_available, color: Color(0xFF7CB342)),
              title: const Text(
                "CicloRecreoVía",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                "Calles cerradas para ciclistas los domingos",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              onChanged: (_) => _toggleCicloRecreo(),
            ),
            const Divider(color: Colors.white24, height: 24),
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Text(
                "SEGURIDAD",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            SwitchListTile(
              value: _fallDetectionEnabled,
              activeThumbColor: Colors.redAccent,
              secondary: const Icon(
                Icons.health_and_safety,
                color: Colors.redAccent,
              ),
              title: const Text(
                "Detección de caídas",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                "Llama a emergencias si detecta una caída brusca",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              onChanged: (val) {
                setState(() => _fallDetectionEnabled = val);
                if (val) {
                  _fallService.start(_onFallDetected);
                } else {
                  _fallService.stop();
                }
              },
            ),
            SwitchListTile(
              value: _proximityAlertsEnabled,
              activeThumbColor: Colors.orangeAccent,
              secondary: const Icon(
                Icons.notifications_active,
                color: Colors.orangeAccent,
              ),
              title: const Text(
                "Alertas de proximidad",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              subtitle: Text(
                "Notifica al acercarte a un incidente reportado",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              onChanged: (val) {
                setState(() => _proximityAlertsEnabled = val);
                _proximityService.reset();
              },
            ),
            const Divider(color: Colors.white24, height: 24),
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Text(
                "CUENTA",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                "Cerrar sesión",
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    MapboxOptions.setAccessToken(kMapboxToken);
    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // GestureDetector solo para capturar posición del dedo (overlay visual)
          GestureDetector(
            onTapDown: (details) {
              _longPressTapPosition = details.globalPosition;
            },
            child: MapWidget(
              key: const ValueKey("mapWidget"),
              styleUri: _currentStyle,
              cameraOptions: CameraOptions(
                center: Point(coordinates: Position(-70.6483, -33.4569)),
                zoom: 15.0,
              ),
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: (_) => _onStyleLoaded(),
              onScrollListener: (_) => _stopFollowingByGesture(),
              onZoomListener: (_) => _stopFollowingByGesture(),
              // Tap corto → mostrar info de alerta/evento
              onTapListener: (info) => _onMapTap(info.point),
              // Long press nativo del SDK → crear alerta con indicador visual
              onLongTapListener: (info) {
                _showLongPressIndicator(_longPressTapPosition ?? Offset.zero);
                Future.delayed(const Duration(milliseconds: 150), () {
                  _removeLongPressIndicator();
                  _onLongPress(info.point);
                });
              },
            ),
          ),
          // ── Banner sin conexión ───────────────────────────────────────────
          if (_isOffline)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  color: Colors.orange.shade800.withOpacity(0.95),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Sin conexión · Mostrando datos en caché',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Positioned(top: 120, left: 20, right: 20, child: _buildTopBar()),
          Positioned(left: 20, bottom: 64, child: _buildSpeedometer()),

          if (_isSelectingLocation && _selectedLocation != null)
            Positioned(
              bottom: 120,
              right: 20,
              child: FloatingActionButton(
                backgroundColor: Colors.greenAccent,
                onPressed: _confirmLocationAndCreateAlert,
                child: const Icon(Icons.check, color: Colors.black),
              ),
            ),

          Positioned(
            top: 50,
            left: 16,
            child: Container(
              decoration: _dayNightBox(radius: 30),
              child: IconButton(
                icon: Icon(
                  Icons.menu,
                  color: _isDayMode
                      ? const Color(0xFF00A86B)
                      : Colors.greenAccent,
                  size: 22,
                ),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                tooltip: 'Menú',
              ),
            ),
          ),
          // ── Botón de búsqueda de destino ────────────────────────
          Positioned(
            top: 50,
            left: 64,
            child: Container(
              decoration: _dayNightBox(radius: 30),
              child: IconButton(
                icon: Icon(
                  Icons.search,
                  color: _isDayMode
                      ? const Color(0xFF00A86B)
                      : Colors.greenAccent,
                  size: 22,
                ),
                onPressed: _openPlaceSearch,
                tooltip: 'Buscar destino',
              ),
            ),
          ),
          // ── Botón de pánico ─────────────────────────────────────
          Positioned(bottom: 64, right: 20, child: _PanicButton()),

          // ── Hint "toca el mapa" cuando _routeAddMode ─────────────────────
          if (_routePlannerOpen && _routeAddMode)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.greenAccent.withOpacity(0.5),
                    ),
                  ),
                  child: const Text(
                    '📍 Toca el mapa para añadir una parada',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.greenAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

          // ── Botón cancelar ruta (visible cuando hay una ruta activa) ─────
          if (_routePlannerOpen && _routeDistKm != null)
            Positioned(
              bottom: 220,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _closeRoutePlanner,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Cancelar ruta',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Panel planificador de ruta ────────────────────────────────────
          if (_routePlannerOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildRoutePlannerPanel(),
            ),

          Positioned(
            top: 50,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: _dayNightBox(radius: 30),
                  child: IconButton(
                    icon: Icon(
                      Icons.explore,
                      color: _isDayMode
                          ? const Color(0xFF00A86B)
                          : Colors.greenAccent,
                      size: 22,
                    ),
                    onPressed: _resetNorth,
                    tooltip: 'Orientar al norte',
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: _dayNightBox(radius: 30),
                  child: IconButton(
                    icon: Icon(
                      Icons.navigation,
                      color: _isFollowingUser
                          ? (_isDayMode
                                ? const Color(0xFF00A86B)
                                : Colors.greenAccent)
                          : (_isDayMode
                                ? const Color(0xFF333355)
                                : Colors.white),
                      size: 22,
                    ),
                    onPressed: _toggleFollowing,
                    tooltip: 'Seguir ubicación',
                  ),
                ),
                _ProfileButton(isDayMode: _isDayMode),
              ],
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(),
    );
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    this.mapboxMap = mapboxMap;
    _configureMapOrnaments(mapboxMap);
    _startFollowing();
    _centerOnUserAtStartup();
    _listenToActiveCyclists();
    _listenToEvents();
    _listenToAlerts();
    // Las capas se agregan en _onStyleLoaded, que se dispara tras onMapCreated
  }

  /// Al abrir la app, obtiene la ubicación actual de inmediato y centra el mapa
  /// ahí (el stream de GPS solo emite al moverse, por eso hay que pedir una
  /// lectura puntual). También dispara la carga de las capas por defecto.
  Future<void> _centerOnUserAtStartup() async {
    try {
      var perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied) {
        perm = await geo.Geolocator.requestPermission();
      }
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        return;
      }

      // Salto rápido con la última posición conocida…
      geo.Position? pos = await geo.Geolocator.getLastKnownPosition();
      if (pos != null) {
        _lastPosition = pos;
        _moveCameraInstant(pos);
        _maybeAutoLoadLayers();
      }

      // …y centrado preciso con una lectura fresca.
      pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));
      _lastPosition = pos;
      if (mounted) setState(() => _isFollowingUser = true);
      _moveCameraInstant(pos);
      _maybeAutoLoadLayers();
    } catch (e) {
      debugPrint('No se pudo centrar al inicio: $e');
    }
  }

  /// Ajusta los adornos nativos de Mapbox para que no se encimen con la UI de
  /// la app ni con las barras del sistema:
  ///  • Barra de escala: se oculta (saturaba la parte superior).
  ///  • Brújula nativa: se oculta (la app ya tiene su propio botón de brújula).
  ///  • Logo y atribución: se mantienen visibles (requisito de Mapbox) pero se
  ///    suben para no chocar con la barra de navegación de Android.
  Future<void> _configureMapOrnaments(MapboxMap map) async {
    try {
      await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
      await map.compass.updateSettings(CompassSettings(enabled: false));
      // Logo y ⓘ pegados a las esquinas inferiores, apenas por encima de la
      // barra de navegación (no flotando en medio de la pantalla).
      await map.logo.updateSettings(
        LogoSettings(
          position: OrnamentPosition.BOTTOM_LEFT,
          marginLeft: 10,
          marginBottom: 26,
        ),
      );
      await map.attribution.updateSettings(
        AttributionSettings(
          position: OrnamentPosition.BOTTOM_RIGHT,
          marginRight: 10,
          marginBottom: 26,
        ),
      );
    } catch (e) {
      debugPrint('Error configurando adornos del mapa: $e');
    }
  }

  /// Se dispara cada vez que el mapa carga un estilo (inicio + cada cambio día/noche).
  /// Re-agrega TODAS las capas custom porque Mapbox las borra al cambiar estilo.
  void _onStyleLoaded() {
    // Resetear flags para que se re-agreguen
    _cicloviasAdded = false;
    _cyclistsIconAdded = false;
    _eventsIconAdded = false;
    _alertsIconAdded = false;
    _alertsLayerAdded = false;
    _bikeParkingsIconAdded = false;
    _bicimetroIconAdded = false;
    _bikeServicesIconsAdded = false;
    _cicloRecreoIconAdded = false;

    Future.microtask(() async {
      if (mapboxMap == null || !mounted) return;
      await _setupUserPuck();
      await _addCicloviasLayer();
      // Re-agregar alertas/eventos con los datos que ya tenemos en memoria
      if (_currentAlerts.isNotEmpty) await _updateAlertsLayer(_currentAlerts);
      if (_currentEvents.isNotEmpty) await _updateEventsLayer(_currentEvents);
      // Re-agregar capas opcionales si estaban activas
      if (_showBikeParkings && _bikeParkings.isNotEmpty) await _updateBikeParkingsLayer();
      if (_showBicimetro) await _updateBicimetroLayer();
      if (_showBikeServices && _bikeServices.isNotEmpty) await _updateBikeServicesLayer();
      if (_showCicloRecreo && _cicloRecreoPoints.isNotEmpty) await _updateCicloRecreoLayer();

      // El primer cargado de las capas por defecto se dispara tras el primer
      // fix de GPS (ver _maybeAutoLoadLayers), para usar un área pequeña
      // alrededor del usuario y evitar consultas lentas a todo Santiago.
      _maybeAutoLoadLayers();
      // Re-dibujar ruta si estaba calculada
      if (_routeCoords.isNotEmpty && _routeDistKm != null) {
        final remaining = _routeCoords.sublist(_routeProgressIdx);
        if (remaining.length >= 2) {
          final style = mapboxMap!.style;
          try {
            if (await style.styleLayerExists(_rpRouteLyr)) {
              await style.removeStyleLayer(_rpRouteLyr);
            }
            if (await style.styleSourceExists(_rpRouteSrc)) {
              await style.removeStyleSource(_rpRouteSrc);
            }
            final fc = jsonEncode({
              'type': 'FeatureCollection',
              'features': [
                {
                  'type': 'Feature',
                  'geometry': {'type': 'LineString', 'coordinates': remaining},
                  'properties': {},
                }
              ],
            });
            await style.addSource(GeoJsonSource(id: _rpRouteSrc, data: fc));
            await style.addLayer(
              LineLayer(
                id: _rpRouteLyr,
                sourceId: _rpRouteSrc,
                lineColor: const Color(0xFF2962FF).value, // azul fuerte (ruta)
                lineWidth: 5.0,
                lineJoin: LineJoin.ROUND,
                lineCap: LineCap.ROUND,
                lineOpacity: 0.88,
              ),
            );
            await _redrawRoutePins();
          } catch (_) {}
        }
      }
    });
  }

  /// Capas de ciclovías con ancho y opacidad dependientes del zoom:
  /// finas y tenues al ver toda la ciudad (no saturan el mapa), nítidas al
  /// acercarte para pedalear. Se eliminó el "glow" que creaba la neblina neón.
  List<LineLayer> _cicloviaLayers() {
    return [
      // Línea principal — celeste suave
      LineLayer(
        id: "ciclovias-main-layer",
        sourceId: "ciclovias-source",
        lineColor: const Color(0xFF38BDF8).value, // sky-400
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineWidthExpression: [
          'interpolate', ['linear'], ['zoom'],
          11, 0.6,
          13, 1.4,
          15, 3.0,
          17, 5.0,
        ],
        lineOpacityExpression: [
          'interpolate', ['linear'], ['zoom'],
          11, 0.22,
          13, 0.45,
          15, 0.7,
        ],
      ),
      // Centro claro — solo aparece al acercarse, da sensación de carril
      LineLayer(
        id: "ciclovias-center-layer",
        sourceId: "ciclovias-source",
        lineColor: const Color(0xFFBAE6FD).value, // sky-200
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineWidthExpression: [
          'interpolate', ['linear'], ['zoom'],
          14, 0.0,
          16, 1.0,
          18, 1.8,
        ],
        lineOpacityExpression: [
          'interpolate', ['linear'], ['zoom'],
          14, 0.0,
          16, 0.6,
        ],
      ),
    ];
  }

  Future<void> _addCicloviasLayer() async {
    if (_cicloviasAdded || mapboxMap == null) return;
    try {
      final style = mapboxMap!.style;

      // Si ya tenemos el GeoJSON procesado en caché, lo usamos directamente
      if (_cicloviasGeoJson != null) {
        final sourceExists = await style.styleSourceExists("ciclovias-source");
        if (sourceExists) await style.removeStyleSource("ciclovias-source");
        for (var lyr in ["ciclovias-glow-layer", "ciclovias-main-layer", "ciclovias-center-layer"]) {
          if (await style.styleLayerExists(lyr)) await style.removeStyleLayer(lyr);
        }
        await style.addSource(GeoJsonSource(id: "ciclovias-source", data: _cicloviasGeoJson!));
        for (final l in _cicloviaLayers()) {
          await style.addLayer(l);
        }
        _cicloviasAdded = true;
        if (_currentAlerts.isNotEmpty) await _updateAlertsLayer(_currentAlerts);
        if (_currentEvents.isNotEmpty) await _updateEventsLayer(_currentEvents);
        return;
      }

      // Ciclovías incluidas en la app (sin depender de internet).
      final data = await rootBundle.loadString('assets/data/ciclovias_scl.json');
      debugPrint("📊 Datos de ciclovías recibidos: ${data.length} caracteres");
      if (data.isEmpty) {
        debugPrint("⚠️ No se recibieron datos de ciclovías");
        return;
      }
      final jsonData = jsonDecode(data);
      debugPrint("📦 JSON parseado correctamente");
      List features = [];
      if (jsonData.containsKey('elements')) {
        debugPrint("✅ Estructura 'elements' encontrada");
        for (var element in jsonData['elements']) {
          if (element['geometry'] != null) {
            if (element['type'] == 'way' || element['type'] == 'relation') {
              List coordinates = [];
              if (element['geometry'] is List) {
                coordinates = (element['geometry'] as List)
                    .map((p) => [p['lon'], p['lat']])
                    .toList();
              } else if (element['geometry'] is Map &&
                  element['geometry']['coordinates'] != null) {
                coordinates = element['geometry']['coordinates'];
              }
              if (coordinates.isNotEmpty) {
                features.add({
                  "type": "Feature",
                  "properties": {
                    "tipo": "ciclovia",
                    "name": element['tags']?['name'] ?? "Ciclovía",
                  },
                  "geometry": {
                    "type": "LineString",
                    "coordinates": coordinates,
                  },
                });
              }
            }
          }
        }
      } else if (jsonData.containsKey('features')) {
        debugPrint("✅ Estructura GeoJSON encontrada");
        features = jsonData['features'];
      }
      debugPrint("📍 Total de features generados: ${features.length}");
      if (features.isEmpty) {
        debugPrint("⚠️ No se generaron features para las ciclovías");
        return;
      }
      final geoJson = jsonEncode({
        "type": "FeatureCollection",
        "features": features,
      });
      final sourceExists = await style.styleSourceExists("ciclovias-source");
      if (sourceExists) {
        await style.removeStyleSource("ciclovias-source");
        debugPrint("🗑️ Fuente anterior eliminada");
      }
      await style.addSource(
        GeoJsonSource(id: "ciclovias-source", data: geoJson),
      );
      debugPrint("✅ Nueva fuente GeoJSON agregada");
      const layers = [
        "ciclovias-glow-layer",
        "ciclovias-main-layer",
        "ciclovias-center-layer",
      ];
      for (var layer in layers) {
        if (await style.styleLayerExists(layer)) {
          await style.removeStyleLayer(layer);
          debugPrint("🗑️ Capa $layer eliminada");
        }
      }
      for (final l in _cicloviaLayers()) {
        await style.addLayer(l);
      }
      debugPrint("✅ Capas de ciclovías agregadas");
      _cicloviasGeoJson = geoJson;
      CacheService.saveCiclovias(geoJson); // Persistir en disco
      _cicloviasAdded = true;
      debugPrint("🎉 ¡Ciclovías cargadas exitosamente!");

      // Las ciclovías quedan encima de todo → re-agregar alertas y eventos
      // para que siempre estén por encima de las líneas.
      if (_currentAlerts.isNotEmpty) {
        await _updateAlertsLayer(_currentAlerts);
      }
      if (_currentEvents.isNotEmpty) {
        await _updateEventsLayer(_currentEvents);
      }
    } catch (e) {
      debugPrint("❌ Error crítico en ciclovías: $e");
      debugPrint("Stack trace: ${StackTrace.current}");
    }
  }

  Future<void> _toggleFollowing() async {
    final enabling = !_isFollowingUser;
    setState(() => _isFollowingUser = enabling);
    _restartGps(); // aplica el filtro de 5 m al seguir / 15 m al soltar
    if (!enabling) return;

    // Al activar el seguimiento, centrar de inmediato en la ubicación actual
    // (sin esperar a que el usuario se mueva 15 m para que el GPS emita).
    try {
      // Asegurar permiso de ubicación.
      var perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied) {
        perm = await geo.Geolocator.requestPermission();
      }
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Activa el permiso de ubicación para centrarte'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      // Usar la última posición conocida para un salto instantáneo…
      geo.Position? pos = _lastPosition ??
          await geo.Geolocator.getLastKnownPosition();
      if (pos != null) _moveCameraInstant(pos);

      // …y luego refinar con una lectura fresca.
      pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      ).timeout(const Duration(seconds: 6));
      _lastPosition = pos;
      if (_isFollowingUser) _moveCameraInstant(pos);
    } catch (e) {
      debugPrint('No se pudo centrar en la ubicación: $e');
    }
  }

  Future<void> _updateCyclistsLayer(
    List<Map<String, dynamic>> cyclists,
  ) async {}

  // ══════════════════════════════════════════════════════════════════════════
  //  ESTACIONAMIENTOS DE BICI
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _ensureParkingIcon() async {
    if (mapboxMap == null || _bikeParkingsIconAdded) return;
    try {
      final style = mapboxMap!.style;
      if (await style.hasStyleImage(_parkingIconId)) {
        _bikeParkingsIconAdded = true;
        return;
      }
      final bytes = await _renderAlertIcon(const Color(0xFF00BCD4), Icons.local_parking);
      await style.addStyleImage(
        _parkingIconId, 1.0, MbxImage(width: 80, height: 80, data: bytes),
        false, [], [], null,
      );
      _bikeParkingsIconAdded = true;
    } catch (e) {
      debugPrint('Error icono parking: $e');
    }
  }

  Future<void> _loadBikeParkings() async {
    if (_bikeParkingsLoading) return;
    setState(() => _bikeParkingsLoading = true);
    try {
      List? elements;
      // 1) Datos empacados en la app (instantáneo, offline y para todos por
      //    igual). Overpass en vivo fallaba en redes móviles, por lo que los
      //    estacionamientos no aparecían en algunos teléfonos.
      try {
        final raw = await rootBundle
            .loadString('assets/data/bike_parkings_scl.json');
        final decoded = jsonDecode(raw);
        elements = (decoded is Map ? decoded['elements'] : decoded) as List?;
        debugPrint('🅿️ Parkings empacados: ${elements?.length ?? 0}');
      } catch (e) {
        debugPrint('⚠️ No se pudo leer el asset de parkings: $e');
      }
      // 2) Respaldo: si no hay asset, intentar Overpass en vivo.
      if (elements == null || elements.isEmpty) {
        final p = _lastPosition;
        final bbox = p != null
            ? '(${p.latitude - 0.12},${p.longitude - 0.12},'
                '${p.latitude + 0.12},${p.longitude + 0.12})'
            : '(-33.70,-70.95,-33.30,-70.45)';
        final query = '[out:json][timeout:25];'
            '(node["amenity"="bicycle_parking"]$bbox;'
            'way["amenity"="bicycle_parking"]$bbox;);'
            'out center;';
        elements = await _fetchOverpass(query);
      }
      if (elements != null) {
        _bikeParkings = elements.map<Map<String, dynamic>>((e) {
          double lat = 0, lng = 0;
          if (e['type'] == 'node') {
            lat = (e['lat'] as num).toDouble();
            lng = (e['lon'] as num).toDouble();
          } else {
            lat = (e['center']?['lat'] as num?)?.toDouble() ?? 0;
            lng = (e['center']?['lon'] as num?)?.toDouble() ?? 0;
          }
          final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? {};
          final isCovered = tags['covered'] == 'yes' ||
              tags['bicycle_parking'] == 'shed' ||
              tags['bicycle_parking'] == 'lockers';
          return {
            'id': e['id'].toString(),
            'lat': lat,
            'lng': lng,
            'name': tags['name'] ?? tags['description'] ?? 'Estacionamiento',
            'capacity': tags['capacity'],
            'covered': isCovered ? 'Cubierto' : 'Descubierto',
            'type': tags['bicycle_parking'] ?? 'stands',
          };
        }).where((p) => (p['lat'] as double) != 0.0).toList();
        debugPrint('🅿️ Parkings cargados: ${_bikeParkings.length}');
      }
    } catch (e) {
      debugPrint('Error cargando parkings: $e');
    } finally {
      if (mounted) setState(() => _bikeParkingsLoading = false);
    }
  }

  Future<void> _updateBikeParkingsLayer() async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    if (await style.styleLayerExists(_parkingLyrId)) await style.removeStyleLayer(_parkingLyrId);
    if (await style.styleSourceExists(_parkingSrcId)) await style.removeStyleSource(_parkingSrcId);
    if (!_showBikeParkings || _bikeParkings.isEmpty) return;
    await _ensureParkingIcon();
    final features = _bikeParkings.map((p) => {
      'type': 'Feature',
      'properties': {'id': p['id'], 'name': p['name'], 'capacity': p['capacity'], 'covered': p['covered'], 'type': p['type']},
      'geometry': {'type': 'Point', 'coordinates': [p['lng'], p['lat']]},
    }).toList();
    final fc = jsonEncode({'type': 'FeatureCollection', 'features': features});
    await style.addSource(GeoJsonSource(id: _parkingSrcId, data: fc));
    await style.addLayer(SymbolLayer(
      id: _parkingLyrId,
      sourceId: _parkingSrcId,
      iconImage: _parkingIconId,
      iconSize: 0.35,
      // Detección de colisiones: Mapbox oculta los pines que se encimarían y
      // muestra un conjunto representativo y legible en cualquier zoom (ni
      // amontonado ni vacío). Al acercarse aparecen más.
      iconAllowOverlap: false,
      iconIgnorePlacement: false,
    ));
  }

  void _toggleBikeParkings() async {
    final newVal = !_showBikeParkings;
    setState(() => _showBikeParkings = newVal);
    if (newVal && _bikeParkings.isEmpty) {
      await _loadBikeParkings();
    }
    await _updateBikeParkingsLayer();
  }

  void _showBikeParkingModal(Map<String, dynamic> props) {
    final id = props['id']?.toString() ?? '';
    final parking = _bikeParkings.firstWhere(
      (p) => p['id'] == id,
      orElse: () => props,
    );
    final destLat = (parking['lat'] as num?)?.toDouble() ?? 0;
    final destLng = (parking['lng'] as num?)?.toDouble() ?? 0;
    final destName = parking['name']?.toString() ?? 'Estacionamiento';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E18),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: Color(0xFF00BCD4), shape: BoxShape.circle),
                child: const Icon(Icons.local_parking, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destName,
                    style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    parking['covered']?.toString() ?? 'Descubierto',
                    style: const TextStyle(fontFamily: 'Poppins', color: Colors.grey, fontSize: 13),
                  ),
                ],
              )),
            ]),
            const SizedBox(height: 14),
            if (parking['capacity'] != null)
              _infoRow(Icons.bike_scooter, 'Capacidad', '${parking['capacity']} bicis'),
            _infoRow(Icons.inventory_2_outlined, 'Tipo', parking['type']?.toString() ?? 'stands'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: destLat != 0
                    ? () => _navigateTo(destLat, destLng, destName)
                    : null,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Ir aquí'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00BCD4),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BICIMETRO
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _ensureBicimetroIcon() async {
    if (mapboxMap == null || _bicimetroIconAdded) return;
    try {
      final style = mapboxMap!.style;
      if (await style.hasStyleImage(_bicimetroIconId)) {
        _bicimetroIconAdded = true;
        return;
      }
      final bytes = await _renderAlertIcon(const Color(0xFF7C3AED), Icons.train);
      await style.addStyleImage(
        _bicimetroIconId, 1.0, MbxImage(width: 80, height: 80, data: bytes),
        false, [], [], null,
      );
      _bicimetroIconAdded = true;
    } catch (e) {
      debugPrint('Error icono bicimetro: $e');
    }
  }

  Future<void> _updateBicimetroLayer() async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    if (await style.styleLayerExists(_bicimetroLyrId)) await style.removeStyleLayer(_bicimetroLyrId);
    if (await style.styleSourceExists(_bicimetroSrcId)) await style.removeStyleSource(_bicimetroSrcId);
    if (!_showBicimetro) return;
    await _ensureBicimetroIcon();
    final features = _kBicimetroStations.map((s) => {
      'type': 'Feature',
      'properties': {'name': s['name'].toString(), 'line': s['line'].toString()},
      'geometry': {'type': 'Point', 'coordinates': [s['lng'], s['lat']]},
    }).toList();
    final fc = jsonEncode({'type': 'FeatureCollection', 'features': features});
    await style.addSource(GeoJsonSource(id: _bicimetroSrcId, data: fc));
    await style.addLayer(SymbolLayer(
      id: _bicimetroLyrId,
      sourceId: _bicimetroSrcId,
      iconImage: _bicimetroIconId,
      iconSize: 0.35,
      iconAllowOverlap: false,
      iconIgnorePlacement: false,
    ));
  }

  void _toggleBicimetro() async {
    setState(() => _showBicimetro = !_showBicimetro);
    await _updateBicimetroLayer();
  }

  void _showBicimetroModal(Map<String, dynamic> props) {
    final name = props['name']?.toString() ?? 'Estación';
    final line = props['line']?.toString() ?? '';
    final station = _kBicimetroStations.firstWhere(
      (s) => s['name'].toString() == name,
      orElse: () => const {'lat': 0.0, 'lng': 0.0, 'name': '', 'line': ''},
    );
    final destLat = (station['lat'] as num).toDouble();
    final destLng = (station['lng'] as num).toDouble();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E18),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: Color(0xFF7C3AED), shape: BoxShape.circle),
                child: const Icon(Icons.train, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  Text('Metro $line', style: const TextStyle(fontFamily: 'Poppins', color: Color(0xFF9CA3AF), fontSize: 13)),
                ],
              )),
            ]),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Horarios BiciMetro', style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  _infoRow(Icons.check_circle, 'Fin de semana', 'Todo el día ✔'),
                  _infoRow(Icons.check_circle, 'Lunes – viernes', '9:00 – 18:00  ·  20:00 en adelante ✔'),
                  _infoRow(Icons.block, 'Punta mañana', '7:00 – 9:00 ✖'),
                  _infoRow(Icons.block, 'Punta tarde', '18:00 – 20:00 ✖'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: destLat != 0
                    ? () => _navigateTo(destLat, destLng, name)
                    : null,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Ir a esta estación'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SERVICIOS PARA BICI — inflado / talleres / gasolineras con aire (OSM)
  // ══════════════════════════════════════════════════════════════════════════

  /// Devuelve (color, ícono Material) según la categoría del servicio.
  static (Color, IconData) _serviceStyle(String category) {
    switch (category) {
      case 'repair': // punto público de inflado/reparación
        return (const Color(0xFF22C55E), Icons.build); // llave de reparación
      case 'shop': // taller / tienda de bicis
        return (const Color(0xFF3B82F6), Icons.storefront); // tienda
      case 'fuel': // gasolinera con aire (Copec, etc.)
        return (const Color(0xFFE2231A), Icons.local_gas_station); // rojo Copec
      case 'water': // punto de agua / hidratación
        return (const Color(0xFF2196F3), Icons.water_drop); // azul agua
      default:
        return (const Color(0xFF22C55E), Icons.air);
    }
  }

  static String _serviceLabel(String category) {
    switch (category) {
      case 'repair':
        return 'Punto de inflado / reparación';
      case 'shop':
        return 'Taller / tienda de bicis';
      case 'fuel':
        return 'Gasolinera con aire';
      case 'water':
        return 'Punto de agua (hidratación)';
      default:
        return 'Servicio para bici';
    }
  }

  Future<void> _ensureServicesIcons() async {
    if (mapboxMap == null || _bikeServicesIconsAdded) return;
    try {
      final style = mapboxMap!.style;
      for (final cat in ['repair', 'shop', 'fuel', 'water']) {
        final iconId = 'svc-icon-$cat';
        if (await style.hasStyleImage(iconId)) continue;
        final (color, icon) = _serviceStyle(cat);
        final bytes = await _renderPinIcon(color, icon);
        await style.addStyleImage(
          iconId, 1.0, MbxImage(width: 84, height: 108, data: bytes),
          false, [], [], null,
        );
      }

      // Pin especial con el logo de Copec dentro de la cabeza.
      if (!await style.hasStyleImage('svc-icon-fuel-copec')) {
        final data = await rootBundle.load('assets/brands/copec.png');
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        final bytes = await _renderLogoPin(
          frame.image,
          const Color(0xFFE2231A),
        );
        await style.addStyleImage(
          'svc-icon-fuel-copec', 1.0,
          MbxImage(width: 88, height: 112, data: bytes),
          false, [], [], null,
        );
      }

      _bikeServicesIconsAdded = true;
    } catch (e) {
      debugPrint('Error iconos servicios: $e');
    }
  }

  /// Pin tipo globito con un logo (imagen) dentro de la cabeza blanca.
  Future<Uint8List> _renderLogoPin(ui.Image logo, Color tailColor) async {
    const double w = 88;
    const double h = 112;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final center = const ui.Offset(w / 2, w / 2 + 2);
    final headR = w / 2 - 4;
    final tip = const ui.Offset(w / 2, h - 3);

    final shadow = ui.Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawCircle(center.translate(0, 3), headR, shadow);

    // Cola + aro del color de la marca
    final colorPaint = ui.Paint()..color = tailColor;
    final body = ui.Path()
      ..moveTo(center.dx - headR * 0.6, center.dy + headR * 0.72)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(center.dx + headR * 0.6, center.dy + headR * 0.72)
      ..close();
    canvas.drawPath(body, colorPaint);
    canvas.drawCircle(center, headR, colorPaint);

    // Cabeza blanca
    canvas.drawCircle(center, headR - 4, ui.Paint()..color = Colors.white);

    // Logo recortado dentro de la cabeza (contain por el lado mayor)
    canvas.save();
    canvas.clipPath(
      ui.Path()
        ..addOval(ui.Rect.fromCircle(center: center, radius: headR - 6)),
    );
    final d = (headR - 8) * 2;
    final lw = logo.width.toDouble();
    final lh = logo.height.toDouble();
    final scale = d / (lw > lh ? lw : lh);
    final dst = ui.Rect.fromCenter(
      center: center,
      width: lw * scale,
      height: lh * scale,
    );
    canvas.drawImageRect(
      logo,
      ui.Rect.fromLTWH(0, 0, lw, lh),
      dst,
      ui.Paint(),
    );
    canvas.restore();

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  /// Consulta Overpass probando varios servidores espejo en orden hasta que
  /// uno responda. Devuelve la lista de `elements` o null si todos fallan.
  Future<List?> _fetchOverpass(String query) async {
    const mirrors = [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
      'https://overpass.private.coffee/api/interpreter',
      'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    ];
    for (final url in mirrors) {
      try {
        final res = await http
            .post(
              Uri.parse(url),
              body: 'data=${Uri.encodeQueryComponent(query)}',
            )
            .timeout(const Duration(seconds: 25));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          return data['elements'] as List;
        }
        debugPrint('Overpass $url → HTTP ${res.statusCode}');
      } catch (e) {
        debugPrint('Overpass $url falló: $e');
      }
    }
    return null;
  }

  /// Carga el dataset de servicios (talleres, aire, Copec y otras gasolineras).
  /// Usa el archivo incluido en la app (siempre disponible, sin internet) y,
  /// si la red responde, lo refresca desde OpenStreetMap.
  Future<void> _loadBikeServices() async {
    if (_bikeServicesLoading) return;
    setState(() => _bikeServicesLoading = true);
    try {
      // 1) Dataset incluido en la app → garantiza que siempre haya puntos.
      if (_bikeServices.isEmpty) {
        _bikeServices = await _loadBundledServices();
        debugPrint('🔧 Servicios (incluidos): ${_bikeServices.length}');
      }

      // 2) Refresco opcional desde Overpass (mejor esfuerzo, no bloquea).
      const bbox = '(-33.70,-70.95,-33.30,-70.45)';
      final query = '[out:json][timeout:25];'
          '('
          'nwr["amenity"="bicycle_repair_station"]$bbox;'
          'nwr["amenity"="compressed_air"]$bbox;'
          'nwr["shop"="bicycle"]$bbox;'
          'nwr["amenity"="fuel"]["brand"]$bbox;'
          'nwr["amenity"="fuel"]["compressed_air"="yes"]$bbox;'
          ');'
          'out center;';
      final elements = await _fetchOverpass(query);
      if (elements != null && elements.length > 50) {
        _bikeServices = _mapServiceElements(elements);
        debugPrint('🔧 Servicios (Overpass): ${_bikeServices.length}');
      }
    } catch (e) {
      debugPrint('Error cargando servicios bici: $e');
    } finally {
      if (mounted) setState(() => _bikeServicesLoading = false);
    }
  }

  /// Lee el dataset de servicios incluido en los assets de la app.
  Future<List<Map<String, dynamic>>> _loadBundledServices() async {
    try {
      final raw =
          await rootBundle.loadString('assets/data/bike_services_scl.json');
      final list = (jsonDecode(raw) as List);
      return list.map<Map<String, dynamic>>((e) {
        final m = e as Map<String, dynamic>;
        return {
          'id': m['id'].toString(),
          'lat': (m['lat'] as num).toDouble(),
          'lng': (m['lng'] as num).toDouble(),
          'name': m['name'],
          'brand': m['brand'],
          'category': m['category'],
          'icon_id': m['icon_id'],
          'has_pump': m['has_pump'],
        };
      }).toList();
    } catch (e) {
      debugPrint('Error leyendo dataset incluido: $e');
      return [];
    }
  }

  /// Convierte los elementos crudos de Overpass al formato de la capa.
  List<Map<String, dynamic>> _mapServiceElements(List elements) {
    return elements.map<Map<String, dynamic>>((e) {
      double lat = 0, lng = 0;
      if (e['type'] == 'node') {
        lat = (e['lat'] as num).toDouble();
        lng = (e['lon'] as num).toDouble();
      } else {
        lat = (e['center']?['lat'] as num?)?.toDouble() ?? 0;
        lng = (e['center']?['lon'] as num?)?.toDouble() ?? 0;
      }
      final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? {};

      String category;
      if (tags['shop'] == 'bicycle') {
        category = 'shop';
      } else if (tags['amenity'] == 'fuel') {
        category = 'fuel';
      } else if (tags['amenity'] == 'drinking_water') {
        category = 'water';
      } else {
        category = 'repair';
      }

      final hasPump = tags['service:bicycle:pump'] == 'yes' ||
          tags['compressed_air'] == 'yes' ||
          tags['amenity'] == 'compressed_air' ||
          tags['amenity'] == 'bicycle_repair_station';

      final brand = (tags['brand'] ?? tags['operator'] ?? '').toString();
      final displayName = category == 'fuel'
          ? (brand.isNotEmpty ? brand : (tags['name']?.toString() ?? 'Gasolinera'))
          : (tags['name']?.toString() ??
                (brand.isNotEmpty ? brand : _serviceLabel(category)));

      final isCopec =
          category == 'fuel' && brand.toLowerCase().contains('copec');
      final iconId = isCopec ? 'svc-icon-fuel-copec' : 'svc-icon-$category';

      return {
        'id': e['id'].toString(),
        'lat': lat,
        'lng': lng,
        'name': displayName,
        'brand': brand,
        'category': category,
        'icon_id': iconId,
        'has_pump': hasPump,
      };
    }).where((p) => (p['lat'] as double) != 0.0).toList();
  }

  Future<void> _updateBikeServicesLayer() async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    if (await style.styleLayerExists(_servicesLyrId)) {
      await style.removeStyleLayer(_servicesLyrId);
    }
    if (await style.styleSourceExists(_servicesSrcId)) {
      await style.removeStyleSource(_servicesSrcId);
    }
    if (!_showBikeServices || _bikeServices.isEmpty) return;
    await _ensureServicesIcons();
    final features = _bikeServices.map((p) => {
      'type': 'Feature',
      'properties': {
        'id': p['id'],
        'name': p['name'],
        'category': p['category'],
        'icon_id': p['icon_id'],
        'has_pump': p['has_pump'],
      },
      'geometry': {'type': 'Point', 'coordinates': [p['lng'], p['lat']]},
    }).toList();
    final fc = jsonEncode({'type': 'FeatureCollection', 'features': features});
    await style.addSource(GeoJsonSource(id: _servicesSrcId, data: fc));
    await style.addLayer(SymbolLayer(
      id: _servicesLyrId,
      sourceId: _servicesSrcId,
      iconImage: 'svc-icon-repair', // se sobreescribe por feature abajo
      iconSize: 0.42,
      iconAnchor: IconAnchor.BOTTOM, // la punta del pin marca el lugar
      // Colisión: declutter automático sin desaparecer del todo al alejarse.
      iconAllowOverlap: false,
      iconIgnorePlacement: false,
    ));
    // Ícono según la categoría de cada punto.
    await style.setStyleLayerProperty(
      _servicesLyrId,
      'icon-image',
      jsonEncode(['get', 'icon_id']),
    );
  }

  /// Carga (una sola vez) las capas activas por defecto, esperando a tener un
  /// fix de GPS para consultar solo el área alrededor del usuario.
  void _maybeAutoLoadLayers() {
    if (_autoLayersTriggered || mapboxMap == null || _lastPosition == null) {
      return;
    }
    _autoLayersTriggered = true;
    if (_showBikeParkings && _bikeParkings.isEmpty && !_bikeParkingsLoading) {
      _loadBikeParkings().then((_) => _updateBikeParkingsLayer());
    }
    if (_showBikeServices && _bikeServices.isEmpty && !_bikeServicesLoading) {
      _loadBikeServices().then((_) => _updateBikeServicesLayer());
    }
  }

  void _toggleBikeServices() async {
    final newVal = !_showBikeServices;
    setState(() => _showBikeServices = newVal);
    if (newVal && _bikeServices.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔍 Buscando talleres y puntos de aire…'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      await _loadBikeServices();
      if (mounted) {
        final n = _bikeServices.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(n > 0
                ? '✅ $n puntos cargados (talleres, aire y gasolineras)'
                : '⚠️ No se encontraron puntos (revisa tu conexión)'),
            backgroundColor: n > 0 ? Colors.green : Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    await _updateBikeServicesLayer();
  }

  void _showBikeServiceModal(Map<String, dynamic> props) {
    final id = props['id']?.toString() ?? '';
    final svc = _bikeServices.firstWhere(
      (p) => p['id'] == id,
      orElse: () => props,
    );
    final destLat = (svc['lat'] as num?)?.toDouble() ?? 0;
    final destLng = (svc['lng'] as num?)?.toDouble() ?? 0;
    final category = svc['category']?.toString() ?? 'repair';
    final name = svc['name']?.toString() ?? _serviceLabel(category);
    final hasPump = svc['has_pump'] == true;
    final (color, icon) = _serviceStyle(category);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E18),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(_serviceLabel(category), style: const TextStyle(fontFamily: 'Poppins', color: Colors.grey, fontSize: 13)),
                ],
              )),
            ]),
            const SizedBox(height: 14),
            _infoRow(
              hasPump ? Icons.check_circle : Icons.help_outline,
              'Bomba de aire',
              hasPump
                  ? 'Disponible'
                  : (category == 'fuel'
                        ? 'Consultar en el local'
                        : 'No confirmado'),
            ),
            if (category == 'fuel' && svc['brand'] != null &&
                svc['brand'].toString().isNotEmpty)
              _infoRow(Icons.local_gas_station, 'Marca', svc['brand'].toString()),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: destLat != 0 ? () => _navigateTo(destLat, destLng, name) : null,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Ir aquí'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  CICLORECREOVÍA — cierres de calles dominicales para ciclistas
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> _loadCicloRecreo() async {
    try {
      final raw =
          await rootBundle.loadString('assets/data/ciclorecreovia.json');
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error cargando CicloRecreoVía: $e');
      return [];
    }
  }

  Future<void> _ensureCicloRecreoIcon() async {
    if (mapboxMap == null || _cicloRecreoIconAdded) return;
    try {
      final style = mapboxMap!.style;
      if (await style.hasStyleImage('crv-icon')) {
        _cicloRecreoIconAdded = true;
        return;
      }
      // Pin lima con ícono de evento/bici (cierre recreativo).
      final bytes =
          await _renderPinIcon(const Color(0xFF7CB342), Icons.event_available);
      await style.addStyleImage(
        'crv-icon', 1.0, MbxImage(width: 84, height: 108, data: bytes),
        false, [], [], null,
      );
      _cicloRecreoIconAdded = true;
    } catch (e) {
      debugPrint('Error icono CicloRecreoVía: $e');
    }
  }

  Future<void> _updateCicloRecreoLayer() async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    if (await style.styleLayerExists(_crvLyrId)) {
      await style.removeStyleLayer(_crvLyrId);
    }
    if (await style.styleSourceExists(_crvSrcId)) {
      await style.removeStyleSource(_crvSrcId);
    }
    if (!_showCicloRecreo || _cicloRecreoPoints.isEmpty) return;
    await _ensureCicloRecreoIcon();
    final features = _cicloRecreoPoints.map((p) => {
      'type': 'Feature',
      'properties': {'id': p['id'], 'comuna': p['comuna']},
      'geometry': {
        'type': 'Point',
        'coordinates': [
          (p['lng'] as num).toDouble(),
          (p['lat'] as num).toDouble(),
        ],
      },
    }).toList();
    final fc = jsonEncode({'type': 'FeatureCollection', 'features': features});
    await style.addSource(GeoJsonSource(id: _crvSrcId, data: fc));
    await style.addLayer(SymbolLayer(
      id: _crvLyrId,
      sourceId: _crvSrcId,
      iconImage: 'crv-icon',
      iconSize: 0.42,
      iconAnchor: IconAnchor.BOTTOM,
      iconAllowOverlap: false,
      iconIgnorePlacement: false,
    ));
  }

  void _toggleCicloRecreo() async {
    setState(() => _showCicloRecreo = !_showCicloRecreo);
    await _updateCicloRecreoLayer();
  }

  void _showCicloRecreoModal(Map<String, dynamic> props) {
    final id = props['id']?.toString() ?? '';
    final p = _cicloRecreoPoints.firstWhere(
      (e) => e['id'] == id,
      orElse: () => props,
    );
    final lat = (p['lat'] as num?)?.toDouble() ?? 0;
    final lng = (p['lng'] as num?)?.toDouble() ?? 0;
    final comuna = p['comuna']?.toString() ?? 'CicloRecreoVía';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E18),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: Color(0xFF7CB342), shape: BoxShape.circle),
                child: const Icon(Icons.event_available, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CicloRecreoVía', style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(comuna, style: const TextStyle(fontFamily: 'Poppins', color: Colors.grey, fontSize: 13)),
                ],
              )),
            ]),
            const SizedBox(height: 14),
            _infoRow(Icons.route, 'Ruta', p['ruta']?.toString() ?? '-'),
            _infoRow(Icons.calendar_today, 'Días', p['dias']?.toString() ?? 'Domingos'),
            _infoRow(Icons.schedule, 'Horario', p['horario']?.toString() ?? '09:00 a 14:00'),
            const SizedBox(height: 8),
            Text(
              p['descripcion']?.toString() ?? '',
              style: const TextStyle(fontFamily: 'Poppins', color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: lat != 0 ? () => _navigateTo(lat, lng, 'CicloRecreoVía $comuna') : null,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Ir aquí'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7CB342),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BÚSQUEDA DE DESTINO — Mapbox Geocoding (sin backend propio)
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<_GeoResult>> _geocodePlaces(String query) async {
    if (query.trim().length < 3) return [];
    // Sesgar resultados hacia la ubicación del usuario (o centro de Santiago).
    final prox = _lastPosition != null
        ? '${_lastPosition!.longitude},${_lastPosition!.latitude}'
        : '-70.6483,-33.4569';
    final url =
        'https://api.mapbox.com/geocoding/v5/mapbox.places/'
        '${Uri.encodeComponent(query.trim())}.json'
        '?access_token=$kMapboxToken'
        '&country=cl&language=es&limit=6&proximity=$prox';
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final feats = (body['features'] as List?) ?? [];
      return feats.map((f) {
        final m = f as Map<String, dynamic>;
        final center = m['center'] as List; // [lng, lat]
        return _GeoResult(
          name: (m['text'] ?? '') as String,
          fullName: (m['place_name'] ?? '') as String,
          lng: (center[0] as num).toDouble(),
          lat: (center[1] as num).toDouble(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  void _openPlaceSearch() {
    final controller = TextEditingController();
    Timer? debounce;
    List<_GeoResult> results = [];
    bool loading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            void runSearch(String q) {
              debounce?.cancel();
              if (q.trim().length < 3) {
                setSheet(() {
                  results = [];
                  loading = false;
                });
                return;
              }
              setSheet(() => loading = true);
              debounce = Timer(const Duration(milliseconds: 400), () async {
                final r = await _geocodePlaces(q);
                setSheet(() {
                  results = r;
                  loading = false;
                });
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xF5080810),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      onChanged: runSearch,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: '¿A dónde quieres ir?',
                        hintStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white38,
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.greenAccent,
                          size: 20,
                        ),
                        suffixIcon: loading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.greenAccent,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (results.isEmpty &&
                        !loading &&
                        controller.text.trim().length >= 3)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          'Sin resultados. Prueba con otro nombre.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else if (results.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          'Escribe una calle, plaza o lugar de Santiago',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(sheetCtx).size.height * 0.4,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: results.length,
                          separatorBuilder: (_, _) =>
                              const Divider(color: Colors.white10, height: 1),
                          itemBuilder: (_, i) {
                            final r = results[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.place,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              title: Text(
                                r.name,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                r.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                              onTap: () {
                                debounce?.cancel();
                                _navigateTo(r.lat, r.lng, r.name);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _navigateTo(double destLat, double destLng, String name) async {
    if (!mounted) return;
    Navigator.pop(context); // Cierra el modal

    // Ocultar todas las capas de markers opcionales, guardando estado previo
    setState(() {
      _prevShowBikeParkings = _showBikeParkings;
      _prevShowBicimetro = _showBicimetro;
      _prevShowBikeServices = _showBikeServices;
      _showBikeParkings = false;
      _showBicimetro = false;
      _showBikeServices = false;
      _routePlannerOpen = true;
      _routeWps.clear();
      _routeDistKm = null;
      _routeDurMin = null;
      _routeDifficulty = null;
      _routeElevGain = null;
    });
    await _updateBikeParkingsLayer();
    await _updateBicimetroLayer();
    await _updateBikeServicesLayer();

    // Waypoint 1: posición actual
    if (_lastPosition != null) {
      _routeWps.add(_RouteWp(
        lat: _lastPosition!.latitude,
        lng: _lastPosition!.longitude,
        label: 'Mi ubicación',
      ));
    } else {
      try {
        final pos = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.high,
        );
        _routeWps.add(_RouteWp(lat: pos.latitude, lng: pos.longitude, label: 'Mi ubicación'));
      } catch (_) {}
    }

    // Waypoint 2: destino
    _routeWps.add(_RouteWp(lat: destLat, lng: destLng, label: name));

    await _loadFavorites();
    await _redrawRoutePins();

    if (_routeWps.length >= 2) await _calcRoute();
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Icon(icon, color: Colors.greenAccent, size: 13),
      const SizedBox(width: 7),
      Text(label, style: const TextStyle(fontFamily: 'Poppins', color: Colors.grey, fontSize: 12)),
      const SizedBox(width: 4),
      Expanded(child: Text(value, style: const TextStyle(fontFamily: 'Poppins', color: Colors.white70, fontSize: 12), textAlign: TextAlign.right)),
    ]),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  DIFICULTAD DE RUTA — Open-Elevation API
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _fetchRouteElevation() async {
    if (_routeCoords.isEmpty) return;
    if (mounted) setState(() => _elevationLoading = true);
    try {
      // Muestrear hasta 30 puntos equidistantes
      final total = _routeCoords.length;
      final step = (total / 30).ceil().clamp(1, total);
      final sample = <Map<String, double>>[];
      for (int i = 0; i < total; i += step) {
        // _routeCoords almacena [lng, lat]
        sample.add({'latitude': _routeCoords[i][1], 'longitude': _routeCoords[i][0]});
      }
      // Asegurar que incluimos el último punto
      if (sample.last['latitude'] != _routeCoords.last[1]) {
        sample.add({'latitude': _routeCoords.last[1], 'longitude': _routeCoords.last[0]});
      }

      final body = jsonEncode({'locations': sample});
      final res = await http.post(
        Uri.parse('https://api.open-elevation.com/api/v1/lookup'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List;
        double gain = 0.0;
        for (int i = 1; i < results.length; i++) {
          final diff = (results[i]['elevation'] as num) - (results[i - 1]['elevation'] as num);
          if (diff > 0) gain += diff.toDouble();
        }
        final difficulty = gain < 100 ? 'Fácil' : gain < 300 ? 'Moderada' : 'Difícil';
        if (mounted) setState(() { _routeElevGain = gain; _routeDifficulty = difficulty; _elevationLoading = false; });
        debugPrint('🏔️ Desnivel: ${gain.toStringAsFixed(0)}m → $difficulty');
      } else {
        if (mounted) setState(() => _elevationLoading = false);
      }
    } catch (e) {
      debugPrint('Error elevación: $e');
      if (mounted) setState(() => _elevationLoading = false);
    }
  }
}

// ✅ FORMULARIO SIMPLE PARA ALERTA
class _SimpleAlertFormDialog extends StatefulWidget {
  final Point point;

  const _SimpleAlertFormDialog({required this.point});

  @override
  State<_SimpleAlertFormDialog> createState() => _SimpleAlertFormDialogState();
}

class _SimpleAlertFormDialogState extends State<_SimpleAlertFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _picker = ImagePicker();

  String _selectedType = 'danger';
  File? _photoFile;
  final bool _uploadingPhoto = false;

  final Map<String, AlertTypeInfo> _alertTypes = {
    'danger': AlertTypeInfo(Icons.warning, Colors.red, 'Peligro'),
    'theft': AlertTypeInfo(Icons.no_accounts, Colors.purple, 'Robo'),
    'construction': AlertTypeInfo(Icons.construction, Colors.orange, 'Obras'),
    'accident': AlertTypeInfo(Icons.car_crash, Colors.deepOrange, 'Accidente'),
    'other': AlertTypeInfo(Icons.info, Colors.blue, 'Otro'),
  };

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1280,
      );
      if (picked != null && mounted) {
        setState(() => _photoFile = File(picked.path));
      }
    } catch (e) {
      debugPrint('Error seleccionando imagen: $e');
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.greenAccent,
              ),
              title: const Text(
                'Tomar foto',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: Colors.greenAccent,
              ),
              title: const Text(
                'Elegir de galería',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_photoFile != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Eliminar foto',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.redAccent,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  setState(() => _photoFile = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _alertTypes[_selectedType]?.color ?? Colors.red;

    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E18),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.08),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.07)),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _alertTypes[_selectedType]?.icon ?? Icons.warning,
                    color: accentColor,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Nueva Alerta',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white38,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),

            // Contenido scrollable
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Chips de tipo
                      const Text(
                        'TIPO',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white24,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _alertTypes.entries.map((entry) {
                          final isSelected = _selectedType == entry.key;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedType = entry.key),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? entry.value.color.withOpacity(0.18)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? entry.value.color.withOpacity(0.7)
                                      : Colors.white.withOpacity(0.1),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    entry.value.icon,
                                    color: isSelected
                                        ? entry.value.color
                                        : Colors.white38,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    entry.value.label,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      color: isSelected
                                          ? entry.value.color
                                          : Colors.white38,
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Título
                      const Text(
                        'DETALLES',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white24,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _titleController,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Título',
                          labelStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: accentColor.withOpacity(0.6),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _descriptionController,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Descripción',
                          labelStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: accentColor.withOpacity(0.6),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _locationController,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Nombre del lugar (opcional)',
                          labelStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Sección foto
                      const Text(
                        'FOTO DEL SECTOR',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white24,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _showPhotoOptions,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: _photoFile != null ? 140 : 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _photoFile != null
                                  ? Colors.greenAccent.withOpacity(0.4)
                                  : Colors.white.withOpacity(0.1),
                              width: _photoFile != null ? 1.5 : 1,
                            ),
                          ),
                          child: _photoFile != null
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(13),
                                      child: Image.file(
                                        _photoFile!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: GestureDetector(
                                        onTap: () =>
                                            setState(() => _photoFile = null),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_a_photo_outlined,
                                      color: Colors.white24,
                                      size: 24,
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Agregar foto (opcional)',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        color: Colors.white38,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),

            // Botones fijos abajo
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white38,
                        side: BorderSide(color: Colors.white.withOpacity(0.1)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(fontFamily: 'Poppins'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _uploadingPhoto
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                Navigator.pop(context, {
                                  'type': _selectedType,
                                  'title': _titleController.text,
                                  'description': _descriptionController.text,
                                  'locationName':
                                      _locationController.text.isNotEmpty
                                      ? _locationController.text
                                      : 'Ubicación seleccionada',
                                  'photoFile': _photoFile,
                                });
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      child: const Text('Crear Alerta'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }
}

class AlertTypeInfo {
  final IconData icon;
  final Color color;
  final String label;

  AlertTypeInfo(this.icon, this.color, this.label);
}

/// Botón circular de perfil para la barra superior del mapa.
class _ProfileButton extends StatelessWidget {
  final bool isDayMode;
  _ProfileButton({this.isDayMode = false});

  final _supabase = Supabase.instance.client;

  String _initials(String? fullName, String? username, String? email) {
    final name =
        (fullName?.trim().isNotEmpty == true
                ? fullName!
                : username?.trim().isNotEmpty == true
                ? username!
                : email ?? '')
            .trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final avatarUrl = user?.userMetadata?['avatar_url'] as String?;
    final fullName = user?.userMetadata?['full_name'] as String?;
    final username = user?.userMetadata?['username'] as String?;
    final email = user?.email;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfilePage()),
      ),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.greenAccent, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipOval(
          child: avatarUrl != null && avatarUrl.isNotEmpty
              ? Image.network(
                  avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      _fallback(_initials(fullName, username, email)),
                )
              : _fallback(_initials(fullName, username, email)),
        ),
      ),
    );
  }

  Widget _fallback(String initials) {
    return Container(
      color: isDayMode ? Colors.white : Colors.black.withOpacity(0.8),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: isDayMode ? const Color(0xFF00A86B) : Colors.greenAccent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ─── Waypoint del planificador de rutas ──────────────────────────────────────

class _RouteWp {
  final double lat;
  final double lng;
  final String label;
  const _RouteWp({required this.lat, required this.lng, required this.label});
}

/// Popup estilo "Pokémon GO" que pregunta si el usuario es pasajero
/// (auto/micro/metro) cuando la velocidad es demasiado alta para ir en bici.
class _PassengerPrompt extends StatelessWidget {
  final int speedKmh;
  const _PassengerPrompt({required this.speedKmh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 320),
        curve: Curves.elasticOut,
        tween: Tween(begin: 0.7, end: 1.0),
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF12213A), Color(0xFF0A0A14)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.lightBlueAccent.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.lightBlueAccent.withOpacity(0.25),
                blurRadius: 40,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Badge de velocidad pulsante
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.speed_rounded,
                        color: Colors.redAccent, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '$speedKmh km/h',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.redAccent,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '¡Vas muy rápido! 🏎️',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Eso es mucho para ir pedaleando.\n¿Vas como pasajero?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white60,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _vehicleOption(context, '🚗', 'Auto', 'auto'),
                  const SizedBox(width: 10),
                  _vehicleOption(context, '🚌', 'Micro', 'micro'),
                  const SizedBox(width: 10),
                  _vehicleOption(context, '🚇', 'Metro', 'metro'),
                ],
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, 'bici'),
                icon: const Text('🚴', style: TextStyle(fontSize: 16)),
                label: const Text(
                  'No, sigo pedaleando',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.greenAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vehicleOption(
      BuildContext context, String emoji, String label, String value) {
    return Expanded(
      child: GestureDetector(
        onTap: () => Navigator.pop(context, value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.lightBlueAccent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.lightBlueAccent.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resultado de búsqueda de lugar (geocoding de Mapbox).
class _GeoResult {
  final String name;
  final String fullName;
  final double lat;
  final double lng;
  const _GeoResult({
    required this.name,
    required this.fullName,
    required this.lat,
    required this.lng,
  });
}

/// Indicador visual que se expande al hacer long press en el mapa.
class _LongPressRipple extends StatefulWidget {
  final Offset position;
  const _LongPressRipple({required this.position});

  @override
  State<_LongPressRipple> createState() => _LongPressRippleState();
}

class _LongPressRippleState extends State<_LongPressRipple>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacity = Tween<double>(
      begin: 0.8,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.position.dx - 40,
      top: widget.position.dy - 40,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context2, child2) => Opacity(
            opacity: _opacity.value,
            child: Transform.scale(
              scale: _scale.value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.redAccent, width: 3),
                  color: Colors.redAccent.withOpacity(0.25),
                ),
                child: const Center(
                  child: Icon(Icons.add_alert, color: Colors.white, size: 30),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Botón de pánico ──────────────────────────────────────────────────────────

class _PanicButton extends StatefulWidget {
  @override
  State<_PanicButton> createState() => _PanicButtonState();
}

class _PanicButtonState extends State<_PanicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showEmergencyMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EmergencySheet(onCall: _call),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Transform.scale(scale: _pulse.value, child: child),
      child: GestureDetector(
        onTap: () => _showEmergencyMenu(context),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.shade700,
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.55),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.sos_rounded, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}

class _EmergencySheet extends StatelessWidget {
  final Future<void> Function(String) onCall;

  const _EmergencySheet({required this.onCall});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      // Sube el sheet si hay teclado o notch inferior
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Container(
          margin: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomPadding),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F1A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.red.withOpacity(0.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.2),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.sos_rounded,
                      color: Colors.red,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergencias Chile',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Selecciona el servicio de emergencia',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _EmergencyTile(
                icon: Icons.local_police_rounded,
                color: const Color(0xFF4A90D9),
                label: 'Carabineros',
                number: '133',
                description: 'Policía de Chile',
                onTap: () {
                  Navigator.pop(context);
                  onCall('133');
                },
              ),
              _EmergencyTile(
                icon: Icons.local_hospital_rounded,
                color: const Color(0xFFE53935),
                label: 'SAMU',
                number: '131',
                description: 'Urgencias médicas',
                onTap: () {
                  Navigator.pop(context);
                  onCall('131');
                },
              ),
              _EmergencyTile(
                icon: Icons.local_fire_department_rounded,
                color: const Color(0xFFFF6D00),
                label: 'Bomberos',
                number: '132',
                description: 'Cuerpo de Bomberos',
                onTap: () {
                  Navigator.pop(context);
                  onCall('132');
                },
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: Colors.white38),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(fontFamily: 'Poppins'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmergencyTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String number;
  final String description;
  final VoidCallback onTap;

  const _EmergencyTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.number,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        description,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone_rounded, color: color, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        number,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Diálogo de cuenta regresiva tras detectar una caída ────────────────────

class _FallCountdownDialog extends StatefulWidget {
  final Future<void> Function(String number) onCall;
  const _FallCountdownDialog({required this.onCall});

  @override
  State<_FallCountdownDialog> createState() => _FallCountdownDialogState();
}

class _FallCountdownDialogState extends State<_FallCountdownDialog> {
  static const int _start = 15;
  int _remaining = _start;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        _callEmergency();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _callEmergency() async {
    if (mounted) Navigator.of(context).pop();
    await widget.onCall('133'); // Carabineros
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.red.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.3),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  child: CircularProgressIndicator(
                    value: _remaining / _start,
                    strokeWidth: 6,
                    backgroundColor: Colors.red.withOpacity(0.15),
                    valueColor: const AlwaysStoppedAnimation(Colors.red),
                  ),
                ),
                Text(
                  '$_remaining',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '¿Tuviste una caída?',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Llamaremos a Carabineros (133) automáticamente si no respondes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white60,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _timer?.cancel();
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Estoy bien'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  _timer?.cancel();
                  _callEmergency();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Llamar ahora'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';
import '../services/alerts_service.dart';
import '../core/glass.dart';

enum LocationMethod { current, pin }

class CreateAlertPage extends StatefulWidget {
  final Function(Map<String, dynamic>)? onAlertCreated;
  final double? initialLatitude;
  final double? initialLongitude;

  const CreateAlertPage({
    super.key,
    this.onAlertCreated,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<CreateAlertPage> createState() => _CreateAlertPageState();
}

class _CreateAlertPageState extends State<CreateAlertPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();

  String _selectedType = 'danger';
  bool _loading = false;
  bool _isGettingLocation = false;

  double? _latitude;
  double? _longitude;
  LocationMethod _locationMethod = LocationMethod.current;

  final AlertsService _alertsService = AlertsService();

  final Map<String, AlertTypeInfo> _alertTypes = {
    'danger': AlertTypeInfo(
      icon: Icons.warning,
      color: Colors.red,
      label: 'Peligro',
      description: 'Zona peligrosa',
    ),
    'theft': AlertTypeInfo(
      icon: Icons.no_accounts,
      color: Colors.purple,
      label: 'Robo',
      description: 'Robos recientes',
    ),
    'construction': AlertTypeInfo(
      icon: Icons.construction,
      color: Colors.orange,
      label: 'Obras',
      description: 'Obras en la vía',
    ),
    'accident': AlertTypeInfo(
      icon: Icons.car_crash,
      color: Colors.deepOrange,
      label: 'Accidente',
      description: 'Accidente reciente',
    ),
    'other': AlertTypeInfo(
      icon: Icons.info,
      color: Colors.blue,
      label: 'Otro',
      description: 'Otro tipo',
    ),
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _latitude = widget.initialLatitude;
      _longitude = widget.initialLongitude;
      _locationController.text = 'Ubicación seleccionada';
      _locationMethod = LocationMethod.current;
    } else if (widget.onAlertCreated != null) {
      _locationMethod = LocationMethod.pin;
    } else {
      _locationMethod = LocationMethod.current;
      _getCurrentLocation();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    final status = await Permission.location.status;
    if (status.isDenied) {
      final result = await Permission.location.request();
      if (!result.isGranted) {
        setState(() => _isGettingLocation = false);
        if (mounted) _showSnack('Se necesita permiso de ubicación', color: Colors.orange);
        return;
      }
    }
    try {
      final position = await geo.Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 10),
      );
      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _isGettingLocation = false;
        });
        _locationController.text = 'Ubicación actual';
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGettingLocation = false);
        _showSnack('Error obteniendo ubicación: $e', color: Colors.redAccent);
      }
    }
  }

  void _showSnack(String msg, {Color color = Colors.green}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _createAlert() async {
    if (!_formKey.currentState!.validate()) return;
    if (_locationMethod == LocationMethod.pin && widget.onAlertCreated != null) {
      widget.onAlertCreated!({
        'type': _selectedType,
        'title': _titleController.text,
        'description': _descriptionController.text,
        'locationName': _locationController.text.isNotEmpty
            ? _locationController.text
            : 'Ubicación pendiente',
      });
      Navigator.pop(context);
      return;
    }
    if (_latitude == null || _longitude == null) {
      _showSnack('No se pudo obtener tu ubicación. Activa el GPS y presiona 📍',
          color: Colors.orange);
      return;
    }
    setState(() => _loading = true);
    try {
      final alert = await _alertsService.createAlert(
        type: _selectedType,
        title: _titleController.text,
        description: _descriptionController.text,
        latitude: _latitude!,
        longitude: _longitude!,
        locationName: _locationController.text.isNotEmpty
            ? _locationController.text
            : null,
      );
      if (alert != null && mounted) {
        Navigator.pop(context);
        if (widget.onAlertCreated != null) widget.onAlertCreated!(alert);
        _showSnack('Alerta creada con éxito');
      } else if (mounted) {
        throw Exception('No se pudo crear la alerta');
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', color: Colors.redAccent);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor =
        _alertTypes[_selectedType]?.color ?? Colors.redAccent;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: kPageGradient,
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: glassDecoration(radius: 12),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Crear Alerta',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  children: [
                    // Tipo
                    _sectionLabel('TIPO DE ALERTA'),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 92,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: _alertTypes.entries.map((entry) {
                          final isSelected = _selectedType == entry.key;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedType = entry.key),
                            child: Container(
                              width: 88,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? entry.value.color.withOpacity(0.18)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? entry.value.color.withOpacity(0.7)
                                      : Colors.white.withOpacity(0.1),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    entry.value.icon,
                                    color: isSelected
                                        ? entry.value.color
                                        : Colors.white38,
                                    size: 26,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    entry.value.label,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      color: isSelected
                                          ? entry.value.color
                                          : Colors.white38,
                                      fontSize: 11,
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
                    ),
                    const SizedBox(height: 20),

                    // Detalles
                    _sectionLabel('DETALLES'),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: glassDecoration(radius: 18),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _titleController,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            decoration: glassInput(
                              'Título de la alerta',
                              _alertTypes[_selectedType]?.icon ?? Icons.warning,
                              accentColor: accentColor,
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Ingresa un título'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _descriptionController,
                            maxLines: 3,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            decoration:
                                glassInput('Descripción', Icons.description),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Describe la situación'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Ubicación
                    _sectionLabel('UBICACIÓN'),
                    const SizedBox(height: 10),
                    Container(
                      decoration: glassDecoration(radius: 18),
                      child: Column(
                        children: [
                          // Selector de método
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                            child: Row(
                              children: [
                                _methodChip(
                                  label: '📍 Ubicación actual',
                                  selected: _locationMethod ==
                                      LocationMethod.current,
                                  onTap: () {
                                    setState(() =>
                                        _locationMethod = LocationMethod.current);
                                    if (_latitude == null) _getCurrentLocation();
                                  },
                                ),
                                const SizedBox(width: 10),
                                _methodChip(
                                  label: '🗺️ Elegir en mapa',
                                  selected:
                                      _locationMethod == LocationMethod.pin,
                                  onTap: () => setState(
                                      () => _locationMethod = LocationMethod.pin),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_locationMethod == LocationMethod.current) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              child: TextFormField(
                                controller: _locationController,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                                decoration: glassInput(
                                  'Nombre del lugar (opcional)',
                                  Icons.location_on,
                                  suffix: _isGettingLocation
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.greenAccent,
                                            ),
                                          ),
                                        )
                                      : IconButton(
                                          icon: const Icon(
                                              Icons.my_location,
                                              color: Colors.greenAccent,
                                              size: 20),
                                          onPressed: _getCurrentLocation,
                                        ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                              child: _locationStatus(),
                            ),
                          ] else
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color:
                                          Colors.greenAccent.withOpacity(0.2)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.touch_app,
                                        color: Colors.greenAccent, size: 18),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Después de crear la alerta, toca el mapa para colocar el pin',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _createAlert,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Crear Alerta'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white24,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _methodChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Colors.greenAccent.withOpacity(0.15)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? Colors.greenAccent.withOpacity(0.4)
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: selected ? Colors.greenAccent : Colors.white38,
              fontSize: 12,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _locationStatus() {
    if (_latitude != null && _longitude != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.greenAccent, size: 15),
            SizedBox(width: 8),
            Text(
              'Ubicación obtenida correctamente',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.greenAccent,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 15),
          SizedBox(width: 8),
          Text(
            'Presiona 📍 para obtener tu ubicación',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.orange,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class AlertTypeInfo {
  final IconData icon;
  final Color color;
  final String label;
  final String description;

  AlertTypeInfo({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
  });
}

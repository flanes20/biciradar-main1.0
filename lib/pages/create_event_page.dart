import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/events_service.dart';
import '../core/glass.dart';

class CreateEventPage extends StatefulWidget {
  const CreateEventPage({super.key});

  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends State<CreateEventPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _maxParticipantsController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _loading = false;
  bool _isGettingLocation = false;

  double? _latitude;
  double? _longitude;

  final EventsService _eventsService = EventsService();

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _maxParticipantsController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    final status = await Permission.location.status;
    if (status.isDenied) {
      final result = await Permission.location.request();
      if (!result.isGranted) {
        setState(() => _isGettingLocation = false);
        _showSnack('Se necesita permiso de ubicación', color: Colors.orange);
        return;
      }
    }
    try {
      final position = await geo.Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 10),
      );
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _isGettingLocation = false;
      });
      if (_locationController.text.isEmpty) {
        _locationController.text = 'Mi ubicación actual';
      }
    } catch (e) {
      setState(() => _isGettingLocation = false);
      _showSnack('Error obteniendo ubicación: $e', color: Colors.redAccent);
    }
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.greenAccent,
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A2E),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (date != null) setState(() => _selectedDate = date);
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.greenAccent,
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A2E),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (time != null) setState(() => _selectedTime = time);
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

  Future<void> _createEvent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_latitude == null || _longitude == null) {
      _showSnack('No se pudo obtener tu ubicación. Activa el GPS y presiona 📍',
          color: Colors.orange);
      return;
    }
    setState(() => _loading = true);
    final eventDate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final maxParticipants = _maxParticipantsController.text.isNotEmpty
        ? int.tryParse(_maxParticipantsController.text)
        : null;
    try {
      final event = await _eventsService.createEvent(
        title: _titleController.text,
        description: _descriptionController.text,
        eventDate: eventDate,
        locationName: _locationController.text,
        latitude: _latitude!,
        longitude: _longitude!,
        maxParticipants: maxParticipants,
      );
      if (event != null && mounted) {
        Navigator.pop(context, event);
        _showSnack('¡Evento creado con éxito!');
      } else if (mounted) {
        throw Exception('No se pudo crear el evento');
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', color: Colors.redAccent);
    } finally {
      if (mounted) setState(() => _loading = false);
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
                      'Crear Evento',
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
                    _section('INFORMACIÓN DEL EVENTO', [
                      _glassField(
                        controller: _titleController,
                        decoration: glassInput('Título del evento', Icons.title),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Ingresa un título' : null,
                      ),
                      const SizedBox(height: 12),
                      _glassField(
                        controller: _descriptionController,
                        decoration:
                            glassInput('Descripción', Icons.description),
                        maxLines: 3,
                      ),
                    ]),
                    const SizedBox(height: 16),

                    _section('FECHA Y HORA', [
                      Row(
                        children: [
                          Expanded(
                            child: _dateTile(
                              label: 'Fecha',
                              value:
                                  '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                              icon: Icons.calendar_today,
                              onTap: _selectDate,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _dateTile(
                              label: 'Hora',
                              value:
                                  '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
                              icon: Icons.access_time,
                              onTap: _selectTime,
                            ),
                          ),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 16),

                    _section('UBICACIÓN', [
                      TextFormField(
                        controller: _locationController,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 15,
                        ),
                        decoration: glassInput(
                          'Lugar de encuentro',
                          Icons.location_on,
                          helper: 'Ej: Plaza de Armas, Parque Forestal…',
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
                                  icon: const Icon(Icons.my_location,
                                      color: Colors.greenAccent, size: 20),
                                  onPressed: _getCurrentLocation,
                                ),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Ingresa el lugar de encuentro'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _locationStatus(),
                    ]),
                    const SizedBox(height: 16),

                    _section('PARTICIPANTES', [
                      _glassField(
                        controller: _maxParticipantsController,
                        decoration: glassInput(
                          'Máximo de participantes (opcional)',
                          Icons.people,
                          helper: 'Deja en blanco para sin límite',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ]),
                    const SizedBox(height: 28),

                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _createEvent,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
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
                                    color: Colors.black, strokeWidth: 2),
                              )
                            : const Text('Crear Evento'),
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

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white24,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: glassDecoration(radius: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _glassField({
    required TextEditingController controller,
    required InputDecoration decoration,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(
        fontFamily: 'Poppins',
        color: Colors.white,
        fontSize: 15,
      ),
      decoration: decoration,
    );
  }

  Widget _dateTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: Colors.greenAccent.withOpacity(0.7), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
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

  Widget _locationStatus() {
    if (_latitude != null && _longitude != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle,
                color: Colors.greenAccent, size: 15),
            const SizedBox(width: 8),
            Text(
              'Ubicación: ${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
              style: const TextStyle(
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
          Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 15),
          SizedBox(width: 8),
          Text(
            'Presiona 📍 para usar tu ubicación actual',
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

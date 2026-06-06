import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/glass.dart';
import '../services/achievements_service.dart';
import '../services/karma_service.dart';
import '../services/co2_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _supabase = Supabase.instance.client;
  final _usernameCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _avatarUrlCtrl = TextEditingController();
  final _communeCtrl = TextEditingController();

  final _achievementsService = AchievementsService();
  final _karmaService = KarmaService();
  final ImagePicker _picker = ImagePicker();
  bool _uploadingAvatar = false;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _achievements = [];
  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  int _karma = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _fullNameCtrl.dispose();
    _avatarUrlCtrl.dispose();
    _communeCtrl.dispose();
    super.dispose();
  }

  User? get _user => _supabase.auth.currentUser;

  bool get _isGoogleUser {
    final identities = _user?.identities ?? [];
    return identities.any((id) => id.provider == 'google');
  }

  Future<void> _loadProfile() async {
    try {
      final userId = _user?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      // Chequear y desbloquear logros nuevos, luego cargar todos
      await _achievementsService.checkAndUnlock();
      final achievements = await _achievementsService.getAllWithStatus();
      final karma = await _karmaService.getMyKarma();

      if (mounted) {
        setState(() {
          _profile = data;
          _achievements = achievements;
          _karma = karma;
          _usernameCtrl.text = data?['username'] ?? '';
          _fullNameCtrl.text = data?['full_name'] ?? '';
          _avatarUrlCtrl.text = data?['avatar_url'] ?? '';
          _communeCtrl.text = data?['commune'] ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnack('Error cargando perfil: $e', isError: true);
      }
    }
  }

  /// Abre la galería, sube la imagen elegida y la fija como foto de perfil.
  Future<void> _pickAndUploadAvatar() async {
    final userId = _user?.id;
    if (userId == null || _uploadingAvatar) return;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        imageQuality: 80,
      );
      if (picked == null) return;
      setState(() => _uploadingAvatar = true);

      final file = File(picked.path);
      final path = 'avatars/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _supabase.storage.from('alert-photos').upload(path, file);
      final url = _supabase.storage.from('alert-photos').getPublicUrl(path);

      await _supabase.from('profiles').upsert({'id': userId, 'avatar_url': url});
      await _loadProfile();
      if (mounted) _showSnack('Foto de perfil actualizada');
    } catch (e) {
      if (mounted) _showSnack('No se pudo subir la foto: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _saveProfile() async {
    final userId = _user?.id;
    if (userId == null) return;
    setState(() => _saving = true);
    try {
      await _supabase.from('profiles').upsert({
        'id': userId,
        'username': _usernameCtrl.text.trim(),
        'full_name': _fullNameCtrl.text.trim(),
        'avatar_url': _avatarUrlCtrl.text.trim().isEmpty
            ? null
            : _avatarUrlCtrl.text.trim(),
        'commune': _communeCtrl.text.trim().isEmpty
            ? null
            : _communeCtrl.text.trim(),
      });
      await _loadProfile();
      if (mounted) {
        setState(() => _editing = false);
        _showSnack('Perfil actualizado');
      }
    } catch (e) {
      if (mounted) _showSnack('Error guardando: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _memberSince() {
    final raw = _profile?['created_at'] as String?;
    if (raw == null) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '—';
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _initials() {
    final full = (_profile?['full_name'] as String? ?? '').trim();
    final user = (_profile?['username'] as String? ?? '').trim();
    final name = full.isNotEmpty ? full : user;
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
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
            // AppBar glass
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      'Mi Perfil',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    const Spacer(),
                    if (!_loading && !_editing)
                      GestureDetector(
                        onTap: () => setState(() => _editing = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: glassDecoration(
                            radius: 12,
                            tint: Colors.greenAccent,
                            opacity: 0.1,
                            borderOpacity: 0.2,
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                color: Colors.greenAccent,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Editar',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.greenAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_editing)
                      TextButton(
                        onPressed: () => setState(() {
                          _editing = false;
                          _usernameCtrl.text = _profile?['username'] ?? '';
                          _fullNameCtrl.text = _profile?['full_name'] ?? '';
                          _avatarUrlCtrl.text = _profile?['avatar_url'] ?? '';
                          _communeCtrl.text = _profile?['commune'] ?? '';
                        }),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white38,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.greenAccent,
                        strokeWidth: 2,
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 600;
                        return SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: isWide
                                ? constraints.maxWidth * 0.15
                                : 20,
                            vertical: 24,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildAvatar(),
                              const SizedBox(height: 16),
                              _buildNameAndBadge(),
                              const SizedBox(height: 8),
                              _buildEmail(),
                              const SizedBox(height: 16),
                              _buildKarmaCard(),
                              const SizedBox(height: 12),
                              _buildCo2Card(),
                              const SizedBox(height: 24),
                              if (_editing)
                                _buildEditForm()
                              else
                                _buildProfileInfo(),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final avatarUrl = _profile?['avatar_url'] as String?;
    return GestureDetector(
      onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.greenAccent.withOpacity(0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.greenAccent.withOpacity(0.15),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipOval(
              child: _uploadingAvatar
                  ? Container(
                      color: Colors.black54,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Colors.greenAccent,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : (avatarUrl != null && avatarUrl.isNotEmpty
                      ? Image.network(
                          avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _avatarFallback(),
                        )
                      : _avatarFallback()),
            ),
          ),
          // Badge de cámara para indicar que se puede cambiar la foto
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.greenAccent,
              shape: BoxShape.circle,
              border: Border.all(color: kBgDark, width: 2),
            ),
            child: const Icon(Icons.photo_camera_rounded,
                color: Colors.black, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
      color: Colors.greenAccent.withOpacity(0.1),
      child: Center(
        child: Text(
          _initials(),
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.greenAccent,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildNameAndBadge() {
    final displayName = (_profile?['full_name'] as String? ?? '').trim();
    final username = (_profile?['username'] as String? ?? '').trim();
    return Column(
      children: [
        if (displayName.isNotEmpty)
          Text(
            displayName,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        if (username.isNotEmpty)
          Text(
            '@$username',
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white38,
              fontSize: 15,
            ),
          ),
        if (_isGoogleUser) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.blue.withOpacity(0.25)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GoogleIcon(size: 14),
                SizedBox(width: 7),
                Text(
                  'Inició sesión con Google',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.lightBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmail() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.email_outlined, color: Colors.white24, size: 15),
        const SizedBox(width: 6),
        Text(
          _user?.email ?? '—',
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white38,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildKarmaCard() {
    final level = KarmaService.getLevel(_karma);
    final progress = KarmaService.getLevelProgress(_karma);
    final levelColor = Color(level.colorValue);

    // Próximo nivel
    final levelIndex = KarmaService.levels.indexOf(level);
    final isMax = levelIndex >= KarmaService.levels.length - 1;
    final nextLevel =
        isMax ? null : KarmaService.levels[levelIndex + 1];

    return Container(
      decoration: glassDecoration(
        radius: 20,
        tint: levelColor,
        opacity: 0.07,
        borderOpacity: 0.18,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              // Emoji nivel
              Text(level.emoji,
                  style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          level.title,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: levelColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: levelColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: levelColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            '$_karma karma',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: levelColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white10,
                        valueColor:
                            AlwaysStoppedAnimation(levelColor),
                        minHeight: 5,
                      ),
                    ),
                    if (!isMax && nextLevel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Próximo: ${nextLevel.emoji} ${nextLevel.title} (${nextLevel.minKarma} pts)',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Nivel máximo alcanzado',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline,
                  color: Colors.white24, size: 14),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'El karma sube con votos positivos en tus reportes y baja con votos negativos.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white24,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCo2Card() {
    final totalKm = (_profile?['total_km'] as num?)?.toDouble() ?? 0.0;
    final co2Kg   = Co2Service.savedKg(totalKm);
    final co2Str  = Co2Service.format(co2Kg);
    final treeStr = Co2Service.treeEquivalent(co2Kg);

    return Container(
      decoration: glassDecoration(
        radius: 20,
        tint: Colors.lightGreenAccent,
        opacity: 0.05,
        borderOpacity: 0.14,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          const Text('🌱', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Impacto ecológico',
                    style: TextStyle(fontFamily: 'Poppins', color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${totalKm.toStringAsFixed(1)} km',
                      style: const TextStyle(fontFamily: 'Poppins', color: Colors.lightGreenAccent, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.lightGreenAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.lightGreenAccent.withOpacity(0.25)),
                      ),
                      child: Text(
                        '$co2Str CO₂',
                        style: const TextStyle(fontFamily: 'Poppins', color: Colors.lightGreenAccent, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (treeStr.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(treeStr, style: const TextStyle(fontFamily: 'Poppins', color: Colors.white38, fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('INFORMACIÓN'),
        const SizedBox(height: 10),
        Container(
          decoration: glassDecoration(radius: 18),
          child: Column(children: [
            _infoRow(Icons.person_outline, 'Usuario',
                _profile?['username'] ?? '—'),
            _divider(),
            _infoRow(Icons.badge_outlined, 'Nombre completo',
                _profile?['full_name'] ?? '—'),
            _divider(),
            _infoRow(
              Icons.location_city_outlined,
              'Comuna',
              (_profile?['commune'] as String? ?? '').isNotEmpty
                  ? _profile!['commune']
                  : '—',
              valueColor: (_profile?['commune'] as String? ?? '').isNotEmpty
                  ? Colors.amberAccent
                  : null,
            ),
            _divider(),
            _infoRow(
              Icons.calendar_today_outlined,
              'Miembro desde',
              _memberSince(),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        _sectionLabel('CUENTA'),
        const SizedBox(height: 10),
        Container(
          decoration: glassDecoration(radius: 18),
          child: Column(children: [
            _infoRow(Icons.email_outlined, 'Correo', _user?.email ?? '—'),
            _divider(),
            _infoRow(
              Icons.login_outlined,
              'Proveedor',
              _isGoogleUser ? 'Google' : 'Email / contraseña',
              valueColor: _isGoogleUser ? Colors.lightBlue : null,
            ),
            _divider(),
            _infoRow(
              Icons.verified_user_outlined,
              'Estado',
              _user?.emailConfirmedAt != null ? 'Verificado' : 'Sin verificar',
              valueColor: _user?.emailConfirmedAt != null
                  ? Colors.greenAccent
                  : Colors.orange,
            ),
          ]),
        ),
        if (_achievements.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildAchievements(),
        ],
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: () async {
            await _supabase.auth.signOut();
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(
                  context, '/', (route) => false);
            }
          },
          icon: const Icon(Icons.logout, size: 17),
          label: const Text(
            'Cerrar sesión',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.redAccent,
            side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
            backgroundColor: Colors.redAccent.withOpacity(0.06),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('EDITAR PERFIL'),
        const SizedBox(height: 16),
        TextField(
          controller: _usernameCtrl,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 15,
          ),
          decoration: glassInput('Nombre de usuario', Icons.person_outline),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _fullNameCtrl,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 15,
          ),
          decoration: glassInput('Nombre completo', Icons.badge_outlined),
        ),
        const SizedBox(height: 14),
        const Text(
          'Para cambiar tu foto, toca tu avatar arriba y elígela de la galería.',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white38,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _communeCtrl,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 15,
          ),
          decoration: glassInput(
            'Mi comuna (opcional)',
            Icons.location_city_outlined,
            helper: 'Ej: Providencia, Ñuñoa, Las Condes...',
            accentColor: Colors.amberAccent,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _saving ? null : _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        color: Colors.black, strokeWidth: 2),
                  )
                : const Text('Guardar cambios'),
          ),
        ),
      ],
    );
  }

  Widget _buildAchievements() {
    final unlocked = _achievements.where((a) => a['unlocked'] == true).toList();
    final locked = _achievements.where((a) => a['unlocked'] != true).toList();
    final unlockedCount = unlocked.length;
    final total = _achievements.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _sectionLabel('LOGROS'),
            const Spacer(),
            Text(
              '$unlockedCount / $total',
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Barra de progreso
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total > 0 ? unlockedCount / total : 0,
            backgroundColor: Colors.white10,
            valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 16),
        if (unlocked.isNotEmpty) ...[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: unlocked.map((a) => _badgeTile(a, true)).toList(),
          ),
          const SizedBox(height: 14),
        ],
        if (locked.isNotEmpty)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: locked.map((a) => _badgeTile(a, false)).toList(),
          ),
      ],
    );
  }

  Widget _badgeTile(Map<String, dynamic> achievement, bool unlocked) {
    final icon = achievement['icon'] as String? ?? '🏅';
    final title = achievement['title'] as String? ?? '';

    return GestureDetector(
      onTap: () => _showAchievementDetail(achievement, unlocked),
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: glassDecoration(
          radius: 16,
          tint: unlocked ? Colors.greenAccent : Colors.white,
          opacity: unlocked ? 0.08 : 0.03,
          borderOpacity: unlocked ? 0.2 : 0.07,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorFiltered(
              colorFilter: unlocked
                  ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                  : const ColorFilter.matrix([
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0,      0,      0,      0.3, 0,
                    ]),
              child: Text(icon, style: const TextStyle(fontSize: 28)),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: unlocked ? Colors.white : Colors.white24,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showAchievementDetail(Map<String, dynamic> achievement, bool unlocked) {
    final icon = achievement['icon'] as String? ?? '🏅';
    final title = achievement['title'] as String? ?? '';
    final description = achievement['description'] as String? ?? '';
    final unlockedAt = achievement['unlocked_at'] as String?;

    String dateStr = '';
    if (unlockedAt != null) {
      final dt = DateTime.tryParse(unlockedAt)?.toLocal();
      if (dt != null) {
        const months = [
          'ene', 'feb', 'mar', 'abr', 'may', 'jun',
          'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
        ];
        dateStr = '${dt.day} ${months[dt.month - 1]} ${dt.year}';
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: glassDecoration(
          radius: 24,
          tint: unlocked ? Colors.greenAccent : Colors.white,
          opacity: unlocked ? 0.1 : 0.05,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: unlocked ? Colors.white : Colors.white38,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white60,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            if (unlocked && dateStr.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
                ),
                child: Text(
                  'Desbloqueado el $dateStr',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.greenAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            if (!unlocked) ...[
              const SizedBox(height: 16),
              const Text(
                'Aún no desbloqueado',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white24,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 8),
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

  Widget _infoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: Colors.greenAccent.withOpacity(0.7), size: 17),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white38,
                fontSize: 13,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: valueColor ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        color: Colors.white.withOpacity(0.06),
        indent: 46,
        endIndent: 16,
      );
}

class _GoogleIcon extends StatelessWidget {
  final double size;
  const _GoogleIcon({this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    const sweepAngle = 2 * 3.14159265 / 4;
    final colors = [Colors.blue, Colors.red, Colors.yellow, Colors.green];
    for (int i = 0; i < 4; i++) {
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.28
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.62),
        -3.14159265 / 2 + sweepAngle * i,
        sweepAngle * 0.97,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

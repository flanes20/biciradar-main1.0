import 'package:biciradar/pages/map_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/glass.dart';

// Mismo color que el resto de la app
const _kGreen = Colors.greenAccent; // Color(0xFF69FF47)
const _kGreenDark = Color(0xFF00C853);

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  bool _obscure = true;

  late final AnimationController _logoCtrl;
  late final Animation<double> _logoGlow;

  SupabaseClient get supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _logoGlow = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeInOut),
    );

    supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      final event = data.event;
      if (event == AuthChangeEvent.signedIn && session != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MapPage()),
        );
      }
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      if (_isLogin) {
        await supabase.auth.signInWithPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );
      } else {
        final response = await supabase.auth.signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
          data: {'username': _usernameCtrl.text.trim()},
        );
        if (mounted) {
          final user = response.user;
          final session = response.session;
          if (user != null && session == null) {
            _showVerificationDialog();
          } else {
            _showSnack('¡Cuenta creada con éxito!', color: Colors.green);
          }
        }
      }
      if (!mounted) return;
      if (supabase.auth.currentSession != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MapPage()),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      _showSnack(e.message, color: Colors.redAccent);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error: $e', color: Colors.redAccent);
    } finally {
      if (mounted) setState(() => _loading = false);
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

  void _showVerificationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassBox(
          blur: 20,
          opacity: 0.15,
          radius: 24,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kGreen.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.mark_email_unread_outlined,
                        color: _kGreen, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Verifica tu correo',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Hemos enviado un enlace de verificación a:',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white60),
              ),
              const SizedBox(height: 8),
              Text(
                _emailCtrl.text.trim(),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: _kGreen,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Revisá tu bandeja de entrada y spam.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white38,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _isLogin = true;
                      _emailCtrl.clear();
                      _passwordCtrl.clear();
                      _usernameCtrl.clear();
                    });
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: _kGreen.withOpacity(0.15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Entendido',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: _kGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'com.biciradar.app://login-callback/',
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      _showSnack(e.message, color: Colors.redAccent);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error con Google: $e', color: Colors.redAccent);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (supabase.auth.currentSession != null) {
      return const MapPage();
    }

    return Scaffold(
      body: Stack(
        children: [
          // ── Fondo degradado ──────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF06060F), Color(0xFF080F0A), Color(0xFF060C06)],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // ── Orbe superior (verde) ────────────────────────────────
          Positioned(
            top: -120,
            right: -80,
            child: AnimatedBuilder(
              animation: _logoGlow,
              builder: (_, _) => Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _kGreen.withOpacity(_logoGlow.value * 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Orbe inferior (verde oscuro) ─────────────────────────
          Positioned(
            bottom: -100,
            left: -60,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _kGreenDark.withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Orbe lateral tenue ───────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).size.height * 0.35,
            left: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _kGreen.withOpacity(0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Contenido principal ──────────────────────────────────
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 36),
                    _buildCard(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Logo con glow pulsante verde
        AnimatedBuilder(
          animation: _logoGlow,
          builder: (_, _) => Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0A1A0A),
              border: Border.all(
                color: _kGreen.withOpacity(0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _kGreen.withOpacity(_logoGlow.value * 0.5),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: _kGreen.withOpacity(0.15),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: const Icon(
              Icons.directions_bike_rounded,
              color: _kGreen,
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'BiciRadar',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _isLogin
                ? 'Bienvenido de vuelta'
                : 'Únete a la comunidad ciclista',
            key: ValueKey(_isLogin),
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.45),
              fontSize: 15,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard() {
    return GlassBox(
      blur: 28,
      opacity: 0.08,
      borderOpacity: 0.12,
      radius: 28,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Franja de acento superior verde
          Container(
            height: 3,
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  _kGreen.withOpacity(0.8),
                  _kGreenDark.withOpacity(0.5),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildToggleTabs(),
                const SizedBox(height: 28),

                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Column(
                    children: [
                      if (!_isLogin) ...[
                        _buildTextField(
                          controller: _usernameCtrl,
                          label: 'Nombre de usuario',
                          icon: Icons.person_outline_rounded,
                        ),
                        const SizedBox(height: 14),
                      ],
                      _buildTextField(
                        controller: _emailCtrl,
                        label: 'Correo electrónico',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: _passwordCtrl,
                        label: 'Contraseña',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscure,
                        suffix: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Colors.white38,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_isLogin) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _loading ? null : _showForgotPassword,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        '¿Olvidaste tu contraseña?',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: _kGreen,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                _buildMainButton(),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                        child: Divider(color: Colors.white.withOpacity(0.1))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'o continúa con',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                        child: Divider(color: Colors.white.withOpacity(0.1))),
                  ],
                ),
                const SizedBox(height: 20),

                _buildGoogleButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleTabs() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          _buildTab('Iniciar sesión', isActive: _isLogin, onTap: () {
            if (!_isLogin) setState(() => _isLogin = true);
          }),
          _buildTab('Registrarse', isActive: !_isLogin, onTap: () {
            if (_isLogin) setState(() => _isLogin = false);
          }),
        ],
      ),
    );
  }

  Widget _buildTab(String label,
      {required bool isActive, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: _loading ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: isActive ? _kGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: _kGreen.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              // greenAccent es claro → texto negro cuando activo
              color: isActive ? Colors.black : Colors.white38,
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: const TextStyle(
        fontFamily: 'Poppins',
        color: Colors.white,
        fontSize: 15,
      ),
      decoration: glassInput(
        label,
        icon,
        suffix: suffix,
        accentColor: _kGreen,
      ),
    );
  }

  Widget _buildMainButton() {
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: _loading
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF69FF47), Color(0xFF00C853)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          boxShadow: _loading
              ? null
              : [
                  BoxShadow(
                    color: _kGreen.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  )
                ],
        ),
        child: ElevatedButton(
          onPressed: _loading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.black,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            disabledBackgroundColor: Colors.white.withOpacity(0.07),
            textStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: _loading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_isLogin ? 'Iniciar sesión' : 'Crear cuenta'),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: _loading ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withOpacity(0.12)),
          backgroundColor: Colors.white.withOpacity(0.04),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                children: [
                  TextSpan(
                      text: 'G',
                      style: TextStyle(color: Color(0xFF4285F4))),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Continuar con Google',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showForgotPassword() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassBox(
          blur: 24,
          opacity: 0.12,
          radius: 24,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recuperar contraseña',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Te enviaremos un enlace para restablecer tu contraseña.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 15,
                ),
                decoration: glassInput(
                  'Correo electrónico',
                  Icons.email_outlined,
                  accentColor: _kGreen,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.white38),
                      child: const Text('Cancelar',
                          style: TextStyle(fontFamily: 'Poppins')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (ctrl.text.trim().isEmpty) return;
                        Navigator.pop(ctx);
                        try {
                          await supabase.auth.resetPasswordForEmail(
                            ctrl.text.trim(),
                          );
                          if (mounted) {
                            _showSnack(
                              'Enlace enviado a ${ctrl.text.trim()}',
                              color: Colors.green,
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            _showSnack('Error: $e',
                                color: Colors.redAccent);
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Enviar'),
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
}

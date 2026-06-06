import 'dart:ui';
import 'package:flutter/material.dart';

// ─── Colores base del tema ──────────────────────────────────────────────────

const kBgDark = Color(0xFF08080F);
const kBgCard = Color(0xFF0F0F1A);

// ─── Decoraciones ──────────────────────────────────────────────────────────

/// Glass sin blur (para fondos sólidos oscuros)
BoxDecoration glassDecoration({
  double opacity = 0.07,
  double borderOpacity = 0.14,
  double radius = 20,
  Color? tint,
}) {
  return BoxDecoration(
    color: (tint ?? Colors.white).withOpacity(opacity),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: Colors.white.withOpacity(borderOpacity),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.3),
        blurRadius: 20,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

/// Glass con BackdropFilter (para superponer sobre el mapa u otra imagen)
class GlassBox extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final double borderOpacity;
  final double radius;
  final Color? tint;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  const GlassBox({
    super.key,
    required this.child,
    this.blur = 28,
    this.opacity = 0.14,
    this.borderOpacity = 0.22,
    this.radius = 20,
    this.tint,
    this.padding,
    this.margin,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: (tint ?? Colors.white).withOpacity(opacity),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Colors.white.withOpacity(borderOpacity),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Gradiente de fondo para páginas (no mapa)
const kPageGradient = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF08080F), Color(0xFF0D0D18), Color(0xFF0A0A14)],
    stops: [0.0, 0.5, 1.0],
  ),
);

/// InputDecoration con estilo glass
InputDecoration glassInput(
  String label,
  IconData icon, {
  Widget? suffix,
  String? helper,
  Color? accentColor,
}) {
  final accent = accentColor ?? Colors.greenAccent;
  return InputDecoration(
    labelText: label,
    helperText: helper,
    labelStyle: TextStyle(
      fontFamily: 'Poppins',
      color: Colors.white38,
      fontSize: 14,
      fontWeight: FontWeight.w300,
    ),
    helperStyle: const TextStyle(
      fontFamily: 'Poppins',
      color: Colors.white24,
      fontSize: 12,
    ),
    prefixIcon: Icon(icon, color: accent.withOpacity(0.7), size: 20),
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.white.withOpacity(0.06),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: accent.withOpacity(0.6), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
  );
}

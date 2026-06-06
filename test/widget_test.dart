// Smoke test de un widget liviano de la app (no requiere Supabase ni red).
//
// El test por defecto de la plantilla (contador) fue reemplazado porque la app
// no tiene contador. Aquí validamos que el GlassBox del sistema de diseño
// renderiza a su hijo sin lanzar excepciones.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biciradar/core/glass.dart';

void main() {
  testWidgets('GlassBox renderiza su contenido hijo', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassBox(
            child: Text('BiciRadar'),
          ),
        ),
      ),
    );

    expect(find.text('BiciRadar'), findsOneWidget);
    expect(find.byType(GlassBox), findsOneWidget);
  });
}

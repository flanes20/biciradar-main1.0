/// Utilidades para calcular CO2 ahorrado al ir en bici.
/// Auto promedio Chile: ~130 g CO2/km
class Co2Service {
  static const double _gramsPerKm = 130.0;

  /// CO2 ahorrado en kg dado los km recorridos en bici.
  static double savedKg(double km) => km * _gramsPerKm / 1000;

  /// Formato legible: "250 g" / "1.3 kg" / "2.1 t"
  static String format(double kg) {
    if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)} t';
    if (kg >= 1)    return '${kg.toStringAsFixed(2)} kg';
    return '${(kg * 1000).toStringAsFixed(0)} g';
  }

  /// Un árbol absorbe ≈22 kg CO2/año.
  static String treeEquivalent(double kg) {
    if (kg <= 0) return '';
    final trees = kg / 22;
    if (trees < 0.05) return '';
    if (trees < 1) return '≈ ${(trees * 100).toStringAsFixed(0)}% de un árbol/año';
    return '≈ ${trees.toStringAsFixed(1)} árbol${trees >= 2 ? "es" : ""}/año';
  }
}

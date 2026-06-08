// Reemplaza con tu token de Mapbox (https://account.mapbox.com)
const kMapboxToken = '';

// Estilos SIN capa de tráfico (los "navigation-*" pintaban las calles de
// autos en verde/naranjo/rojo y se confundían con las ciclovías).
const kMapStyleNight = 'mapbox://styles/mapbox/dark-v11';
const kMapStyleDay   = 'mapbox://styles/mapbox/streets-v12';

/// Devuelve el estilo de mapa según la hora local.
String autoDarkMapStyle() {
  final hour = DateTime.now().hour;
  return (hour >= 7 && hour < 19) ? kMapStyleDay : kMapStyleNight;
}

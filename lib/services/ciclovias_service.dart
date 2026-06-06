import 'package:http/http.dart' as http;

class CicloviasService {
  static Future<String> obtenerCicloviasChile() async {
    final query = """
[out:json][timeout:180];

// Área de Chile
area["name"="Chile"]["boundary"="administrative"]["admin_level"="2"]->.searchArea;

(
  // Ciclovías separadas
  way["highway"="cycleway"](area.searchArea);

  // Infraestructura ciclista asociada a calles
  way["cycleway"](area.searchArea);
  way["cycleway:left"](area.searchArea);
  way["cycleway:right"](area.searchArea);
  way["cycleway:both"](area.searchArea);

  // Casos donde la bici está explícitamente designada
  way["bicycle"="designated"](area.searchArea);

  // Algunas ciclorutas / sendas compartidas útiles
  way["cyclestreet"](area.searchArea);
  way["cycleway"="track"](area.searchArea);
  way["cycleway"="lane"](area.searchArea);
  way["cycleway"="opposite_lane"](area.searchArea);
  way["cycleway"="opposite_track"](area.searchArea);
  way["cycleway"="shared_lane"](area.searchArea);
  way["cycleway"="share_busway"](area.searchArea);

  // Opcional: relaciones de rutas ciclistas
  relation["type"="route"]["route"="bicycle"](area.searchArea);
);

out geom;
    """;

    final url = Uri.parse("https://overpass-api.de/api/interpreter");
    final response = await http.post(url, body: query);

    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception("Error al obtener ciclovías de Chile");
    }
  }
}

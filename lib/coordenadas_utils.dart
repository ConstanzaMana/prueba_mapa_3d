import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // Para el debugPrint

class CoordenadasUtils {

  //Lee el JSON y devuelve la lista completa de destinos
  static Future<List<Map<String, String>>> cargarYProcesarDestinos() async {
    try {
      // Lee el archivo local JSON de la carpeta assets
      String jsonString = await rootBundle.loadString('assets/destinos.json');
      // Decodifica la estructura JSON hacia una lista de objetos dinámicos
      List<dynamic> datosJson = jsonDecode(jsonString);
      // Inicializa la estructura de datos que almacenará los destinos procesados.
      List<Map<String, String>> destinosGenerados = [];

      // Establece el estado inicial de visualización (Vista General del mapa).
      destinosGenerados.add({
        "id": "VISTA_GENERAL",
        "nombre": "Vista General",
        "target": "0m 0m 0m",
        "orbit": "90deg 15deg 150m",
        "hotspot": "",
        "x": "0",
        "y": "0"
      });

      // Recorre cada aula en destinos.json
      for (var item in datosJson) {
        String id = item['idDestino'];
        String nombre = item['nombreDestino'];
        double jX = item['geometria']['coordinates'][0];
        double jY = item['geometria']['coordinates'][1];

        // Formula para convertir coordenadas a las del plano
        var coordsCalculadas = traducirCoordenadasJsonAMapa(jX, jY);

        // Guarda el resultado ya formateado para el mapa 3D
        destinosGenerados.add({
          "id": id,
          "nombre": nombre.trim(),
          "target": coordsCalculadas["cameraTarget"]!,
          "orbit": "0deg 60deg 15m",
          "hotspot": coordsCalculadas["hotspotPos"]!,
          "x": jX.toString(),
          "y": jY.toString()
        });
      }

      return destinosGenerados;

    } catch (e) {
      debugPrint("Error al cargar el JSON local: $e");
      return []; // Devuelve una lista vacía si hay error para que no crashee la App
    }
  }

  //  Fórmula matemática para escalar y alinear los planos (JSON vs SketchUp)
  static Map<String, String> traducirCoordenadasJsonAMapa(double jsonX, double jsonY) {
    // Constantes empíricas de calibración (factor de escala y offset)
    // definidas para sincronizar el mapa base con el entorno tridimensional.
    const double factorX = 0.9941;
    const double offsetX = -2851.85;
    const double factorY = 0.9805;
    const double offsetY = -506.9;

    // Ejecuta la transformación lineal para el eje X.
    double mapaX = (jsonX * factorX) + offsetX;
    // Ejecuta la transformación lineal para el eje Y.
    double mapaY = (jsonY * factorY) + offsetY;

    // Limita la precisión de los valores resultantes a dos decimales
    String xStr = mapaX.toStringAsFixed(2);

    // Invierte el eje Y matemático para mapearlo a la profundidad (eje Z) del motor 3D.
    String zStr = (-mapaY).toStringAsFixed(2);

    // Estructura los vectores de posición finales en metros ('m') para la cámara y el marcador.
    return {
      "cameraTarget": "${xStr}m 2m ${zStr}m", // Enfoque de la cámara (altura de 2 metros)
      "hotspotPos": "${xStr}m 0.02m ${zStr}m", // Elevación del marcador a nivel del suelo
    };
  }
}
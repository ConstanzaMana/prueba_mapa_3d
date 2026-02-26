import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
//Clase para obtener datos del servidor, si no se puede conectar con el servidor usa archivo JSON guardado

class redUtils {
  static const String baseUrl = 'https://mi-tesis-inmap.loca.lt';

  static const Map<String, String> headersTesis = {
    "Bypass-Tunnel-Reminder": "true",
    "Content-Type": "application/json",
  };

  // Obtener Zonas  del servidor
  static Future<List<dynamic>> obtenerZonasBloqueadas() async {
    try {
      final respuesta = await http
          .get(Uri.parse('$baseUrl/obtenerZonas'), headers: headersTesis)
          .timeout(const Duration(seconds: 5));

      if (respuesta.statusCode == 200) {
        List<dynamic> zonas = jsonDecode(respuesta.body);
        debugPrint("Capa de datos: Recibidas ${zonas.length} zonas desde el servidor.");
        return zonas;
      }
      throw Exception("Fallo en respuesta de servidor");
    } catch (e) {
      debugPrint("Estado: Servidor no disponible. Cargando respaldo local de zonas. Motivo: $e");
      String jsonString = await rootBundle.loadString('assets/obtenerZonas.json');
      return jsonDecode(jsonString);
    }
  }

  // Obtener Personal del servidor
  static Future<List<dynamic>> obtenerListaPersonal() async {
    try {
      final respuesta = await http
          .get(Uri.parse('$baseUrl/personal'), headers: headersTesis)
          .timeout(const Duration(seconds: 5));

      if (respuesta.statusCode == 200) return jsonDecode(respuesta.body);
      throw Exception("Error");
    } catch (e) {
      debugPrint("Falló conexión. Cargando personal.json local...");
      try {
        String jsonString = await rootBundle.loadString('assets/personal.json');
        return jsonDecode(jsonString);
      } catch (err) {
        debugPrint("Error: No existe el archivo assets/personal.json");
        return [];
      }
    }
  }
  // Obtener Lista de Materias del servidor
  static Future<List<dynamic>> obtenerListaMaterias() async {
    try {
      final respuesta = await http
          .get(Uri.parse('$baseUrl/materias'), headers: headersTesis)
          .timeout(const Duration(seconds: 5));

      if (respuesta.statusCode == 200) return jsonDecode(respuesta.body);
      throw Exception("Error");
    } catch (e) {
      debugPrint("Falló conexión. Cargando materias.json local...");
      try {
        // CORRECCIÓN DE RUTA
        String jsonString = await rootBundle.loadString('assets/materias.json');
        return jsonDecode(jsonString);
      } catch (err) {
        debugPrint("Error: No existe el archivo assets/materias.json");
        return [];
      }
    }
  }
  //  Obtener ubicacion de un personal del servidor
  static Future<String?> buscarUbicacionPersonal(String idPersonal, String hora, String dia) async {
    try {
      final url = Uri.parse('$baseUrl/personal/$idPersonal/$hora/$dia');
      final respuesta = await http.get(url, headers: headersTesis).timeout(const Duration(seconds: 5));

      if (respuesta.statusCode == 200) {
        final List<dynamic> data = jsonDecode(respuesta.body);
        if (data.isNotEmpty) {
          // Navegación: Lista[0] -> Mapa 'destino' -> Campo 'idDestino'
          var primerResultado = data[0];
          return primerResultado['destino']['idDestino'].toString();
        }
      }
    } catch (e) {
      debugPrint("🚨 Error en Personal: $e");
    }
    return null;
  }

  // Obtener Ubicacion de un Materia en un horario y fecha del servidor
  static Future<String?> buscarUbicacionMateria(String codMateria, String hora, String dia) async {
    try {
      final url = Uri.parse('$baseUrl/materia/$codMateria/$hora/$dia');
      final respuesta = await http.get(url, headers: headersTesis).timeout(const Duration(seconds: 5));

      if (respuesta.statusCode == 200) {
        final List<dynamic> data = jsonDecode(respuesta.body);
        if (data.isNotEmpty) {
          // El log mostró que Materia también devuelve una LISTA []
          var primerResultado = data[0];
          return primerResultado['destino']['idDestino'].toString();
        }
      }
    } catch (e) {
      debugPrint("🚨 Error en Materia: $e");
    }
    return null;
  }
}
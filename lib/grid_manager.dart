import 'dart:math';
import 'dart:math';
import 'package:flutter/foundation.dart'; // Para debugPrint
//Clase para acelerar proceso de direccionamiento
class GridManager {
  late double minX, maxX, minY, maxY;
  late double cellSize; // Tamaño de cada celda
  late int cols, rows;
  List<List<bool>>? _grid;

  GridManager({required this.cellSize});

  void inicializarDesdeZonas(List<dynamic> zonas) {
    if (zonas.isEmpty) return;

    //límites del mapa
    minX = double.infinity; maxX = double.negativeInfinity;
    minY = double.infinity; maxY = double.negativeInfinity;

    for (var zona in zonas) {
      //  zonas caminables para definir el tamaño del mapa
      if (zona['bloqueado'] == false) {
        var coords = zona['geometria']['coordinates'][0][0];
        for (var punto in coords) {
          double x = punto[0].toDouble();
          double y = punto[1].toDouble();
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    // Margen de seguridad
    minX -= 2; maxX += 2; minY -= 2; maxY += 2;

    cols = ((maxX - minX) / cellSize).ceil();
    rows = ((maxY - minY) / cellSize).ceil();

    debugPrint("Mapa Grid: $cols x $rows. Límites: X($minX, $maxX) Y($minY, $maxY)");

    _grid = List.generate(cols, (_) => List.filled(rows, false));

    // Se pinta de verde (true) solo donde hay pasillos o aulas
    _quemarPasillosEnGrilla(zonas);
  }

  void _quemarPasillosEnGrilla(List<dynamic> zonas) {
    int contadorCeldasCaminables = 0;

    for (var zona in zonas) {
      // Solo se procesa lo que NO está bloqueado (Pasillos y Aulas)
      if (zona['bloqueado'] == false) {
        var polygon = zona['geometria']['coordinates'][0][0];

        // Bounding box local para optimizar
        double zMinX = double.infinity, zMaxX = double.negativeInfinity;
        double zMinY = double.infinity, zMaxY = double.negativeInfinity;

        for (var p in polygon) {
          if (p[0] < zMinX) zMinX = p[0].toDouble();
          if (p[0] > zMaxX) zMaxX = p[0].toDouble();
          if (p[1] < zMinY) zMinY = p[1].toDouble();
          if (p[1] > zMaxY) zMaxY = p[1].toDouble();
        }

        int startI = ((zMinX - minX) / cellSize).floor().clamp(0, cols - 1);
        int endI = ((zMaxX - minX) / cellSize).ceil().clamp(0, cols - 1);
        int startJ = ((zMinY - minY) / cellSize).floor().clamp(0, rows - 1);
        int endJ = ((zMaxY - minY) / cellSize).ceil().clamp(0, rows - 1);

        for (int i = startI; i <= endI; i++) {
          for (int j = startJ; j <= endJ; j++) {
            if (_grid![i][j]) continue;

            double cellWorldX = minX + (i * cellSize) + (cellSize / 2);
            double cellWorldY = minY + (j * cellSize) + (cellSize / 2);

            if (_pointInPolygon(cellWorldX, cellWorldY, polygon)) {
              _grid![i][j] = true;
              contadorCeldasCaminables++;
            }
          }
        }
      }
    }
    debugPrint("Rasterización completada. Celdas caminables: $contadorCeldasCaminables");
  }

  bool _pointInPolygon(double x, double y, List<dynamic> poly) {
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      double xi = poly[i][0].toDouble(), yi = poly[i][1].toDouble();
      double xj = poly[j][0].toDouble(), yj = poly[j][1].toDouble();

      bool intersect = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  // Getter para exportar
  Map<String, dynamic> exportarDatos() {
    return {
      'grid': _grid,
      'minX': minX,
      'minY': minY,
      'cellSize': cellSize,
      'cols': cols,
      'rows': rows
    };
  }
}
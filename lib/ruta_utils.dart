import 'dart:math';

class Nodo {
  final int x, y;
  double g = 0;
  double h = 0;
  double get f => g + h;
  Nodo? padre;

  Nodo(this.x, this.y);

  @override
  bool operator ==(Object other) => other is Nodo && x == other.x && y == other.y;
  @override
  int get hashCode => Object.hash(x, y);
}

enum TipoGiro { recto, derecha, izquierda, destino }

class InstruccionRuta {
  final String texto;
  final double distancia; // en metros
  final TipoGiro tipo;

  InstruccionRuta({required this.texto, required this.distancia, required this.tipo});
}

class BuscadorRutas {
  static List<Nodo> encontrarRutaAislada(Map<String, dynamic> datos) {
    // 1. DESEMPAQUETAR
    List<List<bool>> grid = (datos['datosMapa']['grid'] as List)
        .map((e) => (e as List).cast<bool>())
        .toList();

    double minX = datos['datosMapa']['minX'];
    double minY = datos['datosMapa']['minY'];
    double cellSize = datos['datosMapa']['cellSize'];
    int cols = datos['datosMapa']['cols'];
    int rows = datos['datosMapa']['rows'];

    // 2. CONVERTIR METROS -> ÍNDICES
    int startX = ((datos['startX'] - minX) / cellSize).floor();
    int startY = ((datos['startY'] - minY) / cellSize).floor();
    int endX = ((datos['endX'] - minX) / cellSize).floor();
    int endY = ((datos['endY'] - minY) / cellSize).floor();

    // --- CORRECCIÓN DE SEGURIDAD (SNAP TO GRID) ---
    if (!_esValido(grid, startX, startY, cols, rows)) {
      var nuevoInicio = _buscarCaminableCercano(grid, startX, startY, cols, rows);
      if (nuevoInicio != null) {
        startX = nuevoInicio.x;
        startY = nuevoInicio.y;
      } else {
        return [];
      }
    }

    if (!_esValido(grid, endX, endY, cols, rows)) {
      var nuevoFin = _buscarCaminableCercano(grid, endX, endY, cols, rows);
      if (nuevoFin != null) {
        endX = nuevoFin.x;
        endY = nuevoFin.y;
      } else {
        return [];
      }
    }

    // 3. A*
    Nodo inicio = Nodo(startX, startY);
    Nodo destino = Nodo(endX, endY);

    List<Nodo> abierta = [inicio];
    Set<Nodo> cerrada = {};
    Map<String, Nodo> abiertaMap = {"${inicio.x},${inicio.y}": inicio};

    while (abierta.isNotEmpty) {
      abierta.sort((a, b) => a.f.compareTo(b.f));
      Nodo actual = abierta.removeAt(0);
      abiertaMap.remove("${actual.x},${actual.y}");

      if (actual.x == destino.x && actual.y == destino.y) {
        List<Nodo> ruta = [];
        Nodo? temp = actual;
        while (temp != null) {
          ruta.insert(0, temp);
          temp = temp.padre;
        }
        return ruta;
      }

      cerrada.add(actual);

      List<Nodo> vecinos = [
        Nodo(actual.x + 1, actual.y),
        Nodo(actual.x - 1, actual.y),
        Nodo(actual.x, actual.y + 1),
        Nodo(actual.x, actual.y - 1),
        Nodo(actual.x + 1, actual.y + 1),
        Nodo(actual.x - 1, actual.y - 1),
        Nodo(actual.x + 1, actual.y - 1),
        Nodo(actual.x - 1, actual.y + 1),
      ];

      for (Nodo vecino in vecinos) {
        if (vecino.x < 0 || vecino.x >= cols || vecino.y < 0 || vecino.y >= rows) continue;
        if (cerrada.contains(vecino)) continue;
        if (grid[vecino.x][vecino.y] == false) continue;

        double distancia = (vecino.x != actual.x && vecino.y != actual.y) ? 1.41 : 1.0;
        double nuevoCostoG = actual.g + distancia;

        Nodo? enAbierta = abiertaMap["${vecino.x},${vecino.y}"];

        if (enAbierta == null || nuevoCostoG < enAbierta.g) {
          vecino.g = nuevoCostoG;
          vecino.h = sqrt(pow(vecino.x - destino.x, 2) + pow(vecino.y - destino.y, 2));
          vecino.padre = actual;

          if (enAbierta == null) {
            abierta.add(vecino);
            abiertaMap["${vecino.x},${vecino.y}"] = vecino;
          } else {
            enAbierta.g = vecino.g;
            enAbierta.padre = actual;
          }
        }
      }
    }
    return [];
  }

  static bool _esValido(List<List<bool>> grid, int x, int y, int cols, int rows) {
    if (x < 0 || x >= cols || y < 0 || y >= rows) return false;
    return grid[x][y];
  }

  static Nodo? _buscarCaminableCercano(List<List<bool>> grid, int cx, int cy, int cols, int rows) {
    int radioMax = 5;
    for (int r = 1; r <= radioMax; r++) {
      for (int x = cx - r; x <= cx + r; x++) {
        for (int y = cy - r; y <= cy + r; y++) {
          if (_esValido(grid, x, y, cols, rows)) {
            return Nodo(x, y);
          }
        }
      }
    }
    return null;
  }

  // EL MÉTODO AHORA ESTÁ DENTRO DE LA CLASE
  static List<InstruccionRuta> generarInstrucciones(List<Nodo> ruta, double cellSize) {
    if (ruta.length < 2) return [];

    List<InstruccionRuta> instrucciones = [];
    double distanciaAcumulada = 0;

    for (int i = 0; i < ruta.length - 2; i++) {
      Nodo a = ruta[i];
      Nodo b = ruta[i + 1];
      Nodo c = ruta[i + 2];

      int v1x = b.x - a.x;
      int v1y = b.y - a.y;
      int v2x = c.x - b.x;
      int v2y = c.y - b.y;

      int crossProduct = (v1x * v2y) - (v1y * v2x);
      distanciaAcumulada += cellSize;

      if (crossProduct != 0) {
        String giro = crossProduct < 0 ? "la derecha" : "la izquierda"; // Cambiamos > por <
        TipoGiro tipo = crossProduct < 0 ? TipoGiro.derecha : TipoGiro.izquierda; // Cambiamos > por

        instrucciones.add(InstruccionRuta(
            texto: "En ${distanciaAcumulada.toStringAsFixed(1)}m, dobla a $giro",
            distancia: distanciaAcumulada,
            tipo: tipo));
        distanciaAcumulada = 0;
      }
    }

    distanciaAcumulada += cellSize;
    instrucciones.add(InstruccionRuta(
        texto: "Has llegado a tu destino",
        distancia: distanciaAcumulada,
        tipo: TipoGiro.destino));

    return instrucciones;
  }
}
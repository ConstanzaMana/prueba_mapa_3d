import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:prueba_mapa_3d/redUtils.dart';
import 'package:prueba_mapa_3d/ruta_utils.dart';
import 'coordenadas_utils.dart';
import 'grid_manager.dart';


class MapaInteractivoScreen extends StatefulWidget {
  const MapaInteractivoScreen({super.key});

  @override
  State<MapaInteractivoScreen> createState() => _MapaInteractivoScreenState();
}

class _MapaInteractivoScreenState extends State<MapaInteractivoScreen> {
  // Paleta de colores de la aplicacion
  final Color _cDarkBlue = const Color(0xFF193B59);  // Fondo Paneles
  final Color _cSlate = const Color(0xFF2F4659);     // Campos de texto / Fondos secundarios
  final Color _cCyan = const Color(0xFF77F2F2);      // Botones de Acción / Iconos activos
  final Color _cLight = const Color(0xFFC4DDF2);     // Texto / Iconos pasivos

  // Variables de estado del Plano
  String _targetActual = "0m 0m 0m";
  String _orbitActual = "90deg 15deg 150m";
  String _hotspotActual = "";
  String _idActual = "VISTA_GENERAL";
  List<String> _rutaPuntos = [];
  String _mapKey = "mapa_inicial";
  List<InstruccionRuta> _instrucciones = [];
  bool _enGuiadoReal = false;
  List<Map<String, dynamic>> _puntosRutaDetalle = [];
  String _idOrigenSimulado = "D10"; // Simulación de ubicación usuario
  List<dynamic> _zonasBloqueadas = [];
  List<Map<String, String>> _destinos = [
    {"id": "VISTA_GENERAL", "nombre": "Vista General", "target": "0m 0m 0m", "orbit": "0deg 45deg 80m", "hotspot": ""},
  ];
  String _modoBusqueda = "Aulas"; // Opciones: "Aulas", "Profesores", "Materias"
  DateTime _horarioConsulta = DateTime.now(); // Por defecto la hora actual
  List<Map<String, dynamic>> _cachePersonal = [];
  List<Map<String, dynamic>> _cacheMaterias = [];
  // Para optimizacion de las zonas bloqueada
  final GridManager _gridManager = GridManager(cellSize: 0.4); // 40cm de precisión

  // Variables de Estado de la interfaz
  bool _modoNavegacion = false; //panel de configuración
  bool _rutaLista = false;      //ruta ya calculada
  String _idOrigenRuta = "UBICACION_ACTUAL";
  String _nombreOrigenDisplay = "Tu ubicación";

  // --- ESTADO DE INFORMACIÓN DE BÚSQUEDA ---
  bool _mostrarInfoBusqueda = false;
  String _tituloInfo = "";
  String _subtituloInfo = "";

  // --- ESTADO DE NAVEGACIÓN DINÁMICA ---
  int _indicePuntoActual = 0; // En qué punto de la lista de nodos estamos
  bool _recalculando = false;
  List<Nodo> _rutaNodosActual = []; // Guardamos los nodos para el recálculo

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    // Carga paralela de datos
    var resultados = await Future.wait([
      CoordenadasUtils.cargarYProcesarDestinos(),
      redUtils.obtenerZonasBloqueadas(),
      redUtils.obtenerListaPersonal(),
      redUtils.obtenerListaMaterias(),
    ]);

    List<Map<String, String>> listaProcesada = resultados[0] as List<Map<String, String>>;
    List<dynamic> zonasBloqueadas = resultados[1] as List<dynamic>;

    setState(() {
      _destinos = resultados[0] as List<Map<String, String>>;
      _zonasBloqueadas = resultados[1] as List<dynamic>;
      _cachePersonal = (resultados[2] as List).cast<Map<String, dynamic>>();
      _cacheMaterias = (resultados[3] as List).cast<Map<String, dynamic>>();
    });

    // Generacion de gril
    debugPrint("Iniciando rasterización de mapa...");
    await Future.delayed(const Duration(milliseconds: 100));
    _gridManager.inicializarDesdeZonas(zonasBloqueadas);
    debugPrint("¡Mapa rasterizado y listo para navegar!");
  }

  //Navegacion

  // Selección directa (Zoom al aula)
  void _seleccionarDestino(String idSeleccionado) {
    final destino = _destinos.firstWhere((d) => d["id"] == idSeleccionado, orElse: () => _destinos[0]);

    setState(() {
      _idActual = idSeleccionado;
      _targetActual = destino["target"]!;
      _orbitActual = destino["orbit"]!;
      _hotspotActual = destino["hotspot"] ?? "";
      _rutaPuntos = [];
      _rutaLista = false;
      _modoNavegacion = false;

      _mapKey = "mapa_$idSeleccionado";
    });
  }

  Future<void> _calcularRutaDinamica() async {
    Map<String, String> origenData;
    if (_idOrigenRuta == "UBICACION_ACTUAL") {
      origenData = _destinos.firstWhere((d) => d["id"] == _idOrigenSimulado, orElse: () => _destinos[0]);
    } else {
      origenData = _destinos.firstWhere((d) => d["id"] == _idOrigenRuta, orElse: () => _destinos[0]);
    }
    final destinoData = _destinos.firstWhere((d) => d["id"] == _idActual);

    double oX = double.parse(origenData["x"]!);
    double oY = double.parse(origenData["y"]!);
    double dX = double.parse(destinoData["x"]!);
    double dY = double.parse(destinoData["y"]!);

    var datosMapa = _gridManager.exportarDatos();

    List<Nodo> rutaReal = await compute(BuscadorRutas.encontrarRutaAislada, {
      'startX': oX, 'startY': oY, 'endX': dX, 'endY': dY,
      'datosMapa': datosMapa,
    });

    if (rutaReal.isNotEmpty) {
      _instrucciones = BuscadorRutas.generarInstrucciones(rutaReal, _gridManager.cellSize);

      List<String> nuevaRutaVisual = [];
      List<Map<String, dynamic>> nuevaRutaDetalle = [];

      double minX = _gridManager.minX;
      double minY = _gridManager.minY;
      double cellSize = _gridManager.cellSize;

      for (int i = 0; i < rutaReal.length; i++) {
        double mundoX = minX + (rutaReal[i].x * cellSize) + (cellSize / 2);
        double mundoY = minY + (rutaReal[i].y * cellSize) + (cellSize / 2);
        var coords3D = CoordenadasUtils.traducirCoordenadasJsonAMapa(mundoX, mundoY);

        String posStr = coords3D["hotspotPos"]!;
        nuevaRutaVisual.add(posStr);

        double anguloCamara = 0;
        if (i + 1 < rutaReal.length) {
          int dx = rutaReal[i + 1].x - rutaReal[i].x;
          int dy = rutaReal[i + 1].y - rutaReal[i].y;
          anguloCamara = (atan2(dx.toDouble(), -dy.toDouble()) * 180 / pi) + 180;
        }

        nuevaRutaDetalle.add({
          'pos': posStr,
          'angle': anguloCamara,
        });
      }

      setState(() {
        _rutaPuntos = nuevaRutaVisual;
        _puntosRutaDetalle = nuevaRutaDetalle;
        _rutaLista = true;
        _enGuiadoReal = false;
        _targetActual = "0m 0m 0m";
        _orbitActual = "0deg 0deg 80m";
        _mapKey = "ruta_${DateTime.now()}";
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se encontró una ruta válida."))
      );
    }
  }

  // Interfaz
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // CAPA 1: MAPA 3D
          SizedBox.expand(
            child: ModelViewer(
              key: ValueKey(_mapKey),
              src: kIsWeb ? 'mapa3.glb' : 'assets/mapa3.glb',
              backgroundColor: Colors.transparent,
              cameraTarget: _targetActual,
              cameraOrbit: _orbitActual,
              minCameraOrbit: "auto 0deg 2m",
              maxCameraOrbit: "auto 80deg 90m",
              fieldOfView: "30deg",
              environmentImage: 'neutral',
              exposure: 0.4,
              cameraControls: true,
              innerModelViewerHtml: '''
                <style>
                  .marcador-destino {
                    display: block; width: 24px; height: 24px; background-color: #77F2F2; 
                    border-radius: 50%; border: 3px solid #193B59;
                    box-shadow: 0px 0px 15px #77F2F2;
                    transform: translate(-50%, -50%); animation: latido 1.5s infinite; 
                  }

                  /* ESTILO LÍNEA DE PUNTOS (NEÓN) */
                  .punto-ruta {
                    display: block; 
                    width: 6px; height: 6px; /* Puntos pequeños */
                    background-color: #77F2F2; 
                    border-radius: 50%; 
                    transform: translate(-50%, -50%);
                    /* Resplandor para que parezca luz */
                    box-shadow: 0 0 5px #77F2F2, 0 0 10px #77F2F2; 
                    pointer-events: none;
                  }
                  
                  @keyframes latido {
                    0% { transform: translate(-50%, -50%) scale(0.9); opacity: 0.7; }
                    50% { transform: translate(-50%, -50%) scale(1.1); opacity: 1; }
                    100% { transform: translate(-50%, -50%) scale(0.9); opacity: 0.7; }
                  }
                </style>

                ${_hotspotActual.isNotEmpty ? '<div slot=\"hotspot-destino\" data-position=\"$_hotspotActual\" data-normal=\"0 1 0\" class=\"marcador-destino\"></div>' : ''}
                
                ${_puntosRutaDetalle.asMap().entries.map((entry) {
                // Renderizamos TODOS los puntos iguales. Al estar tan juntos, forman una línea.
                return '<div slot=\"hotspot-ruta-${entry.key}\" data-position=\"${entry.value['pos']}\" class=\"punto-ruta\"></div>';
              }).join('\n')}
              ''',
            ),
          ),

          // CAPA 2: UI SUPERIOR
          if (!_modoNavegacion && !_rutaLista)
            Positioned(
              top: 50, left: 15, right: 15,
              child: _buildBarraSuperiorCombinada(),
            ),
          if (_mostrarInfoBusqueda && !_modoNavegacion && !_rutaLista)
            _buildPanelInfoBusqueda(),

          // CAPA 3: BOTÓN "CÓMO LLEGAR"
          if (!_modoNavegacion && !_rutaLista && _idActual != "VISTA_GENERAL")
            Positioned(
              bottom: 30, right: 20,
              child: FloatingActionButton.extended(
                backgroundColor: _cCyan,
                foregroundColor: _cDarkBlue,
                elevation: 6,
                icon: const Icon(Icons.directions_outlined),
                label: const Text("Cómo llegar", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  FocusScope.of(context).unfocus();
                  await _calcularRutaDinamica();
                  setState(() {
                    _enGuiadoReal = false;
                    _orbitActual = "0deg 0deg 80m";
                    _targetActual = "0m 0m 0m";
                  });
                },
              ),
            ),
          // Agregalo al final del Stack en el método build para probar
          // Ubicar dentro del Stack en el método build
          if (_enGuiadoReal)
            Positioned(
              top: 150,
              left: 20,
              child: FloatingActionButton(
                backgroundColor: _cDarkBlue,
                child: Icon(Icons.sync_problem, color: _cCyan), // "sync_problem" en minúsculas
                onPressed: () => _activarRecalculo(2880.0, 510.0), // Simulación de desvío
              ),
            ),

          // CAPA 4: PANEL DE NAVEGACIÓN
          if (_rutaLista)
            Positioned(
              bottom: 20, left: 15, right: 15,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _cDarkBlue,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10)],
                ),
                child: Row(
                  children: [
                    Icon(
                      _instrucciones.isEmpty ? Icons.location_on :
                      _instrucciones.first.tipo == TipoGiro.derecha ? Icons.turn_right :
                      _instrucciones.first.tipo == TipoGiro.izquierda ? Icons.turn_left :
                      Icons.directions_walk,
                      color: _cCyan, size: 35,
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        _instrucciones.isEmpty ? "Llegaste a tu destino" : _instrucciones.first.texto,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),

                    if (!_enGuiadoReal)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _cCyan,
                            foregroundColor: _cDarkBlue
                        ),
                        onPressed: () {
                          setState(() {
                            _enGuiadoReal = true;
                            _mostrarInfoBusqueda = false; // Ocultamos el panel de búsqueda

                          });
                          // Llamada crucial para iniciar el movimiento
                          _simularMovimiento();
                        },
                        child: const Text("IR"),
                      ),
                    IconButton(
                      icon: Icon(Icons.format_list_bulleted, color: _cLight),
                      onPressed: () => _mostrarListaPasos(context),
                    ),
                    // Busca este bloque dentro del CAPA 4: PANEL DE NAVEGACIÓN
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () {
                        setState(() {
                          // 1. DETENER la simulación inmediatamente
                          _enGuiadoReal = false;

                          // 2. Ocultar el panel de ruta
                          _rutaLista = false;

                          // 3. Limpiar las listas para que desaparezca el neón
                          _rutaPuntos = [];
                          _puntosRutaDetalle = []; // Importante limpiar esto también

                          // 4. RESTAURAR CÁMARA: Volver a la vista general (Zoom Out)
                          // Esto evita que se quede con el zoom del pasillo
                          _targetActual = "0m 0m 0m";
                          _orbitActual = "0deg 45deg 80m";

                          // 5. Refrescar el mapa
                          _mapKey = "reset_${DateTime.now()}";
                        });
                      },
                    ),
                  ],
                ),
              ),
            )
          else if (_modoNavegacion)
            _buildPanelNavegacionModerno(),
        ],


      ),



    );
  }

  // --- WIDGETS AUXILIARES ---

  Widget _buildHeaderFlotante() {
    return Row(
      children: [
        Icon(Icons.map_outlined, color: _cDarkBlue, size: 28),
        const SizedBox(width: 10),
        Text(
          "Indoor Map",
          style: TextStyle(color: _cDarkBlue, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1.0),
        ),
      ],
    );
  }

  Widget _buildBuscadorPrincipal() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_idActual != "VISTA_GENERAL")
          Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: FloatingActionButton.extended(
              backgroundColor: _cCyan,
              foregroundColor: _cDarkBlue,
              elevation: 4,
              icon: const Icon(Icons.directions_outlined),
              label: const Text("Cómo llegar", style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                setState(() {
                  _modoNavegacion = true;
                  _idOrigenRuta = "UBICACION_ACTUAL";
                  _nombreOrigenDisplay = "Tu ubicación";
                });
              },
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: _cDarkBlue,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [BoxShadow(color: _cDarkBlue.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          child: Autocomplete<Map<String, String>>(
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text == '') return const Iterable<Map<String, String>>.empty();
              return _destinos.where((op) => op["nombre"]!.toLowerCase().contains(textEditingValue.text.toLowerCase()));
            },
            displayStringForOption: (op) => op["nombre"]!,
            onSelected: (sel) => _seleccionarDestino(sel["id"]!),
            fieldViewBuilder: (ctx, ctrl, focus, onEdit) {
              return TextField(
                controller: ctrl, focusNode: focus,
                style: TextStyle(color: _cLight, fontSize: 16),
                cursorColor: _cCyan,
                decoration: InputDecoration(
                  hintText: "¿A dónde quieres ir?",
                  hintStyle: TextStyle(color: _cLight.withOpacity(0.5)),
                  border: InputBorder.none,
                  icon: Icon(Icons.search_rounded, color: _cCyan),
                  suffixIcon: Icon(Icons.mic_none_rounded, color: _cLight.withOpacity(0.5)),
                ),
                onEditingComplete: onEdit,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPanelNavegacionModerno() {
    String nombreDestino = _destinos.firstWhere((d) => d["id"] == _idActual, orElse: () => {"nombre": "..."})["nombre"]!;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.only(top: 0),
        padding: const EdgeInsets.fromLTRB(20, 50, 20, 25),
        decoration: BoxDecoration(
          color: _cDarkBlue,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Planificar Ruta", style: TextStyle(color: _cLight, fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: Icon(Icons.close, color: _cLight),
                  onPressed: () {
                    setState(() { _modoNavegacion = false; _rutaPuntos = []; _mapKey = "cancel_${DateTime.now()}"; });
                  },
                )
              ],
            ),
            const SizedBox(height: 15),
            Container(
              decoration: BoxDecoration(color: _cSlate, borderRadius: BorderRadius.circular(15)),
              padding: const EdgeInsets.all(15),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.my_location, color: _cCyan, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Autocomplete<Map<String, String>>(
                          initialValue: TextEditingValue(text: _nombreOrigenDisplay),
                          optionsBuilder: (val) {
                            if (val.text.isEmpty) return const Iterable<Map<String, String>>.empty();
                            return _destinos.where((op) => op["nombre"]!.toLowerCase().contains(val.text.toLowerCase()));
                          },
                          displayStringForOption: (op) => op["nombre"]!,
                          onSelected: (sel) {
                            setState(() { _idOrigenRuta = sel["id"]!; _nombreOrigenDisplay = sel["nombre"]!; });
                          },
                          fieldViewBuilder: (ctx, ctrl, focus, onEdit) {
                            return TextField(
                              controller: ctrl, focusNode: focus,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none,
                                hintText: "Origen...", hintStyle: TextStyle(color: _cLight.withOpacity(0.5)),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  Divider(color: _cLight.withOpacity(0.2), height: 25),
                  Row(
                    children: [
                      Icon(Icons.location_on, color: const Color(0xFFFF6B6B), size: 18),
                      const SizedBox(width: 12),
                      Expanded(child: Text(nombreDestino, style: TextStyle(color: _cLight, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  FocusScope.of(context).unfocus();
                  await _calcularRutaDinamica();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _cCyan, foregroundColor: _cDarkBlue,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 0,
                ),
                child: const Text("INICIAR RUTA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelRutaLista() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cDarkBlue,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _cCyan.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.directions_run, color: _cCyan),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Ruta Calculada", style: TextStyle(color: _cCyan, fontSize: 12, fontWeight: FontWeight.bold)),
                    Text("Sigue la línea iluminada", style: TextStyle(color: _cLight, fontSize: 16)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: _cLight),
                onPressed: () {
                  setState(() {
                    _rutaLista = false;
                    _enGuiadoReal = false; // Resetear esto también
                    _rutaPuntos = [];
                    _mapKey = "reset_${DateTime.now()}";
                  });
                },
              )
            ],
          ),
        ],
      ),
    );
  }

  final LayerLink _capaBuscadorLink = LayerLink();

  Widget _buildBarraSuperiorCombinada() {
    bool filtrosActivos = _modoBusqueda != "Aulas";
    Color colorFiltros = filtrosActivos ? _cCyan : _cLight.withOpacity(0.3);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => FocusScope.of(context).unfocus(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // LOGO
              Image.asset('assets/logo.png', height: 40, width: 40),
              const SizedBox(width: 10),
              Text("InMap", style: TextStyle(color: _cDarkBlue, fontSize: 20, fontWeight: FontWeight.w900)),

              const Spacer(),

              // 1. SELECTOR DE MODO
              _buildCapsulaFiltro(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _modoBusqueda,
                    dropdownColor: _cDarkBlue,
                    icon: Icon(Icons.arrow_drop_down, color: _cCyan, size: 20),
                    style: TextStyle(color: _cCyan, fontWeight: FontWeight.bold, fontSize: 13),
                    items: ["Aulas", "Profesores", "Materias"].map((String value) {
                      // Texto corto para que no rompa el diseño en el botón
                      String label = value == "Profesores" ? "Profesor" : (value == "Materias" ? "Materia" : "Aulas");
                      return DropdownMenuItem<String>(value: value, child: Text(label));
                    }).toList(),
                    onChanged: (val) => setState(() => _modoBusqueda = val!),
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // 2. CÁPSULA UNIFICADA (Fecha + Hora)
              IgnorePointer(
                ignoring: !filtrosActivos,
                child: _buildCapsulaFiltro(
                  onTap: () async {
                    // Al tocar el cuerpo principal, abrimos la HORA por defecto
                    final TimeOfDay? time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_horarioConsulta),
                      builder: (context, child) => _tematizarDialogo(child!),
                    );
                    if (time != null) {
                      setState(() {
                        _horarioConsulta = DateTime(_horarioConsulta.year, _horarioConsulta.month, _horarioConsulta.day, time.hour, time.minute);
                      });
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icono de reloj y hora
                      Icon(Icons.access_time, color: colorFiltros, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        "${_horarioConsulta.hour}:${_horarioConsulta.minute.toString().padLeft(2, '0')}",
                        style: TextStyle(color: colorFiltros, fontWeight: FontWeight.bold, fontSize: 13),
                      ),

                      // Separador visual sutil
                      VerticalDivider(color: colorFiltros.withOpacity(0.3), indent: 8, endIndent: 8, width: 12),

                      // BOTÓN PEQUEÑO PARA FECHA (Dentro de la misma cápsula)
                      GestureDetector(
                        onTap: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: _horarioConsulta,
                            firstDate: DateTime(2025),
                            lastDate: DateTime(2030),
                            builder: (context, child) => _tematizarDialogo(child!),
                          );
                          if (picked != null) {
                            setState(() {
                              _horarioConsulta = DateTime(picked.year, picked.month, picked.day, _horarioConsulta.hour, _horarioConsulta.minute);
                            });
                          }
                        },
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month, color: colorFiltros, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              _esHoy(_horarioConsulta) ? "Hoy" : _nombreDiaCorto(_horarioConsulta),
                              style: TextStyle(color: colorFiltros, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCajaAutocompleteDinamica(),
        ],
      ),
    );
  }

// Función auxiliar para no repetir el código del tema oscuro en los selectores
  Widget _tematizarDialogo(Widget child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.dark(
          primary: _cCyan, onPrimary: _cDarkBlue,
          surface: _cDarkBlue, onSurface: _cLight,
        ),
        textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: _cCyan)),
      ),
      child: child,
    );
  }

  // --- WIDGET HELPER: CÁPSULA DE FILTRO ---
  // Unifica el diseño de los botones (Fondo azul redondeado)
  Widget _buildCapsulaFiltro({required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 35, // Altura compacta
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _cDarkBlue,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10), // Borde sutil
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  // --- MÉTODOS AUXILIARES DE FECHA ---
  bool _esHoy(DateTime fecha) {
    final now = DateTime.now();
    return fecha.year == now.year && fecha.month == now.month && fecha.day == now.day;
  }

  String _nombreDiaCorto(DateTime fecha) {
    // Retorna Lun, Mar, Mié...
    const dias = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"];
    return dias[fecha.weekday - 1];
  }
  void _mostrarListaPasos(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cDarkBlue,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Pasos de la ruta", style: TextStyle(color: _cCyan, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              Expanded(
                child: ListView.separated(
                  itemCount: _instrucciones.length,
                  separatorBuilder: (_, __) => Divider(color: _cLight.withOpacity(0.1)),
                  itemBuilder: (context, index) {
                    final paso = _instrucciones[index];
                    return ListTile(
                      leading: Icon(
                        paso.tipo == TipoGiro.derecha ? Icons.turn_right :
                        paso.tipo == TipoGiro.izquierda ? Icons.turn_left :
                        Icons.location_on,
                        color: _cLight,
                      ),
                      title: Text(paso.texto, style: const TextStyle(color: Colors.white)),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 1. Vista desde arriba (Cenital)
  void _verDesdeArriba() {
    setState(() {
      _orbitActual = "0deg 0deg 50m"; // 0deg de inclinación es totalmente arriba
      _targetActual = "0m 0m 0m";    // O el centro de tu mapa
    });
  }

// 2. Vista de Navegación (Inclinada y Zoom)
  // Cambia la definición de la función para aceptar el ángulo
  void _enfocarNavegacion(String posicionHotspot, double anguloGiro) {
    setState(() {
      _targetActual = posicionHotspot;

      // Usamos el ángulo calculado dinámicamente
      // Agregamos un ajuste (por ejemplo +180 o +90) si notas que la cámara mira al revés
      _orbitActual = "${anguloGiro}deg 60deg 25m";
    });
  }
  void _manejarSeleccionFiltro(dynamic seleccion) async {
    String? idDestinoFinal;
    String nombreSeleccionado = "";
    String diaStr = _obtenerNombreDia(_horarioConsulta);
    String horaStr = "${_horarioConsulta.hour.toString().padLeft(2, '0')}:${_horarioConsulta.minute.toString().padLeft(2, '0')}:00";

    // Mostramos un indicador de carga si lo deseas, o simplemente procedemos
    if (_modoBusqueda == "Profesores") {
      final map = seleccion as Map<String, dynamic>;
      nombreSeleccionado = map['nombreCompleto'];
      idDestinoFinal = await redUtils.buscarUbicacionPersonal(map['idPersonal'].toString(), horaStr, diaStr);
    } else if (_modoBusqueda == "Materias") {
      final map = seleccion as Map<String, dynamic>;
      nombreSeleccionado = map['nombreMateria'];
      idDestinoFinal = await redUtils.buscarUbicacionMateria(map['codMateria'].toString(), horaStr, diaStr);
    } else {
      final map = seleccion as Map<String, String>;
      nombreSeleccionado = map['nombre']!;
      idDestinoFinal = map['id'];
    }

    if (idDestinoFinal != null) {
      // Buscamos el nombre del aula para el panel
      final destinoData = _destinos.firstWhere((d) => d["id"] == idDestinoFinal, orElse: () => {"nombre": "Desconocido"});

      setState(() {
        _tituloInfo = nombreSeleccionado;
        // Construimos el mensaje dinámico
        if (_modoBusqueda == "Profesores") {
          _subtituloInfo = "Está dictando en el ${destinoData['nombre']}";
        } else if (_modoBusqueda == "Materias") {
          _subtituloInfo = "Se dicta en el ${destinoData['nombre']}";
        } else {
          _subtituloInfo = "Aula seleccionada";
        }
        _mostrarInfoBusqueda = true;
      });

      _seleccionarDestino(idDestinoFinal);
    } else {
      setState(() => _mostrarInfoBusqueda = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se encontró ubicación para el horario seleccionado"))
      );
    }
  }
  Widget _buildCajaAutocompleteDinamica() {
    final double anchoLista = MediaQuery.of(context).size.width - 40;

    // CAMBIO: Usamos Object en lugar de dynamic
    return CompositedTransformTarget(
      link: _capaBuscadorLink,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: _cDarkBlue,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Autocomplete<Object>(
          optionsBuilder: (TextEditingValue textValue) {
            if (textValue.text.isEmpty) return const Iterable<Object>.empty();

            if (_modoBusqueda == "Profesores") {
              return _cachePersonal.where((p) =>
                  p['nombreCompleto'].toString().toLowerCase().contains(textValue.text.toLowerCase()));
            } else if (_modoBusqueda == "Materias") {
              return _cacheMaterias.where((m) =>
                  m['nombreMateria'].toString().toLowerCase().contains(textValue.text.toLowerCase()));
            } else {
              return _destinos.where((d) =>
                  d['nombre']!.toLowerCase().contains(textValue.text.toLowerCase()));
            }
          },
          displayStringForOption: (option) {
            // Casteamos a Map para acceder a las llaves
            final map = option as Map<String, dynamic>;
            if (_modoBusqueda == "Profesores") return map['nombreCompleto'] ?? "";
            if (_modoBusqueda == "Materias") return map['nombreMateria'] ?? "";
            return map['nombre'] ?? "";
          },
          onSelected: (sel) => _manejarSeleccionFiltro(sel),

          optionsViewBuilder: (context, onSelected, options) {
            return CompositedTransformFollower(
              link: _capaBuscadorLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 55),
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8,
                  color: _cSlate,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    width: anchoLista,
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index) as Map<String, dynamic>;
                        String titulo = _modoBusqueda == "Profesores" ? option['nombreCompleto'] :
                        _modoBusqueda == "Materias" ? option['nombreMateria'] : option['nombre'];
                        return ListTile(
                          title: Text(titulo, style: TextStyle(color: _cLight, fontSize: 14)),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
          fieldViewBuilder: (ctx, ctrl, focus, onEdit) {
            return TextField(
              controller: ctrl,
              focusNode: focus,
              style: TextStyle(color: _cLight, fontSize: 14),
              cursorColor: _cCyan,
              decoration: InputDecoration(
                hintText: "Buscar $_modoBusqueda...",
                hintStyle: TextStyle(color: _cLight.withOpacity(0.5)),
                border: InputBorder.none,
                icon: Icon(Icons.search, color: _cCyan, size: 20),
              ),
            );
          },
        ),
      ),
    );
  }
  String _obtenerNombreDia(DateTime fecha) {
    // Los días en Dart empiezan en 1 (Lunes) y terminan en 7 (Domingo)
    List<String> dias = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"];
    return dias[fecha.weekday - 1];
  }
  Widget _buildPanelInfoBusqueda() {
    return Positioned(
      bottom: 20,
      left: 15,
      right: 15,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: _cDarkBlue,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: _cCyan.withOpacity(0.3), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _cSlate, borderRadius: BorderRadius.circular(15)),
              child: Icon(
                _modoBusqueda == "Profesores" ? Icons.person : (_modoBusqueda == "Materias" ? Icons.book : Icons.room),
                color: _cCyan,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tituloInfo,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _subtituloInfo,
                    style: TextStyle(color: _cLight.withOpacity(0.8), fontSize: 14),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54, size: 20),
              onPressed: () => setState(() => _mostrarInfoBusqueda = false),
            ),
          ],
        ),
      ),
    );
  }
  void _verificarProgresoInstrucciones(int indiceActual) {
    if (_instrucciones.isEmpty) return;

    // Calculamos progreso inverso (cuánto falta)
    int pasosRestantes = _puntosRutaDetalle.length - indiceActual;

    // Avanzar instrucción cada 15 pasos (aprox 6-7 metros)
    // Usamos el índice para saber que avanzamos
    if (indiceActual > 0 && indiceActual % 15 == 0 && _instrucciones.length > 1) {
      setState(() {
        _instrucciones.removeAt(0);
      });
    }

    if (pasosRestantes < 3) {
      setState(() {
        _tituloInfo = "¡Llegaste!";
        _subtituloInfo = "Tu destino está aquí";
      });
    }
  }
  void _simularMovimiento() async {
    // Si no hay ruta, no hacemos nada
    if (_puntosRutaDetalle.isEmpty) return;

    // 1. Zoom inicial: Usamos tu función para ir al primer punto
    if (mounted) {
      var primerPunto = _puntosRutaDetalle.first;
      _enfocarNavegacion(primerPunto['pos'], primerPunto['angle']);
    }

    // Esperamos para dar tiempo a la cámara a llegar
    await Future.delayed(const Duration(milliseconds: 1500));

    debugPrint("--- INICIANDO RUTA ---");

    for (int i = 0; i < _puntosRutaDetalle.length; i++) {
      if (!_enGuiadoReal) break; // Si cancelas, para

      await Future.delayed(const Duration(milliseconds: 600));

      // --- CORRECCIÓN CRÍTICA ---
      // Verificamos si la pantalla sigue activa y si el índice sigue siendo válido
      if (!mounted || i >= _puntosRutaDetalle.length) break;

      // 2. EN CADA PASO: Llamamos a TU función que funciona bien
      var puntoSiguiente = _puntosRutaDetalle[i];
      _enfocarNavegacion(puntoSiguiente['pos'], puntoSiguiente['angle']);

      // Actualizamos solo el índice para la lógica interna
      setState(() {
        _indicePuntoActual = i;
      });

      // Actualizamos textos
      _verificarProgresoInstrucciones(i);
    }
  }

  // --- LÓGICA DE RECALCULO Y PROCESAMIENTO (Independientes) ---

  void _procesarNuevaRuta(List<Nodo> rutaReal) {
    _instrucciones = BuscadorRutas.generarInstrucciones(rutaReal, _gridManager.cellSize);
    List<String> nuevaRutaVisual = [];
    List<Map<String, dynamic>> nuevaRutaDetalle = [];

    for (int i = 0; i < rutaReal.length; i++) {
      double mundoX = _gridManager.minX + (rutaReal[i].x * _gridManager.cellSize) + (_gridManager.cellSize / 2);
      double mundoY = _gridManager.minY + (rutaReal[i].y * _gridManager.cellSize) + (_gridManager.cellSize / 2);
      var coords3D = CoordenadasUtils.traducirCoordenadasJsonAMapa(mundoX, mundoY);

      String posStr = coords3D["hotspotPos"]!;
      nuevaRutaVisual.add(posStr);

      double anguloCamara = 0;
      if (i + 1 < rutaReal.length) {
        int dx = rutaReal[i + 1].x - rutaReal[i].x;
        int dy = rutaReal[i + 1].y - rutaReal[i].y;
        anguloCamara = (atan2(dx.toDouble(), -dy.toDouble()) * 180 / pi) + 180;
      }

      nuevaRutaDetalle.add({'pos': posStr, 'angle': anguloCamara});
    }

    setState(() {
      _rutaPuntos = nuevaRutaVisual;
      _puntosRutaDetalle = nuevaRutaDetalle;
      _rutaLista = true;
      _mapKey = "recalculo_${DateTime.now()}";
    });
  }

  Future<void> _calcularRutaDesdePosicion(double xOrigen, double yOrigen) async {
    final destinoData = _destinos.firstWhere((d) => d["id"] == _idActual);
    double dX = double.parse(destinoData["x"]!);
    double dY = double.parse(destinoData["y"]!);

    var datosMapa = _gridManager.exportarDatos();

    List<Nodo> rutaReal = await compute(BuscadorRutas.encontrarRutaAislada, {
      'startX': xOrigen, 'startY': yOrigen,
      'endX': dX, 'endY': dY,
      'datosMapa': datosMapa,
    });

    if (rutaReal.isNotEmpty) {
      _procesarNuevaRuta(rutaReal);
    }
  }

  Future<void> _activarRecalculo(double xActual, double yActual) async {
    if (_recalculando) return;

    setState(() {
      _recalculando = true;
      _tituloInfo = "Recalculando ruta...";
      _subtituloInfo = "Buscando camino alternativo";
      _mostrarInfoBusqueda = true;
    });

    await Future.delayed(const Duration(seconds: 1));
    await _calcularRutaDesdePosicion(xActual, yActual);

    setState(() => _recalculando = false);
  }

}
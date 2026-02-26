import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'mapa_screen.dart';


void main() => runApp(const MiAppMapa());
//StatelessWidget: Porque esta clase en  no reacciona a cambios en vivo ni actualiza variables en pantalla
class MiAppMapa extends StatelessWidget {
  // Constructor de la clase.
  // "super.key" pasa el identificador único (Key) a la clase padre (StatelessWidget)
  const MiAppMapa({super.key});

  @override
  Widget build(BuildContext context) {
    //MaterialApp: envoltura  que le da a la aplicación acceso a todas las herramientas de interfaz gráfica
    return const MaterialApp(
      //oculta etiquetita roja que dice "DEBUG" en la esquina superior derecha del celular mientras se esta programando.
      debugShowCheckedModeBanner: false,
      //Indica que cuando termines de cargar, la primera pantalla que le va a mostrar al usuario es el mapa 3D
      home: MapaInteractivoScreen(),
    );
  }
}

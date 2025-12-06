import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wilobu_app/firebase_providers.dart';

class SosAlertPage extends ConsumerWidget {
  final String deviceId;
  final String userId;

  const SosAlertPage({
    super.key,
    required this.deviceId,
    required this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Stream del dispositivo para obtener datos en tiempo real
    final deviceStream = ref.watch(firestoreProvider)
        .collection('users')
        .doc(userId)
        .collection('devices')
        .doc(deviceId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: deviceStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) {
          return const Scaffold(
            body: Center(child: Text('Dispositivo no encontrado')),
          );
        }

        final status = data['status'] as String? ?? 'online';
        
        // Si ya no es SOS, redirigir al home
        if (!status.startsWith('sos_')) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pop();
          });
          return const Scaffold(
            body: Center(child: Text('Alerta cancelada')),
          );
        }

        // Determinar tipo de SOS
        String sosType = 'General';
        MaterialColor sosColor = Colors.red;
        IconData sosIcon = Icons.warning;
        String sosMessage = 'El usuario ha enviado una alerta de emergencia';
        String adviceMessage = 'Contacta al usuario lo antes posible para verificar su estado.';

        if (status == 'sos_medica') {
          sosType = 'Médica';
          sosIcon = Icons.medical_services;
          sosMessage = data['sosMessages']?['medica'] ?? 
              'Emergencia médica detectada. Se requiere asistencia inmediata.';
          adviceMessage = 'Llama a servicios de emergencia (911) si no puedes contactar al usuario.';
        } else if (status == 'sos_seguridad') {
          sosType = 'Seguridad';
          sosIcon = Icons.security;
          sosMessage = data['sosMessages']?['seguridad'] ?? 
              'Alerta de seguridad activada. Situación de peligro detectada.';
          adviceMessage = 'Contacta a las autoridades si el usuario no responde.';
        } else {
          sosMessage = data['sosMessages']?['general'] ?? 
              'Alerta de emergencia activada. Se requiere asistencia.';
        }

        // Ubicación
        final locationData = data['lastLocation'];
        double? latitude;
        double? longitude;
        String locationText = 'Ubicación no disponible';

        if (locationData != null) {
          if (locationData is GeoPoint) {
            latitude = locationData.latitude;
            longitude = locationData.longitude;
            locationText = 'Lat: ${latitude.toStringAsFixed(6)}, Lon: ${longitude.toStringAsFixed(6)}';
          } else if (locationData is Map) {
            latitude = locationData['latitude'] as double?;
            longitude = locationData['longitude'] as double?;
            if (latitude != null && longitude != null) {
              locationText = 'Lat: ${latitude.toStringAsFixed(6)}, Lon: ${longitude.toStringAsFixed(6)}';
            }
          }
        }

        return Scaffold(
          backgroundColor: sosColor.shade900,
          body: SafeArea(
            child: Column(
              children: [
                // Header con icono y tipo de alerta
                Container(
                  padding: const EdgeInsets.all(24),
                  color: sosColor.shade800,
                  child: Column(
                    children: [
                      Icon(sosIcon, size: 80, color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        'ALERTA SOS $sosType'.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        DateTime.now().toString().substring(0, 19),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Mensaje de SOS
                        Card(
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Mensaje:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  sosMessage,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Consejo
                        Card(
                          color: Colors.orange.shade100,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(Icons.lightbulb, color: Colors.orange),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    adviceMessage,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Ubicación
                        Card(
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.location_on, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text(
                                      'Última Ubicación Conocida',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(locationText),
                                if (latitude != null && longitude != null) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    height: 200,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade300,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.map, size: 48, color: Colors.grey),
                                          const SizedBox(height: 8),
                                          const Text('Mapa (Integrar flutter_map)'),
                                          Text('$latitude, $longitude'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Botones de acción
                        ElevatedButton.icon(
                          onPressed: () async {
                            final uri = Uri.parse('tel:911');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            }
                          },
                          icon: const Icon(Icons.phone),
                          label: const Text('Llamar a Emergencias (911)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),

                        const SizedBox(height: 12),

                        if (latitude != null && longitude != null)
                          ElevatedButton.icon(
                            onPressed: () async {
                              final uri = Uri.parse(
                                'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude'
                              );
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: const Icon(Icons.directions),
                            label: const Text('Cómo llegar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),

                        const SizedBox(height: 12),

                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.close),
                          label: const Text('Cerrar Alerta'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

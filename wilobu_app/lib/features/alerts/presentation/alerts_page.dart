import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wilobu_app/firebase_providers.dart';
import 'package:wilobu_app/theme/app_theme.dart';

// ===== MODELO DE ALERTA =====
class AlertItem {
  final String id;
  final String type;
  final String deviceId;
  final String senderName;
  final double? lat;
  final double? lng;
  final DateTime timestamp;
  final bool acknowledged;
  final bool isReceived; // true = recibida, false = enviada

  AlertItem({
    required this.id,
    required this.type,
    required this.deviceId,
    required this.senderName,
    this.lat,
    this.lng,
    required this.timestamp,
    required this.acknowledged,
    required this.isReceived,
  });

  factory AlertItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc, {required bool isReceived}) {
    final d = doc.data() ?? {};
    final loc = d['location'];
    double? lat, lng;
    
    // Caso 1: location es directamente un GeoPoint
    if (loc is GeoPoint) {
      lat = loc.latitude;
      lng = loc.longitude;
    }
    // Caso 2: location es un Map con geopoint o lat/lng
    else if (loc is Map<String, dynamic>) {
      final gp = loc['geopoint'];
      if (gp is GeoPoint) {
        lat = gp.latitude;
        lng = gp.longitude;
      } else {
        lat = (loc['lat'] as num?)?.toDouble();
        lng = (loc['lng'] as num?)?.toDouble();
      }
    }
    // Caso 3: lat/lng directos en el documento
    else if (d['lat'] != null && d['lng'] != null) {
      lat = (d['lat'] as num?)?.toDouble();
      lng = (d['lng'] as num?)?.toDouble();
    }
    
    debugPrint('📍 Alert ${doc.id}: location=$loc, lat=$lat, lng=$lng');
    
    return AlertItem(
      id: doc.id,
      type: d['type'] ?? d['alertType'] ?? 'general',
      deviceId: d['deviceId'] ?? d['fromDeviceId'] ?? '',
      senderName: d['senderName'] ?? d['fromUserName'] ?? d['ownerName'] ?? d['userName'] ?? 'Usuario',
      lat: lat,
      lng: lng,
      timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      acknowledged: d['acknowledged'] ?? d['resolved'] ?? false,
      isReceived: isReceived,
    );
  }

  String get typeLabel {
    final normalizedType = type.replaceFirst('sos_', '');
    return switch (normalizedType) {
      'general' => 'Asistencia no urgente',
      'medica' => 'Emergencia médica',
      'seguridad' => 'Emergencia de seguridad',
      _ => type,
    };
  }
  
  String get typeDescription => switch (type.replaceFirst('sos_', '')) {
    'general' => 'El usuario solicita asistencia',
    'medica' => 'Este usuario podría estar herido',
    'seguridad' => 'Alguien podría querer hacerle daño',
    _ => '',
  };

  Color get typeColor {
    final t = type.replaceFirst('sos_', '');
    return switch (t) {
      'medica' => Colors.red,
      'seguridad' => Colors.orange,
      _ => Colors.blue,
    };
  }

  IconData get typeIcon {
    final t = type.replaceFirst('sos_', '');
    return switch (t) {
      'medica' => Icons.local_hospital,
      'seguridad' => Icons.shield,
      _ => Icons.info_outline,
    };
  }
}

// ===== PROVIDERS =====
final receivedAlertsProvider = StreamProvider.autoDispose<List<AlertItem>>((ref) {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) {
    debugPrint('⚠️ receivedAlertsProvider: No hay usuario logueado');
    return const Stream.empty();
  }
  
  debugPrint('📥 receivedAlertsProvider: Buscando alertas para ${user.uid}');
  
  return ref.watch(firestoreProvider)
    .collection('users').doc(user.uid).collection('receivedAlerts')
    .orderBy('timestamp', descending: true)
    .limit(50)
    .snapshots()
    .map((s) {
      debugPrint('📥 receivedAlerts: ${s.docs.length} documentos encontrados');
      return s.docs.map((doc) => AlertItem.fromDoc(doc, isReceived: true)).toList();
    });
});

final sentAlertsProvider = StreamProvider.autoDispose<List<AlertItem>>((ref) {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) {
    debugPrint('⚠️ sentAlertsProvider: No hay usuario logueado');
    return const Stream.empty();
  }
  
  debugPrint('📤 sentAlertsProvider: Buscando dispositivos para ${user.uid}');
  
  // Obtener alertas de todos los dispositivos del usuario
  return ref.watch(firestoreProvider)
    .collection('users').doc(user.uid).collection('devices')
    .snapshots()
    .asyncMap((devicesSnapshot) async {
      debugPrint('📤 Dispositivos encontrados: ${devicesSnapshot.docs.length}');
      final allAlerts = <AlertItem>[];
      
      for (final deviceDoc in devicesSnapshot.docs) {
        debugPrint('📤 Buscando historial en dispositivo: ${deviceDoc.id}');
        final historySnapshot = await deviceDoc.reference
          .collection('alertHistory')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();
        
        debugPrint('📤 alertHistory de ${deviceDoc.id}: ${historySnapshot.docs.length} alertas');
          
        allAlerts.addAll(
          historySnapshot.docs.map((doc) => AlertItem.fromDoc(doc, isReceived: false))
        );
      }
      
      // Ordenar por fecha
      allAlerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      debugPrint('📤 Total alertas enviadas: ${allAlerts.length}');
      return allAlerts.take(50).toList();
    });
});

// ===== PAGINA DE ALERTAS =====
class AlertsPage extends ConsumerStatefulWidget {
  const AlertsPage({super.key});

  @override
  ConsumerState<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends ConsumerState<AlertsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeControllerProvider);
    final background = AppTheme.buildWilobuBackground(themeMode);
    
    return Scaffold(
      extendBodyBehindAppBar: background != null,
      appBar: AppBar(
        title: const Text('Historial de Alertas'),
        backgroundColor: background != null ? Colors.transparent : null,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.call_received), text: 'Recibidas'),
            Tab(icon: Icon(Icons.call_made), text: 'Enviadas'),
          ],
        ),
      ),
      body: Stack(
        children: [
          if (background != null) background,
          SafeArea(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _ReceivedAlertsTab(),
                _SentAlertsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===== TAB ALERTAS RECIBIDAS =====
class _ReceivedAlertsTab extends ConsumerWidget {
  const _ReceivedAlertsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(receivedAlertsProvider);
    
    return alerts.when(
      data: (list) => list.isEmpty
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_off, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No hay alertas recibidas', style: TextStyle(color: Colors.grey, fontSize: 16)),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (_, i) => _AlertCard(alert: list[i]),
          ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ===== TAB ALERTAS ENVIADAS =====
class _SentAlertsTab extends ConsumerWidget {
  const _SentAlertsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(sentAlertsProvider);
    
    return alerts.when(
      data: (list) => list.isEmpty
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No hay alertas enviadas', style: TextStyle(color: Colors.grey, fontSize: 16)),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (_, i) => _AlertCard(alert: list[i]),
          ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ===== CARD DE ALERTA =====
class _AlertCard extends ConsumerWidget {
  final AlertItem alert;
  const _AlertCard({required this.alert});

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} minutos';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} horas';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatFullDate(DateTime dt) {
    const meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    return '${dt.day} ${meses[dt.month - 1]} ${dt.year}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _markAsAcknowledged(BuildContext context, WidgetRef ref) async {
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user == null) return;
    
    try {
      await ref.read(firestoreProvider)
        .collection('users').doc(user.uid)
        .collection('receivedAlerts').doc(alert.id)
        .update({'acknowledged': true, 'acknowledgedAt': FieldValue.serverTimestamp()});
        
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alerta marcada como vista'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openInMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showExpandedMap(BuildContext context, double lat, double lng, Color pinColor) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 320,
                width: double.infinity,
                child: FlutterMap(
                  options: MapOptions(initialCenter: LatLng(lat, lng), initialZoom: 15),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.wilobu_app',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(lat, lng),
                        child: Icon(Icons.location_pin, color: pinColor, size: 42),
                      ),
                    ]),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('Abrir en Google Maps'),
                      onPressed: () => _openInMaps(lat, lng),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _getDirections(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasLocation = alert.lat != null && alert.lng != null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Colores adaptativos según tema
    final textSecondary = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final textTertiary = isDark ? Colors.grey.shade500 : Colors.grey.shade700;
    final cardBg = alert.acknowledged 
      ? null 
      : (isDark ? alert.typeColor.withOpacity(0.15) : alert.typeColor.withOpacity(0.08));
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: cardBg,
      elevation: alert.acknowledged ? 1 : 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === HEADER ===
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: alert.typeColor.withOpacity(isDark ? 0.2 : 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: alert.typeColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(alert.typeIcon, color: alert.typeColor, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              alert.typeLabel.toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: 0.5,
                                color: isDark 
                                  ? Color.lerp(alert.typeColor, Colors.white, 0.4) 
                                  : Color.lerp(alert.typeColor, Colors.black, 0.2),
                              ),
                            ),
                          ),
                          if (!alert.acknowledged && alert.isReceived)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.notification_important, color: Colors.white, size: 12),
                                  SizedBox(width: 4),
                                  Text('NUEVA', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (alert.typeDescription.isNotEmpty) ...[  
                        const SizedBox(height: 2),
                        Text(
                          alert.typeDescription,
                          style: TextStyle(color: textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        alert.isReceived ? 'Enviada por: ${alert.senderName}' : 'Dispositivo: ${alert.deviceId}',
                        style: TextStyle(color: textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // === DETALLES ===
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fecha y hora
                Row(
                  children: [
                    Icon(Icons.schedule, size: 18, color: textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_formatDate(alert.timestamp),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textTertiary)),
                          Text(_formatFullDate(alert.timestamp),
                            style: TextStyle(fontSize: 12, color: textSecondary)),
                        ],
                      ),
                    ),
                    // Estado
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: alert.acknowledged 
                          ? Colors.green.withOpacity(0.15)
                          : Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: alert.acknowledged ? Colors.green : Colors.orange,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            alert.acknowledged ? Icons.check_circle : Icons.pending,
                            size: 14,
                            color: alert.acknowledged ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            alert.acknowledged ? 'Atendida' : 'Pendiente',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: alert.acknowledged ? Colors.green : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // === MAPA Y UBICACIÓN ===
                if (hasLocation) ...[
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        // Mapa
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                          child: GestureDetector(
                            onTap: () => _showExpandedMap(context, alert.lat!, alert.lng!, alert.typeColor),
                            child: Stack(
                              children: [
                                SizedBox(
                                  height: 150,
                                  width: double.infinity,
                                  child: AbsorbPointer(
                                    child: FlutterMap(
                                      options: MapOptions(
                                        initialCenter: LatLng(alert.lat!, alert.lng!),
                                        initialZoom: 15.0,
                                        interactionOptions: const InteractionOptions(
                                          flags: InteractiveFlag.none, // Solo visual, no interactivo
                                        ),
                                      ),
                                      children: [
                                        TileLayer(
                                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                          userAgentPackageName: 'com.example.wilobu_app',
                                        ),
                                        MarkerLayer(
                                          markers: [
                                            Marker(
                                              point: LatLng(alert.lat!, alert.lng!),
                                              width: 40,
                                              height: 40,
                                              child: Icon(
                                                Icons.location_on,
                                                color: alert.typeColor,
                                                size: 40,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(right: 8, bottom: 8, child: Row(children: [
                                  FloatingActionButton.small(
                                    heroTag: 'alert_full_${alert.id}',
                                    onPressed: () => _showExpandedMap(context, alert.lat!, alert.lng!, alert.typeColor),
                                    child: const Icon(Icons.zoom_out_map, size: 18),
                                  ),
                                  const SizedBox(width: 8),
                                  FloatingActionButton.small(
                                    heroTag: 'alert_gmaps_${alert.id}',
                                    onPressed: () => _openInMaps(alert.lat!, alert.lng!),
                                    child: const Icon(Icons.open_in_new, size: 18),
                                  ),
                                ])),
                              ],
                            ),
                          ),
                        ),
                        // Coordenadas y botones
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.location_on, size: 16, color: alert.typeColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${alert.lat!.toStringAsFixed(6)}, ${alert.lng!.toStringAsFixed(6)}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontFamily: 'monospace',
                                        color: textTertiary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _openInMaps(alert.lat!, alert.lng!),
                                      icon: const Icon(Icons.map, size: 16),
                                      label: const Text('Ver en mapa'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => _getDirections(alert.lat!, alert.lng!),
                                      icon: const Icon(Icons.directions, size: 16),
                                      label: const Text('Cómo llegar'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: alert.typeColor,
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Sin ubicación
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_off, color: Colors.grey.shade500, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Ubicación no disponible',
                            style: TextStyle(color: textSecondary, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // === BOTÓN MARCAR COMO VISTA ===
                if (!alert.acknowledged && alert.isReceived) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _markAsAcknowledged(context, ref),
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text('Marcar como atendida'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

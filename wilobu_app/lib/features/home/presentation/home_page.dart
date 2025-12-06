import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wilobu_app/firebase_providers.dart';
import 'package:wilobu_app/theme/app_theme.dart';
import 'package:wilobu_app/features/contacts/presentation/contacts_page.dart';

class WilobuDevice {
  WilobuDevice({
    required this.id, 
    required this.nombre, 
    required this.estado, 
    required this.bateria,
    this.lastLocation,
    this.lastLocationTimestamp,
  });
  
  final String id; 
  final String nombre; 
  final String estado; 
  final int bateria;
  final GeoPoint? lastLocation;
  final Timestamp? lastLocationTimestamp;
  
  factory WilobuDevice.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final locData = d['lastLocation'] as Map<String, dynamic>?;
    
    return WilobuDevice(
      id: doc.id, 
      nombre: d['name'] ?? 'Wilobu', 
      estado: d['status'] ?? 'Offline', 
      bateria: (d['battery'] as num?)?.toInt() ?? 0,
      lastLocation: locData?['geopoint'] as GeoPoint?,
      lastLocationTimestamp: locData?['timestamp'] as Timestamp?,
    );
  }
}

final userDevicesStreamProvider = StreamProvider.autoDispose((ref) {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) return const Stream.empty();
  return ref.watch(firestoreProvider).collection('users').doc(user.uid).collection('devices')
      .orderBy('createdAt', descending: true).snapshots().map((s) => s.docs.map(WilobuDevice.fromDoc).toList());
});

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(firebaseAuthProvider).currentUser;
    final devicesAsync = ref.watch(userDevicesStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Escuchar cambios de SOS en los dispositivos
    ref.listen(userDevicesStreamProvider, (previous, next) {
      next.whenData((devices) {
        for (final device in devices) {
          if (device.estado.startsWith('sos_')) {
            // Navegar a la pantalla de alerta
            context.push('/sos-alert?deviceId=${device.id}&userId=${user?.uid}');
            break;
          }
        }
      });
    });

    return Scaffold(
      backgroundColor: Colors.transparent, // Para ver fondo global
      appBar: AppBar(
        title: const Text("Wilobu"),
        actions: [
          // Contactos (con badge de solicitudes pendientes)
          Consumer(
            builder: (context, ref, _) {
              final requestsAsync = ref.watch(contactRequestsProvider);
              return requestsAsync.when(
                data: (requests) {
                  final count = requests.length;
                  return IconButton(
                    icon: Badge(
                      isLabelVisible: count > 0,
                      label: Text('$count'),
                      child: const Icon(Icons.people),
                    ),
                    tooltip: 'Contactos',
                    onPressed: () => context.push('/contacts'),
                  );
                },
                loading: () => IconButton(
                  icon: const Icon(Icons.people),
                  onPressed: () => context.push('/contacts'),
                ),
                error: (_, __) => IconButton(
                  icon: const Icon(Icons.people),
                  onPressed: () => context.push('/contacts'),
                ),
              );
            },
          ),
          // Selector de Tema
          PopupMenuButton<AppThemeMode>(
            icon: const Icon(Icons.palette),
            tooltip: 'Cambiar tema',
            onSelected: (mode) {
              ref.read(themeControllerProvider.notifier).setTheme(mode);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: AppThemeMode.light,
                child: Row(
                  children: [
                    Icon(Icons.light_mode, color: Theme.of(context).brightness == Brightness.light ? Colors.blue : null),
                    const SizedBox(width: 12),
                    const Text('Claro'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: AppThemeMode.dark,
                child: Row(
                  children: [
                    Icon(Icons.dark_mode, color: ref.watch(themeControllerProvider) == AppThemeMode.dark ? Colors.blue : null),
                    const SizedBox(width: 12),
                    const Text('Oscuro'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: AppThemeMode.wilobu,
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, color: ref.watch(themeControllerProvider) == AppThemeMode.wilobu ? Colors.blue : null),
                    const SizedBox(width: 12),
                    const Text('Wilobu Theme'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () {
             ref.read(firebaseAuthProvider).signOut(); 
             context.go('/login');
          }),
        ],
      ),
      body: Column(
        children: [
          const Spacer(flex: 1),
          // LOGO CIRCULAR CORRECTO
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? Colors.white30 : Colors.grey.shade300, 
                width: 2
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black26 : Colors.grey.shade400,
                  blurRadius: 20
                )
              ],
              image: const DecorationImage(
                image: AssetImage('assets/images/wilobu_logo.png'),
                fit: BoxFit.cover, // Recorta la imagen cuadrada en el círculo
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text("Hola, ${user?.email?.split('@')[0] ?? 'Usuario'}", 
               style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(flex: 1),
          
          // LISTA
          Expanded(
            flex: 4,
            child: devicesAsync.when(
              data: (devices) {
                if (devices.isEmpty) return _EmptyState();
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: devices.length,
                  separatorBuilder: (_,__) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _DeviceCard(d: devices[i]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e,_) => Center(child: Text("Error: $e")),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/devices/add'),
        label: const Text("Vincular"),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final WilobuDevice d;
  const _DeviceCard({required this.d});
  
  String _getLocationText() {
    if (d.lastLocation == null) return 'Sin ubicación';
    if (d.lastLocationTimestamp == null) return 'Ubicación disponible';
    
    final now = DateTime.now();
    final locTime = d.lastLocationTimestamp!.toDate();
    final diff = now.difference(locTime);
    
    if (diff.inMinutes < 60) {
      return 'Hace ${diff.inMinutes}min';
    } else if (diff.inHours < 24) {
      return 'Hace ${diff.inHours}h';
    } else {
      return 'Hace ${diff.inDays}d';
    }
  }
  
  Color _getBatteryColor() {
    if (d.bateria > 50) return Colors.green;
    if (d.bateria > 20) return Colors.orange;
    return Colors.red;
  }
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.watch, size: 32, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.nombre, 
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600, 
                          color: isDark ? Colors.white : Colors.black87
                        )),
                      Text(d.estado, 
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.grey[600]
                        )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            
            // Batería y Ubicación
            Row(
              children: [
                // Batería
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.battery_charging_full, 
                        size: 20,
                        color: _getBatteryColor(),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${d.bateria}%", 
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Ubicación
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on, 
                        size: 20,
                        color: d.lastLocation != null 
                          ? Colors.blue 
                          : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _getLocationText(), 
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Text("Sin dispositivos", style: Theme.of(context).textTheme.titleMedium)
  );
}
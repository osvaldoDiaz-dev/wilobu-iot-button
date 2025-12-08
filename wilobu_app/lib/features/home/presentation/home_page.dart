import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wilobu_app/firebase_providers.dart';
import 'package:wilobu_app/features/contacts/presentation/contacts_page.dart';
import 'package:wilobu_app/features/contacts/presentation/widgets/contacts_summary_widget.dart';
import 'package:wilobu_app/features/auth/presentation/register_page.dart';
import 'package:wilobu_app/theme/app_theme.dart';

// ===== MODELO DE VIEWER =====
class ViewerDevice {
  final String ownerUid;
  final String ownerName;
  final String deviceId;
  final String? nickname;
  final String status;
  final int? battery;
  final DateTime? lastSeen;
  ViewerDevice({
    required this.ownerUid,
    required this.ownerName,
    required this.deviceId,
    this.nickname,
    required this.status,
    this.battery,
    this.lastSeen,
  });
}

final viewerDevicesProvider = StreamProvider.autoDispose<List<ViewerDevice>>((ref) {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) return const Stream.empty();

  final uid = user.uid;
  final firestore = ref.watch(firestoreProvider);

  return firestore
      .collection('users')
      .doc(uid)
      .snapshots()
      .asyncExpand((userDoc) async* {
        if (!userDoc.exists) {
          yield [];
          return;
        }
        
        final userData = userDoc.data() ?? {};
        final monitoredDevices = List<String>.from(userData['monitored_devices'] ?? []);
        
        if (monitoredDevices.isEmpty) {
          yield [];
          return;
        }
        
        // Obtener mapa de dispositivos -> owners desde system collection
        final deviceMapDoc = await firestore.collection('system').doc('deviceOwnerMap').get();
        final deviceMap = (deviceMapDoc.data()?['map'] as Map<String, dynamic>?) ?? {};
        
        // Agrupar por owner
        final devicesByOwner = <String, List<String>>{};
        
        for (final deviceId in monitoredDevices) {
          final ownerUid = deviceMap[deviceId] as String?;
          if (ownerUid != null) {
            devicesByOwner.putIfAbsent(ownerUid, () => []).add(deviceId);
          }
        }
        
        // Leer cada dispositivo directamente
        final devices = <ViewerDevice>[];
        
        for (final entry in devicesByOwner.entries) {
          final ownerUid = entry.key;
          final deviceIds = entry.value;
          
          for (final deviceId in deviceIds) {
            try {
              final doc = await firestore
                  .collection('users/$ownerUid/devices')
                  .doc(deviceId)
                  .get();
              
              if (!doc.exists) continue;
              
              final data = doc.data()!;
              
              final loc = data['lastLocation'];
              double? lat, lng;

              if (loc is Map<String, dynamic>) {
                final gp = loc['geopoint'];
                if (gp is GeoPoint) {
                  lat = gp.latitude;
                  lng = gp.longitude;
                } else {
                  lat = (loc['lat'] as num?)?.toDouble();
                  lng = (loc['lng'] as num?)?.toDouble();
                }
              }

              final lastSeen = (data['lastSeen'] as Timestamp?)?.toDate() ??
                  (loc is Map<String, dynamic> ? (loc['timestamp'] as Timestamp?)?.toDate() : null);

              // Calcular status real basado en lastSeen
              String status = 'offline';
              if (lastSeen != null) {
                final diff = DateTime.now().difference(lastSeen);
                if (diff.inMinutes < 20) {
                  status = 'online';
                }
              }

              devices.add(ViewerDevice(
                ownerUid: data['ownerUid'] ?? ownerUid,
                ownerName: data['ownerName'] ?? data['ownerEmail'] ?? 'Dueño',
                deviceId: doc.id,
                nickname: data['nickname'] as String?,
                status: status,
                battery: (data['battery'] as num?)?.toInt(),
                lastSeen: lastSeen,
              ));
            } catch (e) {
              print('[viewerDevicesProvider] Error leyendo device $deviceId: $e');
            }
          }
        }
        
        yield devices;
        
        // Stream de actualizaciones
        if (devicesByOwner.isNotEmpty) {
          await for (final _ in Stream.periodic(const Duration(seconds: 10))) {
            final updatedDevices = <ViewerDevice>[];
            
            for (final entry in devicesByOwner.entries) {
              final ownerUid = entry.key;
              final deviceIds = entry.value;
              
              for (final deviceId in deviceIds) {
                try {
                  final doc = await firestore
                      .collection('users/$ownerUid/devices')
                      .doc(deviceId)
                      .get();
                  
                  if (!doc.exists) continue;
                  
                  final data = doc.data()!;
                  
                  final loc = data['lastLocation'];
                  double? lat, lng;

                  if (loc is Map<String, dynamic>) {
                    final gp = loc['geopoint'];
                    if (gp is GeoPoint) {
                      lat = gp.latitude;
                      lng = gp.longitude;
                    } else {
                      lat = (loc['lat'] as num?)?.toDouble();
                      lng = (loc['lng'] as num?)?.toDouble();
                    }
                  }

                  final lastSeen = (data['lastSeen'] as Timestamp?)?.toDate() ??
                      (loc is Map<String, dynamic> ? (loc['timestamp'] as Timestamp?)?.toDate() : null);

                  // Calcular status real basado en lastSeen
                  String status = 'offline';
                  if (lastSeen != null) {
                    final diff = DateTime.now().difference(lastSeen);
                    if (diff.inMinutes < 20) {
                      status = 'online';
                    }
                  }

                  updatedDevices.add(ViewerDevice(
                    ownerUid: data['ownerUid'] ?? ownerUid,
                    ownerName: data['ownerName'] ?? data['ownerEmail'] ?? 'Dueño',
                    deviceId: doc.id,
                    nickname: data['nickname'] as String?,
                    status: status,
                    battery: (data['battery'] as num?)?.toInt(),
                    lastSeen: lastSeen,
                  ));
                } catch (e) {
                  print('[viewerDevicesProvider] Error actualizando: $e');
                }
              }
            }
            
            yield updatedDevices;
          }
        }
      });
});

// Card genérica para dispositivos (viewer o contacto)
class _DeviceListCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? deviceId;
  final bool isOnline;
  final int? battery;
  final DateTime? lastSeen;
  final double? lat;
  final double? lng;

  const _DeviceListCard({
    required this.title,
    required this.subtitle,
    this.deviceId,
    required this.isOnline,
    this.battery,
    this.lastSeen,
    this.lat,
    this.lng,
  });

  @override
  State<_DeviceListCard> createState() => _DeviceListCardState();
}

class _DeviceListCardState extends State<_DeviceListCard> {
  bool _isExpanded = false;

  String _timeAgo(DateTime? dt) {
    if (dt == null) return 'Sin datos';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    return 'Hace ${diff.inDays} dias';
  }

  Future<void> _openInMaps() async {
    if (widget.lat == null || widget.lng == null) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${widget.lat},${widget.lng}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showExpandedMap() async {
    if (widget.lat == null || widget.lng == null) return;
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
                  options: MapOptions(
                    initialCenter: LatLng(widget.lat!, widget.lng!),
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.wilobu_app',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(widget.lat!, widget.lng!),
                        child: const Icon(Icons.location_pin, color: Colors.red, size: 42),
                      ),
                    ]),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('Abrir en Google Maps'),
                        onPressed: _openInMaps,
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = widget.lat != null && widget.lng != null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.isOnline ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.watch,
                  color: widget.isOnline ? Colors.green : Colors.grey, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(widget.subtitle, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
              if (widget.battery != null) Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.battery! < 20 ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(widget.battery! < 20 ? Icons.battery_alert : Icons.battery_full, size: 16,
                    color: widget.battery! < 20 ? Colors.red : Colors.green),
                  const SizedBox(width: 4),
                  Text('${widget.battery}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                    color: widget.battery! < 20 ? Colors.red : Colors.green)),
                ]),
              ),
              const SizedBox(width: 8),
              Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
            ]),
          ),
        ),
        if (_isExpanded) ...[
          const Divider(height: 1),
          if (hasLocation) SizedBox(height: 180, child: Stack(children: [
            FlutterMap(
              options: MapOptions(initialCenter: LatLng(widget.lat!, widget.lng!), initialZoom: 15,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.wilobu_app'),
                MarkerLayer(markers: [Marker(point: LatLng(widget.lat!, widget.lng!),
                  child: const Icon(Icons.location_pin, color: Colors.red, size: 40))]),
              ],
            ),
            Positioned(right: 8, bottom: 8, child: FloatingActionButton.small(
              heroTag: 'map_${widget.deviceId}', onPressed: _openInMaps, child: const Icon(Icons.open_in_new, size: 18))),
          ]))
          else Container(height: 100, color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.location_off, size: 32, color: Colors.grey),
              SizedBox(height: 4),
              Text('Ubicación no disponible', style: TextStyle(color: Colors.grey)),
            ]))),
          Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            if (widget.deviceId != null) ...[
              Row(children: [
                Expanded(child: _InfoTile(icon: Icons.qr_code, label: 'ID', value: widget.deviceId!)),
                Expanded(child: _InfoTile(icon: Icons.access_time, label: 'Última conexión', value: _timeAgo(widget.lastSeen))),
              ]),
            ],
          ])),
        ],
      ]),
    );
  }
}

// ===== MODELO DE DISPOSITIVO =====
class WilobuDevice {
  final String id;
  final String status;
  final String? nickname;
  final double? lat;
  final double? lng;
  final int? battery;
  final DateTime? lastSeen;
  
  // Timeout para considerar offline (5 min para dev, cambiar a 15 para prod)
  static const Duration offlineThreshold = Duration(minutes: 5);

  WilobuDevice({
    required this.id, 
    required this.status, 
    this.nickname,
    this.lat, 
    this.lng, 
    this.battery,
    this.lastSeen,
  });

  factory WilobuDevice.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final loc = d['lastLocation'];
    double? lat, lng;
    
    if (loc is Map<String, dynamic>) {
      final gp = loc['geopoint'];
      if (gp is GeoPoint) {
        lat = gp.latitude;
        lng = gp.longitude;
      } else {
        lat = (loc['lat'] as num?)?.toDouble();
        lng = (loc['lng'] as num?)?.toDouble();
      }
    }
    
    final lastSeenTs = d['lastSeen'] as Timestamp?;
    final locTs = (loc is Map<String, dynamic>) ? loc['timestamp'] as Timestamp? : null;
    final lastSeen = lastSeenTs?.toDate() ?? locTs?.toDate();
    
    // Calcular status real basado en lastSeen
    String status = 'offline';
    if (lastSeen != null) {
      final diff = DateTime.now().difference(lastSeen);
      if (diff < offlineThreshold) {
        status = 'online';
      }
    }
    // Si hay estado SOS, mantenerlo
    final dbStatus = d['status'] as String?;
    if (dbStatus != null && dbStatus.startsWith('sos_')) {
      status = dbStatus;
    }
    
    return WilobuDevice(
      id: doc.id,
      status: status,
      nickname: d['nickname'] as String?,
      lat: lat,
      lng: lng,
      battery: (d['battery'] as num?)?.toInt(),
      lastSeen: lastSeen,
    );
  }

  /// Verifica si el dispositivo está online considerando lastSeen
  bool get isOnline {
    // SOS siempre se considera "activo" (no offline)
    if (isSOS) return true;
    
    // Si status no es online, está offline
    if (status != 'online') return false;
    
    // Si no hay lastSeen, considerarlo offline
    if (lastSeen == null) return false;
    
    // Verificar si ha pasado el threshold desde el último heartbeat
    final timeSinceLastSeen = DateTime.now().difference(lastSeen!);
    return timeSinceLastSeen < offlineThreshold;
  }
  
  bool get isSOS => status.startsWith('sos_');
  String get displayName => nickname ?? id;
  
  String get statusLabel {
    if (isSOS) {
      return switch (status) {
        'sos_general' => 'ALERTA GENERAL',
        'sos_medica' => 'ALERTA MEDICA',
        'sos_seguridad' => 'ALERTA SEGURIDAD',
        _ => status.toUpperCase(),
      };
    }
    
    // Verificar timeout de heartbeat
    if (status == 'online' && !isOnline) {
      return 'Sin señal';
    }
    
    return isOnline ? 'En linea' : 'Desconectado';
  }
}

// ===== MODELO DE CONTACTO QUE TE MONITOREA =====
class MonitoringContact {
  final String uid;
  final String? displayName;
  final String? username;
  final String? email;
  final String deviceId;
  final double? lat;
  final double? lng;
  final int? battery;
  final String status;
  final DateTime? lastSeen;
  
  // Mismo threshold que dispositivos
  static const Duration offlineThreshold = Duration(minutes: 5);

  MonitoringContact({
    required this.uid,
    this.displayName,
    this.username,
    this.email,
    required this.deviceId,
    this.lat,
    this.lng,
    this.battery,
    required this.status,
    this.lastSeen,
  });

  bool get isSOS => status.startsWith('sos_');
  
  bool get isOnline {
    if (isSOS) return true;
    if (status != 'online') return false;
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen!) < offlineThreshold;
  }
  
  String get formattedName => displayName ?? email?.split('@')[0] ?? 'Usuario';
  String get formattedUsername {
    if (username != null && username!.isNotEmpty) return '@$username';
    if (email != null) return '@${email!.split('@')[0]}';
    return '';
  }
}

// ===== PROVIDERS =====
final devicesProvider = StreamProvider.autoDispose<List<WilobuDevice>>((ref) {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) return const Stream.empty();
  return ref.watch(firestoreProvider)
    .collection('users').doc(user.uid).collection('devices')
    .snapshots()
    .map((s) => s.docs.map(WilobuDevice.fromDoc).toList());
});

final monitoringContactsProvider = StreamProvider.autoDispose<List<MonitoringContact>>((ref) {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) return const Stream.empty();
  final firestore = ref.watch(firestoreProvider);
  
  // No podemos usar collectionGroup con emergencyContacts porque es un array de objetos
  // En su lugar, retornamos lista vacía por ahora
  // TODO: Implementar índice emergencyContactUids: [uid1, uid2] en dispositivos
  return Stream.value(<MonitoringContact>[]);
});

// ===== PAGINA PRINCIPAL =====
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late GlobalKey<ScaffoldState> _scaffoldKey;

  @override
  void initState() {
    super.initState();
    _scaffoldKey = GlobalKey<ScaffoldState>();
    // Mostrar mensaje de bienvenida si es nuevo registro
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final justRegistered = ref.read(justRegisteredProvider);
      if (justRegistered) {
        ref.read(justRegisteredProvider.notifier).state = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Cuenta creada exitosamente! Bienvenido a Wilobu'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(firebaseAuthProvider).currentUser;
    final devices = ref.watch(devicesProvider);
    final themeMode = ref.watch(themeControllerProvider);
    final background = AppTheme.buildWilobuBackground(themeMode);

    ref.listen(devicesProvider, (_, next) {
      next.whenData((list) {
        final sos = list.where((d) => d.isSOS).firstOrNull;
        if (sos != null) context.push('/sos-alert?deviceId=${sos.id}&userId=${user?.uid}');
      });
    });

    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: background != null,
      appBar: AppBar(
        title: const Text('Wilobu'),
        backgroundColor: background != null ? Colors.transparent : null,
        elevation: 0,
        actions: [
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.build),
              tooltip: 'Reparar enlaces',
              onPressed: () async {
                try {
                  await FirebaseFunctions.instance
                      .httpsCallable('migrateDevicesFields')
                      .call();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Migración ejecutada')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
            ),
          Consumer(builder: (_, ref, __) {
            final theme = ref.watch(themeControllerProvider);
            final icon = switch (theme) {
              AppThemeMode.light => Icons.light_mode,
              AppThemeMode.dark => Icons.dark_mode,
              AppThemeMode.wilobu => Icons.auto_awesome,
            };
            return IconButton(
              icon: Icon(icon),
              tooltip: 'Tema',
              onPressed: () => ref.read(themeControllerProvider.notifier).cycleTheme(),
            );
          }),
          IconButton(icon: const Icon(Icons.notifications), tooltip: 'Alertas', onPressed: () => context.push('/alerts')),
          Consumer(builder: (_, ref, __) {
            final requests = ref.watch(contactRequestsProvider);
            return IconButton(
              icon: Badge(
                isLabelVisible: requests.valueOrNull?.isNotEmpty ?? false,
                label: Text('${requests.valueOrNull?.length ?? 0}'),
                child: const Icon(Icons.menu),
              ),
              tooltip: 'Menú',
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            );
          }),
        ],
      ),
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.account_circle,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.email ?? 'Usuario',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
              title: const Text('Mi Perfil'),
              onTap: () { Navigator.pop(context); context.push('/profile'); },
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(height: 4),
            Consumer(builder: (_, ref, __) {
              final requests = ref.watch(contactRequestsProvider);
              final count = requests.valueOrNull?.length ?? 0;
              return ListTile(
                leading: Icon(Icons.people, color: Theme.of(context).colorScheme.primary),
                title: const Text('Contactos'),
                trailing: count > 0 ? Badge(
                  label: Text('$count'),
                  backgroundColor: Colors.red,
                  child: const SizedBox.shrink(),
                ) : null,
                onTap: () { Navigator.pop(context); context.push('/contacts'); },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                visualDensity: VisualDensity.compact,
              );
            }),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
              onTap: () { 
                Navigator.pop(context);
                ref.read(firebaseAuthProvider).signOut();
                context.go('/login');
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/devices/add'),
        icon: const Icon(Icons.add),
        label: const Text('Vincular'),
      ),
      body: Stack(
        children: [
          if (background != null) background,
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () async { ref.invalidate(devicesProvider); ref.invalidate(monitoringContactsProvider); },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Estadísticas rápidas
                Consumer(builder: (context, ref, _) {
              final myDevices = ref.watch(devicesProvider);
              final viewers = ref.watch(viewerDevicesProvider);
              final contacts = ref.watch(monitoringContactsProvider);
              
              return Row(
                children: [
                  Expanded(
                    child: _StatsCard(
                      icon: Icons.watch,
                      label: 'Mis dispositivos',
                      count: myDevices.valueOrNull?.length ?? 0,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatsCard(
                      icon: Icons.visibility,
                      label: 'Monitoreando',
                      count: (contacts.valueOrNull?.length ?? 0) + (viewers.valueOrNull?.length ?? 0),
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 24),
            _SectionHeader(icon: Icons.watch, title: 'Mi Dispositivo'),
            const SizedBox(height: 8),
            devices.when(
              data: (list) => list.isEmpty
                ? _EmptyState(icon: Icons.watch_off, message: 'No tienes un Wilobu vinculado',
                    action: ElevatedButton.icon(onPressed: () => context.push('/devices/add'),
                      icon: const Icon(Icons.add), label: const Text('Vincular Wilobu')))
                : Column(children: list.map((d) => _MyDeviceCard(device: d)).toList()),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
            const SizedBox(height: 24),
            _SectionHeader(icon: Icons.visibility, title: 'Otros Dispositivos', subtitle: 'Dispositivos que puedes monitorear'),
            const SizedBox(height: 8),
            Consumer(builder: (context, ref, _) {
              final viewers = ref.watch(viewerDevicesProvider);
              final contacts = ref.watch(monitoringContactsProvider);
              return viewers.when(
                data: (viewerList) => contacts.when(
                  data: (contactList) {
                    final allDevices = [
                      ...viewerList.map((v) => _DeviceListCard(
                        title: v.nickname ?? v.deviceId,
                        subtitle: 'Dueño: ${v.ownerName}',
                        deviceId: v.deviceId,
                        isOnline: v.status == 'online',
                        battery: v.battery,
                        lastSeen: v.lastSeen,
                      )),
                      ...contactList.map((c) => _DeviceListCard(
                        title: c.formattedName,
                        subtitle: c.formattedUsername,
                        deviceId: c.deviceId,
                        isOnline: c.isOnline,
                        battery: c.battery,
                        lastSeen: c.lastSeen,
                        lat: c.lat,
                        lng: c.lng,
                      )),
                    ];
                    return allDevices.isEmpty
                      ? _EmptyState(
                          icon: Icons.visibility_off,
                          message: 'No tienes acceso a otros dispositivos',
                          action: OutlinedButton.icon(
                            onPressed: () => context.push('/contacts'),
                            icon: const Icon(Icons.person_add),
                            label: const Text('Gestionar contactos'),
                          ),
                        )
                      : Column(children: allDevices);
                  },
                  loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
                loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Center(child: Text('Error: $e')),
              );
            }),
            const SizedBox(height: 24),
            // ===== NUEVA SECCIÓN: MIS CONTACTOS EN EL DASHBOARD =====
            const MyContactsSummaryWidget(),
          ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;

  const _StatsCard({
    required this.icon,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 28),
            const SizedBox(height: 12),
            Text(
              count.toString(),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon; final String title; final String? subtitle;
  const _SectionHeader({required this.icon, required this.title, this.subtitle});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      Icon(icon, color: theme.colorScheme.primary, size: 24),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.6))),
      ])),
    ]);
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon; final String message; final Widget? action;
  const _EmptyState({required this.icon, required this.message, this.action});
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(32),
    child: Column(children: [
      Icon(icon, size: 48, color: Colors.grey),
      const SizedBox(height: 12),
      Text(message, style: const TextStyle(color: Colors.grey)),
      if (action != null) ...[const SizedBox(height: 16), action!],
    ])));
}

class _MyDeviceCard extends ConsumerStatefulWidget {
  final WilobuDevice device;
  const _MyDeviceCard({required this.device});
  @override ConsumerState<_MyDeviceCard> createState() => _MyDeviceCardState();
}

class _MyDeviceCardState extends ConsumerState<_MyDeviceCard> {
  bool _isExpanded = false;
  String _timeAgo(DateTime? dt) {
    if (dt == null) return 'Sin datos';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    return 'Hace ${diff.inDays} dias';
  }

  Future<void> _showNicknameDialog() async {
    final controller = TextEditingController(text: widget.device.nickname);
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Asignar apodo'),
      content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Apodo', hintText: 'Ej: Mi Wilobu'), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Guardar')),
      ],
    ));
    if (result != null && mounted) {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user != null) {
        await ref.read(firestoreProvider).collection('users').doc(user.uid)
          .collection('devices').doc(widget.device.id)
          .update({'nickname': result.isEmpty ? FieldValue.delete() : result});
      }
    }
  }

  Future<void> _confirmUnlink() async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Desvincular dispositivo?'),
      content: const Text('El dispositivo se reiniciara a configuracion de fabrica y deberas vincularlo nuevamente via Bluetooth.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true), child: const Text('Desvincular')),
      ],
    ));
    if (confirmed == true && mounted) {
      try {
        final user = ref.read(firebaseAuthProvider).currentUser;
        if (user == null) return;
        
        final deviceDoc = ref.read(firestoreProvider)
            .collection('users')
            .doc(user.uid)
            .collection('devices')
            .doc(widget.device.id);
        
        // Marcar cmd_reset y dejar el documento para que el backend responda 410 al firmware
        await deviceDoc.set({
          'cmd_reset': true,
          'provisioned': false,
          'reset_requested_at': FieldValue.serverTimestamp(),
          'status': 'offline',
        }, SetOptions(merge: true));
        
        // Esperar a que el firmware reciba el comando
        await Future.delayed(const Duration(seconds: 3));

        // Borrar el documento para que desaparezca del dashboard (el backend ya enviará 410 si el heartbeat llegó antes)
        await deviceDoc.delete();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Dispositivo desvinculado correctamente'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al desvincular: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _openInMaps() async {
    if (widget.device.lat == null || widget.device.lng == null) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${widget.device.lat},${widget.device.lng}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showExpandedMap() async {
    if (widget.device.lat == null || widget.device.lng == null) return;
    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 420,
            child: Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(widget.device.lat!, widget.device.lng!),
                      initialZoom: 16,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.wilobu_app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(widget.device.lat!, widget.device.lng!),
                            width: 50,
                            height: 50,
                            child: const Icon(Icons.location_on, color: Colors.red, size: 50),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Column(
                    children: [
                      FloatingActionButton(
                        heroTag: 'mydevice_expand_${widget.device.id}',
                        mini: true,
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Icon(Icons.fullscreen_exit),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton(
                        heroTag: 'mydevice_maps_${widget.device.id}',
                        mini: true,
                        onPressed: () async {
                          final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${widget.device.lat},${widget.device.lng}');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: const Icon(Icons.open_in_new),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final hasLocation = device.lat != null && device.lng != null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: device.isSOS ? Colors.red.withOpacity(0.1) : null,
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: device.isSOS ? Colors.red.withOpacity(0.2) : (device.isOnline ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(device.isSOS ? Icons.warning : Icons.watch,
                color: device.isSOS ? Colors.red : (device.isOnline ? Colors.green : Colors.grey), size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (device.nickname != null && device.nickname!.isNotEmpty) ...[
                Text(device.nickname!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(device.id, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              ] else
                Text(device.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle,
                  color: device.isSOS ? Colors.red : (device.isOnline ? Colors.green : Colors.grey))),
                const SizedBox(width: 6),
                Text(device.statusLabel, style: TextStyle(
                  color: device.isSOS ? Colors.red : (device.isOnline ? Colors.green : Colors.grey),
                  fontSize: 13, fontWeight: device.isSOS ? FontWeight.bold : FontWeight.normal)),
              ]),
            ])),
            if (device.battery != null) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: device.battery! < 20 ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(device.battery! < 20 ? Icons.battery_alert : Icons.battery_full, size: 16,
                  color: device.battery! < 20 ? Colors.red : Colors.green),
                const SizedBox(width: 4),
                Text('${device.battery}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                  color: device.battery! < 20 ? Colors.red : Colors.green)),
              ]),
            ),
            const SizedBox(width: 8),
            Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
          ])),
        ),
        if (_isExpanded) ...[
          const Divider(height: 1),
          if (hasLocation) SizedBox(height: 180, child: Stack(children: [
            GestureDetector(
              onTap: _showExpandedMap,
              child: AbsorbPointer(
                child: FlutterMap(
                  options: MapOptions(initialCenter: LatLng(device.lat!, device.lng!), initialZoom: 15,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.wilobu_app'),
                    MarkerLayer(markers: [Marker(point: LatLng(device.lat!, device.lng!),
                      child: const Icon(Icons.location_pin, color: Colors.red, size: 40))]),
                  ],
                ),
              ),
            ),
            Positioned(right: 8, bottom: 8, child: Row(children: [
              FloatingActionButton.small(
                heroTag: 'map_full_${device.id}',
                onPressed: _showExpandedMap,
                child: const Icon(Icons.zoom_out_map, size: 18)),
              const SizedBox(width: 8),
              FloatingActionButton.small(
                heroTag: 'map_open_${device.id}',
                onPressed: _openInMaps,
                child: const Icon(Icons.open_in_new, size: 18)),
            ])),
          ]))
          else Container(height: 100, color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.location_off, size: 32, color: Colors.grey),
              SizedBox(height: 4),
              Text('Ubicacion no disponible', style: TextStyle(color: Colors.grey)),
            ]))),
          Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            Row(children: [
              Expanded(child: _InfoTile(icon: Icons.qr_code, label: 'ID', value: device.id)),
              Expanded(child: _InfoTile(icon: Icons.access_time, label: 'Ultima conexion', value: _timeAgo(device.lastSeen))),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _showNicknameDialog,
                icon: const Icon(Icons.edit, size: 18), label: const Text('Apodo'))),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton.icon(onPressed: _confirmUnlink,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                icon: const Icon(Icons.link_off, size: 18), label: const Text('Desvincular'))),
            ]),
          ])),
        ],
      ]),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon; final String label; final String value;
  const _InfoTile({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 18, color: Colors.grey),
    const SizedBox(width: 8),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
    ])),
  ]);
}

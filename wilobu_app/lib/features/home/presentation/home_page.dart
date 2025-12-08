import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wilobu_app/firebase_providers.dart';
import 'package:wilobu_app/features/contacts/presentation/contacts_page.dart';
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
  final firestore = ref.watch(firestoreProvider);
  return firestore.collectionGroup('devices').snapshots().map((snapshot) {
    final result = <ViewerDevice>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final viewers = data['viewers'] as List<dynamic>?;
      if (viewers == null) continue;
      final isViewer = viewers.any((v) => v is Map && v['uid'] == user.uid);
      if (!isViewer) continue;
      final ownerUid = data['ownerUid'] as String? ?? '';
      final ownerName = data['ownerName'] as String? ?? 'Usuario';
      result.add(ViewerDevice(
        ownerUid: ownerUid,
        ownerName: ownerName,
        deviceId: doc.id,
        nickname: data['nickname'] as String?,
        status: data['status'] ?? 'offline',
        battery: (data['battery'] as num?)?.toInt(),
        lastSeen: (data['lastSeen'] is Timestamp) ? (data['lastSeen'] as Timestamp).toDate() : null,
      ));
    }
    return result;
  });
});

// ...existing code...

class _ViewerDeviceCard extends StatelessWidget {
  final ViewerDevice device;
  const _ViewerDeviceCard({required this.device});
  String _timeAgo(DateTime? dt) {
    if (dt == null) return 'Sin datos';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    return 'Hace ${diff.inDays} dias';
  }
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.visibility, color: Colors.blue),
        title: Text(device.nickname ?? device.deviceId, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Dueño: ${device.ownerName}\nEstado: ${device.status}\nÚltima conexión: ${_timeAgo(device.lastSeen)}'),
        trailing: device.battery != null ? Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(device.battery! < 20 ? Icons.battery_alert : Icons.battery_full, size: 16,
            color: device.battery! < 20 ? Colors.red : Colors.green),
          const SizedBox(width: 4),
          Text('${device.battery}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
            color: device.battery! < 20 ? Colors.red : Colors.green)),
        ]) : null,
      ),
    );
  }
}
// ===== MODELO DE VIEWER =====
// ...existing code...
// ...existing code...

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
    
    return WilobuDevice(
      id: doc.id,
      status: d['status'] ?? 'offline',
      nickname: d['nickname'] as String?,
      lat: lat,
      lng: lng,
      battery: (d['battery'] as num?)?.toInt(),
      lastSeen: lastSeenTs?.toDate() ?? locTs?.toDate(),
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
  return firestore.collectionGroup('devices').snapshots().asyncMap((snapshot) async {
    final contacts = <MonitoringContact>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final ownerUid = data['ownerUid'] as String?;
      if (ownerUid == null || ownerUid == user.uid) continue;
      final emergencyContacts = data['emergencyContacts'] as List<dynamic>? ?? [];
      final isContact = emergencyContacts.any((c) => c is Map && c['uid'] == user.uid);
      if (!isContact) continue;
      final ownerDoc = await firestore.collection('users').doc(ownerUid).get();
      final ownerData = ownerDoc.data() ?? {};
      final loc = data['lastLocation'];
      double? lat, lng;
      if (loc is Map<String, dynamic>) {
        final gp = loc['geopoint'];
        if (gp is GeoPoint) { lat = gp.latitude; lng = gp.longitude; }
      }
      contacts.add(MonitoringContact(
        uid: ownerUid, displayName: ownerData['name'] as String?,
        username: ownerData['username'] as String?, email: ownerData['email'] as String?,
        deviceId: doc.id, lat: lat, lng: lng,
        battery: (data['battery'] as num?)?.toInt(),
        status: data['status'] ?? 'offline',
        lastSeen: (data['lastSeen'] as Timestamp?)?.toDate(),
      ));
    }
    return contacts;
  });
});

// ===== PAGINA PRINCIPAL =====
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
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
    final contacts = ref.watch(monitoringContactsProvider);
    final viewerDevices = ref.watch(viewerDevicesProvider);

    ref.listen(devicesProvider, (_, next) {
      next.whenData((list) {
        final sos = list.where((d) => d.isSOS).firstOrNull;
        if (sos != null) context.push('/sos-alert?deviceId=${sos.id}&userId=${user?.uid}');
      });
    });

    return WilobuScaffold(
      appBar: AppBar(
        title: const Text('Wilobu'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Consumer(builder: (_, ref, __) {
            final theme = ref.watch(themeControllerProvider);
            final icon = switch (theme) {
              AppThemeMode.light => Icons.light_mode,
              AppThemeMode.dark => Icons.dark_mode,
              AppThemeMode.wilobu => Icons.auto_awesome,
            };
            return IconButton(
              icon: Icon(icon),
              tooltip: 'Tema: ${theme.name}',
              onPressed: () => ref.read(themeControllerProvider.notifier).cycleTheme(),
            );
          }),
          IconButton(icon: const Icon(Icons.notifications), onPressed: () => context.push('/alerts')),
          Consumer(builder: (_, ref, __) {
            final requests = ref.watch(contactRequestsProvider);
            return IconButton(
              icon: Badge(
                isLabelVisible: requests.valueOrNull?.isNotEmpty ?? false,
                label: Text('${requests.valueOrNull?.length ?? 0}'),
                child: const Icon(Icons.person_add),
              ),
              onPressed: () => context.push('/contacts'),
            );
          }),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () { ref.read(firebaseAuthProvider).signOut(); context.go('/login'); },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/devices/add'),
        icon: const Icon(Icons.add),
        label: const Text('Vincular'),
      ),
      body: RefreshIndicator(
        onRefresh: () async { ref.invalidate(devicesProvider); ref.invalidate(monitoringContactsProvider); },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
            _SectionHeader(icon: Icons.visibility, title: 'Tienes acceso como viewer', subtitle: 'Dispositivos que puedes ver pero no controlar'),
            const SizedBox(height: 8),
            viewerDevices.when(
              data: (list) => list.isEmpty
                ? _EmptyState(icon: Icons.visibility_off, message: 'No tienes acceso como viewer a ningún dispositivo')
                : Column(children: list.map((v) => _ViewerDeviceCard(device: v)).toList()),
              loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
            const SizedBox(height: 24),
            _SectionHeader(icon: Icons.people, title: 'Tus Contactos', subtitle: 'Usuarios que te tienen como contacto de emergencia'),
            const SizedBox(height: 8),
            contacts.when(
              data: (list) => list.isEmpty
                ? _EmptyState(
                    icon: Icons.people_outline, 
                    message: 'Nadie te ha agregado como contacto aun',
                    action: OutlinedButton.icon(
                      onPressed: () => context.push('/contacts'),
                      icon: const Icon(Icons.person_add),
                      label: const Text('Gestionar contactos'),
                    ),
                  )
                : Column(children: list.map((c) => _ContactDeviceCard(contact: c)).toList()),
              loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Center(child: Text('Error: $e')),
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
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user != null) {
        // Enviar comando de reset al firmware antes de borrar
        await ref.read(firestoreProvider).collection('users').doc(user.uid)
          .collection('devices').doc(widget.device.id).update({'cmd_reset': true});
        // Esperar un momento para que el heartbeat lo lea
        await Future.delayed(const Duration(seconds: 1));
        // Borrar el documento
        await ref.read(firestoreProvider).collection('users').doc(user.uid)
          .collection('devices').doc(widget.device.id).delete();
      }
    }
  }

  Future<void> _openInMaps() async {
    if (widget.device.lat == null || widget.device.lng == null) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${widget.device.lat},${widget.device.lng}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
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
            FlutterMap(
              options: MapOptions(initialCenter: LatLng(device.lat!, device.lng!), initialZoom: 15,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.wilobu_app'),
                MarkerLayer(markers: [Marker(point: LatLng(device.lat!, device.lng!),
                  child: const Icon(Icons.location_pin, color: Colors.red, size: 40))]),
              ],
            ),
            Positioned(right: 8, bottom: 8, child: FloatingActionButton.small(
              heroTag: 'map_${device.id}', onPressed: _openInMaps, child: const Icon(Icons.open_in_new, size: 18))),
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

// ===== WIDGET COMPARTIDO PARA DISPOSITIVOS =====
class _ContactDeviceCard extends StatefulWidget {
  final MonitoringContact contact;
  const _ContactDeviceCard({required this.contact});
  @override State<_ContactDeviceCard> createState() => _ContactDeviceCardState();
}

class _ContactDeviceCardState extends State<_ContactDeviceCard> {
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
    if (widget.contact.lat == null || widget.contact.lng == null) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${widget.contact.lat},${widget.contact.lng}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    final hasLocation = contact.lat != null && contact.lng != null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSOS = contact.isSOS;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSOS ? Colors.red.withOpacity(0.1) : null,
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSOS ? Colors.red.withOpacity(0.2) : (contact.isOnline ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(isSOS ? Icons.warning : Icons.watch,
                color: isSOS ? Colors.red : (contact.isOnline ? Colors.green : Colors.grey), size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(contact.formattedName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              if (contact.formattedUsername.isNotEmpty)
                Text(contact.formattedUsername, style: TextStyle(color: theme.colorScheme.primary, fontSize: 12)),
              const SizedBox(height: 4),
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle,
                  color: isSOS ? Colors.red : (contact.isOnline ? Colors.green : Colors.grey))),
                const SizedBox(width: 6),
                Text(isSOS ? 'ALERTA SOS' : (contact.isOnline ? 'En linea' : 'Desconectado'), style: TextStyle(
                  color: isSOS ? Colors.red : (contact.isOnline ? Colors.green : Colors.grey),
                  fontSize: 13, fontWeight: isSOS ? FontWeight.bold : FontWeight.normal)),
              ]),
            ])),
            if (contact.battery != null) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: contact.battery! < 20 ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(contact.battery! < 20 ? Icons.battery_alert : Icons.battery_full, size: 16,
                  color: contact.battery! < 20 ? Colors.red : Colors.green),
                const SizedBox(width: 4),
                Text('${contact.battery}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                  color: contact.battery! < 20 ? Colors.red : Colors.green)),
              ]),
            ),
            const SizedBox(width: 8),
            Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
          ])),
        ),
        if (_isExpanded) ...[
          const Divider(height: 1),
          if (hasLocation) SizedBox(height: 180, child: Stack(children: [
            FlutterMap(
              options: MapOptions(initialCenter: LatLng(contact.lat!, contact.lng!), initialZoom: 15,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.wilobu_app'),
                MarkerLayer(markers: [Marker(point: LatLng(contact.lat!, contact.lng!),
                  child: const Icon(Icons.location_pin, color: Colors.red, size: 40))]),
              ],
            ),
            Positioned(right: 8, bottom: 8, child: FloatingActionButton.small(
              heroTag: 'map_contact_${contact.deviceId}', onPressed: _openInMaps, child: const Icon(Icons.open_in_new, size: 18))),
          ]))
          else Container(height: 100, color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.location_off, size: 32, color: Colors.grey),
              SizedBox(height: 4),
              Text('Ubicacion no disponible', style: TextStyle(color: Colors.grey)),
            ]))),
          Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            Expanded(child: _InfoTile(icon: Icons.watch, label: 'Dispositivo', value: contact.deviceId)),
            Expanded(child: _InfoTile(icon: Icons.access_time, label: 'Ultima conexion', value: _timeAgo(contact.lastSeen))),
          ])),
        ],
      ]),
    );
  }
}

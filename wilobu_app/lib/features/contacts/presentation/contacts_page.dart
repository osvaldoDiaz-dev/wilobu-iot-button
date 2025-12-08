import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wilobu_app/firebase_providers.dart';
import 'package:wilobu_app/theme/app_theme.dart';
import 'dart:async';

// ============================================================================
// MODELOS
// ============================================================================

class ContactRequest {
  final String id;
  final String fromUid;
  final String fromName;
  final String fromEmail;
  final String deviceId;
  final String deviceName;
  final Timestamp timestamp;

  ContactRequest({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.fromEmail,
    required this.deviceId,
    required this.deviceName,
    required this.timestamp,
  });

  factory ContactRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return ContactRequest(
      id: doc.id,
      fromUid: data['fromUid'] ?? '',
      fromName: data['fromName'] ?? 'Usuario',
      fromEmail: data['fromEmail'] ?? '',
      deviceId: data['deviceId'] ?? '',
      deviceName: data['deviceName'] ?? 'Wilobu',
      timestamp: data['timestamp'] ?? Timestamp.now(),
    );
  }
}

class EmergencyContact {
  final String uid;
  final String name;

  EmergencyContact({
    required this.uid,
    required this.name,
  });

  Map<String, dynamic> toMap() => {'uid': uid, 'name': name};
}

// ============================================================================
// PROVIDERS
// ============================================================================

final contactRequestsProvider = StreamProvider.autoDispose<List<ContactRequest>>((ref) {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) return const Stream.empty();
  
  return ref.watch(firestoreProvider)
      .collection('users/${user.uid}/contactRequests')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((s) => s.docs.map(ContactRequest.fromDoc).toList());
});

final addContactProvider = FutureProvider.autoDispose.family<void, Map<String, dynamic>>((ref, params) async {
  final firestore = ref.read(firestoreProvider);
  final auth = ref.read(firebaseAuthProvider);
  final user = auth.currentUser;
  if (user == null) throw Exception('Usuario no autenticado');

  final contactUid = params['contactUid'] as String;
  final deviceId = params['deviceId'] as String;

  // Obtener nombre del dispositivo
  final deviceDoc = await firestore.collection('users/${user.uid}/devices').doc(deviceId).get();
  final deviceName = deviceDoc.data()?['name'] ?? 'Wilobu';

  // Crear solicitud en la subcollection del contacto
  await firestore.collection('users/$contactUid/contactRequests').add({
    'fromUid': user.uid,
    'fromName': user.displayName ?? user.email ?? 'Usuario',
    'fromEmail': user.email ?? '',
    'deviceId': deviceId,
    'deviceName': deviceName,
    'timestamp': FieldValue.serverTimestamp(),
  });
});

// ============================================================================
// UI
// ============================================================================

class ContactsPage extends ConsumerStatefulWidget {
  const ContactsPage({super.key});

  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(contactRequestsProvider);
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeControllerProvider);
    final background = AppTheme.buildWilobuBackground(themeMode);

    return Scaffold(
      extendBodyBehindAppBar: background != null,
      appBar: AppBar(
        title: const Text('Contactos'),
        elevation: 0,
        backgroundColor: background != null ? Colors.transparent : null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            decoration: BoxDecoration(
              color: background != null 
                  ? Colors.black.withOpacity(0.3)
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.primaryContainer,
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: theme.colorScheme.onPrimaryContainer,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              tabs: [
                const Tab(icon: Icon(Icons.people_outline), text: 'Contactos'),
                Consumer(builder: (_, ref, __) {
                  final requests = ref.watch(contactRequestsProvider);
                  final count = requests.valueOrNull?.length ?? 0;
                  return Tab(
                    icon: Badge(
                      isLabelVisible: count > 0,
                      label: Text('$count'),
                      child: const Icon(Icons.inbox_outlined),
                    ),
                    text: 'Solicitudes',
                  );
                }),
                const Tab(icon: Icon(Icons.person_add_outlined), text: 'Añadir'),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          if (background != null) background,
          SafeArea(
            child: TabBarView(
              controller: _tabController,
              children: [
                const _MyContactsTab(),
                _RequestsTab(requestsAsync: requestsAsync),
                const _AddContactTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 1: MIS CONTACTOS DE EMERGENCIA
// ============================================================================

/// Provider para obtener todos los contactos de emergencia de mis dispositivos
final myEmergencyContactsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) return const Stream.empty();
  
  return ref.watch(firestoreProvider)
      .collection('users/${user.uid}/devices')
      .snapshots()
      .asyncMap((devicesSnapshot) async {
        final contacts = <Map<String, dynamic>>[];
        final firestore = ref.read(firestoreProvider);
        
        for (final deviceDoc in devicesSnapshot.docs) {
          final deviceData = deviceDoc.data();
          final deviceName = deviceData['nickname'] ?? deviceDoc.id;
          final emergencyContacts = deviceData['emergencyContacts'] as List<dynamic>? ?? [];
          
          for (final contact in emergencyContacts) {
            if (contact is Map<String, dynamic>) {
              final contactUid = contact['uid'] as String?;
              if (contactUid == null) continue;
              
              // Obtener info actualizada del usuario
              final userDoc = await firestore.collection('users').doc(contactUid).get();
              final userData = userDoc.data() ?? {};
              
              contacts.add({
                'uid': contactUid,
                'name': contact['name'] ?? userData['name'] ?? 'Usuario',
                'email': userData['email'] ?? '',
                'deviceId': deviceDoc.id,
                'deviceName': deviceName,
              });
            }
          }
        }
        
        return contacts;
      });
});

class _MyContactsTab extends ConsumerWidget {
  const _MyContactsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(myEmergencyContactsProvider);
    final theme = Theme.of(context);
    
    return contactsAsync.when(
      data: (contacts) {
        if (contacts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                    ),
                    child: Icon(
                      Icons.people_outline, 
                      size: 80, 
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Sin contactos', 
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Añade contactos de emergencia para que puedan ver tu ubicación',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        
        // Agrupar por dispositivo
        final byDevice = <String, List<Map<String, dynamic>>>{};
        for (final c in contacts) {
          final deviceId = c['deviceId'] as String;
          byDevice.putIfAbsent(deviceId, () => []).add(c);
        }
        
        return ListView(
          padding: const EdgeInsets.all(16),
          children: byDevice.entries.map((entry) {
            if (entry.value.isEmpty) return const SizedBox.shrink();
            final deviceName = entry.value.first['deviceName'];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.watch, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        deviceName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                ...entry.value.map((contact) => _EmergencyContactCard(
                  contact: contact,
                  deviceId: entry.key,
                )),
                const SizedBox(height: 16),
              ],
            );
          }).toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 60, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Error al cargar contactos', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('$e', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _EmergencyContactCard extends ConsumerStatefulWidget {
  const _EmergencyContactCard({required this.contact, required this.deviceId});
  
  final Map<String, dynamic> contact;
  final String deviceId;

  @override
  ConsumerState<_EmergencyContactCard> createState() => _EmergencyContactCardState();
}

class _EmergencyContactCardState extends ConsumerState<_EmergencyContactCard> {
  bool _removing = false;

  Future<void> _removeContact() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar contacto?'),
        content: Text('${widget.contact['name']} ya no podrá ver tu ubicación ni recibir alertas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _removing = true);
    
    try {
      final firestore = ref.read(firestoreProvider);
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      if (user == null) throw Exception('No autenticado');
      
      // Obtener contactos actuales
      final deviceDoc = await firestore.collection('users/${user.uid}/devices').doc(widget.deviceId).get();
      final contacts = (deviceDoc.data()?['emergencyContacts'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      
      // Filtrar el contacto a eliminar
      final updatedContacts = contacts.where((c) => c['uid'] != widget.contact['uid']).toList();
      
      await deviceDoc.reference.update({'emergencyContacts': updatedContacts});
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contacto eliminado'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            (widget.contact['name'] as String? ?? '').isEmpty ? 'U' : (widget.contact['name'] as String).substring(0, 1).toUpperCase(),
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(widget.contact['name'] ?? 'Sin nombre', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(widget.contact['email'] ?? '', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        trailing: _removing
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                onPressed: _removeContact,
                tooltip: 'Eliminar contacto',
              ),
      ),
    );
  }
}

// ============================================================================
// TAB 2: SOLICITUDES
// ============================================================================

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab({required this.requestsAsync});
  
  final AsyncValue<List<ContactRequest>> requestsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    
    return requestsAsync.when(
      data: (requests) {
        if (requests.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                    ),
                    child: Icon(
                      Icons.inbox_outlined, 
                      size: 80, 
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Sin solicitudes', 
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Las solicitudes de contacto aparecerán aquí',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) => _RequestCard(request: requests[index]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 60, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Error al cargar solicitudes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('$e', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({required this.request});
  
  final ContactRequest request;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _processing = false;

  Future<void> _acceptRequest() async {
    if (_processing) return;
    setState(() => _processing = true);

    try {
      final firestore = ref.read(firestoreProvider);
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      if (user == null) throw Exception('No autenticado');

      // 1. Añadir contacto al dispositivo del solicitante
      final deviceRef = firestore.collection('users/${widget.request.fromUid}/devices').doc(widget.request.deviceId);
      
      await deviceRef.update({
        'emergencyContacts': FieldValue.arrayUnion([
          {
            'uid': user.uid,
            'name': user.displayName ?? user.email ?? 'Usuario',
          }
        ]),
        // Agregar viewerUids para que pueda ver el dispositivo
        'viewerUids': FieldValue.arrayUnion([user.uid]),
      });

      // 2. Agregar deviceId del owner a monitored_devices del viewer
      await firestore.collection('users').doc(user.uid).update({
        'monitored_devices': FieldValue.arrayUnion([deviceRef.id]),
      });

      // 3. RELACIÓN BIDIRECCIONAL: Añadir dispositivos del viewer a monitored_devices del owner
      final viewerDevices = await firestore.collection('users/${user.uid}/devices').get();
      if (viewerDevices.docs.isNotEmpty) {
        final viewerDeviceIds = viewerDevices.docs.map((doc) => doc.id).toList();
        await firestore.collection('users').doc(widget.request.fromUid).update({
          'monitored_devices': FieldValue.arrayUnion(viewerDeviceIds),
        });
      }

      // 4. Eliminar solicitud
      await firestore.collection('users/${user.uid}/contactRequests').doc(widget.request.id).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contacto aceptado'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _rejectRequest() async {
    if (_processing) return;
    setState(() => _processing = true);

    try {
      final firestore = ref.read(firestoreProvider);
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      if (user == null) throw Exception('No autenticado');

      await firestore.collection('users/${user.uid}/contactRequests').doc(widget.request.id).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud rechazada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con avatar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.person_outline,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.request.fromName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.request.fromEmail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            
            // Detalles
            Row(
              children: [
                Icon(Icons.watch_outlined, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Dispositivo: ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.request.deviceName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Botones de acción
            if (_processing)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: theme.colorScheme.primary,
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _acceptRequest,
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text('Aceptar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _rejectRequest,
                      icon: const Icon(Icons.close, size: 20),
                      label: const Text('Rechazar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        side: BorderSide(color: theme.colorScheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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

// ============================================================================
// TAB 2: AÑADIR CONTACTO
// ============================================================================

class _AddContactTab extends ConsumerStatefulWidget {
  const _AddContactTab();

  @override
  ConsumerState<_AddContactTab> createState() => _AddContactTabState();
}

class _AddContactTabState extends ConsumerState<_AddContactTab> {
  final _usernameController = TextEditingController();
  String? _selectedDeviceId;
  bool _searching = false;
  bool _adding = false;
  
  Map<String, dynamic>? _selectedUser;
  List<Map<String, dynamic>> _userDevices = [];
  List<Map<String, dynamic>> _searchResults = [];
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      if (mounted) {
        setState(() => _searchResults = []);
      }
      return;
    }

    if (mounted) {
      setState(() => _searching = true);
    }

    try {
      final firestore = ref.read(firestoreProvider);
      final auth = ref.read(firebaseAuthProvider);
      final currentUser = auth.currentUser;
      if (currentUser == null) throw Exception('No autenticado');

      // Búsqueda por displayName - obtener más usuarios y filtrar en cliente
      final lowerQuery = query.toLowerCase();
      print('[SEARCH] Buscando: "$query" (lowercase: "$lowerQuery")');
      
      final usersQuery = await firestore
          .collection('users')
          .limit(50)  // Get more users to filter on client side
          .get();
      
      print('[SEARCH] Obtenidos ${usersQuery.docs.length} usuarios');
      
      final results = <Map<String, dynamic>>[];
      for (var doc in usersQuery.docs) {
        // No mostrar al usuario actual en los resultados
        if (doc.id != currentUser.uid) {
          final userData = doc.data();
          final displayName = (userData['displayName'] as String? ?? '').toLowerCase();
          final email = (userData['email'] as String? ?? '').toLowerCase();
          final username = (userData['username'] as String? ?? '').toLowerCase();
          
          // Filter by partial match in displayName, email, or username
          if (displayName.contains(lowerQuery) || 
              email.contains(lowerQuery) ||
              username.contains(lowerQuery)) {
            print('[SEARCH] Coincidencia: ${userData['displayName'] ?? userData['email']} (uid: ${doc.id})');
            results.add({'uid': doc.id, ...userData});
          }
        }
      }

      if (mounted) {
        setState(() => _searchResults = results);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error en búsqueda: $e'), backgroundColor: Colors.red),
        );
        setState(() => _searchResults = []);
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectUser(Map<String, dynamic> user) async {
    if (mounted) {
      setState(() => _selectedUser = user);
    }

    try {
      final firestore = ref.read(firestoreProvider);
      final auth = ref.read(firebaseAuthProvider);
      final currentUser = auth.currentUser;
      if (currentUser == null) throw Exception('No autenticado');

      // Obtener dispositivos del usuario actual
      final devicesQuery = await firestore.collection('users/${currentUser.uid}/devices').get();
      
      setState(() {
        _userDevices = devicesQuery.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        if (_userDevices.isNotEmpty) {
          _selectedDeviceId = _userDevices.first['id'];
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendRequest() async {
    if (_selectedUser == null || _selectedDeviceId == null) return;

    setState(() => _adding = true);

    try {
      await ref.read(addContactProvider({
        'contactUid': _selectedUser!['uid'],
        'contactName': _selectedUser!['displayName'] ?? 'Usuario',
        'contactEmail': _selectedUser!['email'] ?? '',
        'deviceId': _selectedDeviceId!,
      }).future);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Solicitud enviada. El usuario debe aceptarla.'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Resetear formulario
        _usernameController.clear();
        setState(() {
          _selectedUser = null;
          _searchResults = [];
          _userDevices = [];
          _selectedDeviceId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Instrucciones
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outline,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Busca por nombre de usuario para enviar una solicitud de contacto',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Campo de búsqueda con Autocomplete
        Autocomplete<Map<String, dynamic>>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            // Return the search results directly
            return _searchResults;
          },
          displayStringForOption: (option) => option['displayName'] ?? 'Usuario',
          fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              onChanged: (value) {
                // Cancel previous search
                _searchDebounce?.cancel();
                
                // Debounce the search to avoid too many Firestore queries
                _searchDebounce = Timer(const Duration(milliseconds: 500), () {
                  if (mounted) {
                    _usernameController.text = value;
                    _searchUsers(value);
                  }
                });
              },
              decoration: InputDecoration(
                labelText: 'Nombre de usuario',
                hintText: 'Busca por nombre...',
                prefixIcon: const Icon(Icons.person_search_outlined),
                suffixIcon: textEditingController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        textEditingController.clear();
                        _usernameController.clear();
                        setState(() {
                          _selectedUser = null;
                          _searchResults = [];
                          _userDevices = [];
                        });
                      },
                    )
                  : null,
              ),
              keyboardType: TextInputType.text,
            );
          },
          onSelected: (Map<String, dynamic> selection) {
            _usernameController.text = selection['displayName'] ?? 'Usuario';
            _selectUser(selection);
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  width: 300,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: theme.colorScheme.surface,
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (BuildContext context, int index) {
                      final option = options.elementAt(index);
                      final displayName = (option['displayName'] as String? ?? '').trim();
                      final firstChar = (displayName.isNotEmpty && displayName.length > 0) ? displayName.substring(0, 1).toUpperCase() : 'U';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(
                            firstChar,
                            style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(displayName.isNotEmpty ? displayName : 'Usuario'),
                        subtitle: Text(option['email'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        
        // Resultado de búsqueda
        if (_selectedUser != null) ...[
          const SizedBox(height: 32),
          
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Usuario encontrado
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.person_outline,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedUser!['displayName'] ?? 'Usuario',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedUser!['email'] ?? '',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  const Divider(height: 1),
                  const SizedBox(height: 24),
                  
                  // Formulario
                  if (_userDevices.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.error,
                      ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No tienes dispositivos Wilobu vinculados',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Text(
                      'Selecciona tu dispositivo',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    DropdownButtonFormField<String>(
                      value: _selectedDeviceId,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.devices_outlined),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                      ),
                      items: _userDevices.map((device) {
                        return DropdownMenuItem<String>(
                          value: device['id'] as String,
                          child: Row(
                            children: [
                              Icon(Icons.watch, size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(device['name'] ?? 'Wilobu'),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedDeviceId = value),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _adding ? null : _sendRequest,
                        icon: _adding 
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.send, size: 20),
                        label: Text(
                          _adding ? 'Enviando...' : 'Enviar Solicitud',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

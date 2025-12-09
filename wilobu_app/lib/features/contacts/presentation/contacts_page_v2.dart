import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wilobu_app/firebase_providers.dart';
import 'package:wilobu_app/features/contacts/data/contacts_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ContactsPageV2 extends ConsumerStatefulWidget {
  const ContactsPageV2({super.key});

  @override
  ConsumerState<ContactsPageV2> createState() => _ContactsPageV2State();
}

class _ContactsPageV2State extends ConsumerState<ContactsPageV2>
    with SingleTickerProviderStateMixin {
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
    final theme = Theme.of(context);
    final requestsAsync = ref.watch(contactRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contactos'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Badge(
                isLabelVisible: requestsAsync.maybeWhen(
                  data: (reqs) => reqs.isNotEmpty,
                  orElse: () => false,
                ),
                label: requestsAsync.maybeWhen(
                  data: (reqs) => Text('${reqs.length}'),
                  orElse: () => const Text('0'),
                ),
                child: const Icon(Icons.inbox_outlined),
              ),
              text: 'Solicitudes',
            ),
            const Tab(icon: Icon(Icons.person_add_outlined), text: 'Añadir'),
            const Tab(icon: Icon(Icons.people_outline), text: 'Mis Contactos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const _RequestsTab(),
          const _AddContactTab(),
          const _MyContactsTab(),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 1: SOLICITUDES PENDIENTES
// ============================================================================

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(contactRequestsProvider);
    final theme = Theme.of(context);

    return requestsAsync.when(
      data: (requests) {
        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined,
                    size: 80, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text('Sin solicitudes',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(height: 8),
                Text('Las solicitudes de contacto aparecerán aquí',
                    style: theme.textTheme.bodyMedium),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (ctx, i) =>
              _RequestCard(request: requests[i], ref: ref),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  final ContactRequest request;
  final WidgetRef ref;

  const _RequestCard({required this.request, required this.ref});

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _processing = false;

  Future<void> _acceptRequest() async {
    setState(() => _processing = true);

    try {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null) throw Exception('No autenticado');

      final firestore = ref.read(firestoreProvider);

      // 1. Agregar viewer al dispositivo
      await firestore
          .collection('users/${widget.request.fromUid}/devices')
          .doc(widget.request.deviceId)
          .update({
        'viewerUids': FieldValue.arrayUnion([user.uid]),
      });

      // 2. Agregar dispositivo a monitored_devices del usuario
      await firestore.collection('users').doc(user.uid).update({
        'monitored_devices': FieldValue.arrayUnion([widget.request.deviceId]),
      });

      // 3. Eliminar solicitud
      await firestore
          .collection('users/${user.uid}/contactRequests')
          .doc(widget.request.id)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Acceso concedido a ${widget.request.deviceName}'),
            backgroundColor: Colors.green,
          ),
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
    setState(() => _processing = true);

    try {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null) throw Exception('No autenticado');

      final firestore = ref.read(firestoreProvider);

      // Eliminar solicitud
      await firestore
          .collection('users/${user.uid}/contactRequests')
          .doc(widget.request.id)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Solicitud rechazada'),
            backgroundColor: Colors.orange,
          ),
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
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    widget.request.fromName.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.request.fromName,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('${widget.request.fromEmail} • ${widget.request.deviceName}',
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_processing)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _rejectRequest,
                      icon: const Icon(Icons.close),
                      label: const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _acceptRequest,
                      icon: const Icon(Icons.check),
                      label: const Text('Aceptar'),
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
  final _emailController = TextEditingController();
  bool _searching = false;
  Map<String, dynamic>? _foundUser;
  List<Map<String, dynamic>> _myDevices = [];
  String? _selectedDeviceId;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadMyDevices() async {
    try {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null) return;

      final firestore = ref.read(firestoreProvider);
      final docs =
          await firestore.collection('users/${user.uid}/devices').get();

      setState(() {
        _myDevices =
            docs.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        if (_myDevices.isNotEmpty) {
          _selectedDeviceId = _myDevices.first['id'];
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _searchUser() async {
    if (_emailController.text.trim().isEmpty) return;

    setState(() => _searching = true);

    try {
      final firestore = ref.read(firestoreProvider);
      final query = await firestore
          .collection('users')
          .where('email', isEqualTo: _emailController.text.trim().toLowerCase())
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        setState(() => _foundUser = null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Usuario no encontrado'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        final doc = query.docs.first;
        setState(() {
          _foundUser = {'uid': doc.id, ...doc.data()};
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest() async {
    if (_foundUser == null || _selectedDeviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona dispositivo y usuario')),
      );
      return;
    }

    setState(() => _searching = true);

    try {
      await ref.read(sendContactRequestProvider({
        'contactUid': _foundUser!['uid'],
        'deviceId': _selectedDeviceId!,
      }).future);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Solicitud enviada'),
            backgroundColor: Colors.green,
          ),
        );
        _emailController.clear();
        setState(() => _foundUser = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email del contacto',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _emailController,
            decoration: InputDecoration(
              hintText: 'ejemplo@gmail.com',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: _searching
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _searchUser,
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_foundUser != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        (_foundUser!['displayName'] as String?)
                                ?.substring(0, 1)
                                .toUpperCase() ??
                            'U',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_foundUser!['displayName'] ?? 'Usuario',
                              style: theme.textTheme.titleSmall),
                          Text(_foundUser!['email'] ?? '',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Dispositivo a compartir',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_myDevices.isEmpty)
              Text('No tienes dispositivos',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ))
            else
              DropdownButtonFormField<String>(
                value: _selectedDeviceId,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: _myDevices
                    .map<DropdownMenuItem<String>>((d) => DropdownMenuItem<String>(
                          value: d['id'] as String,
                          child: Text(d['nickname'] as String? ?? d['id']),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedDeviceId = v),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _myDevices.isEmpty ? null : _sendRequest,
                child: const Text('Enviar Solicitud'),
              ),
            ),
          ] else if (_emailController.text.isNotEmpty && !_searching)
            const SizedBox(height: 20),
          if (_myDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.devices_other_outlined,
                        size: 80, color: theme.colorScheme.outline),
                    const SizedBox(height: 16),
                    Text('No tienes dispositivos',
                        style: theme.textTheme.titleMedium),
                    Text('Vincula un Wilobu primero',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          if (_myDevices.isEmpty) ...[
            const SizedBox(height: 20),
            Opacity(
              opacity: 0.5,
              child: ElevatedButton(
                onPressed: null,
                child: const Text('Cargar dispositivos'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadMyDevices,
              child: const Text('Recargar dispositivos'),
            ),
          ]
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadMyDevices();
  }
}

// ============================================================================
// TAB 3: MIS CONTACTOS
// ============================================================================

class _MyContactsTab extends ConsumerWidget {
  const _MyContactsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(firebaseAuthProvider).currentUser;

    if (user == null) {
      return Center(
        child: Text('No autenticado', style: theme.textTheme.bodyMedium),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: ref
          .read(firestoreProvider)
          .collection('users/${user.uid}/devices')
          .snapshots(),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline,
                    size: 80, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text('Sin contactos', style: theme.textTheme.titleLarge),
              ],
            ),
          );
        }

        final devices = snapshot.data!.docs;
        final viewersList = <Map<String, dynamic>>[];

        for (final device in devices) {
          final viewers = (device.data() as Map)['viewerUids'] as List? ?? [];
          final deviceName = (device.data() as Map)['nickname'] ?? device.id;

          for (final viewerUid in viewers) {
            viewersList.add({
              'uid': viewerUid,
              'deviceId': device.id,
              'deviceName': deviceName,
            });
          }
        }

        if (viewersList.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline,
                    size: 80, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text('No has compartido dispositivos',
                    style: theme.textTheme.titleLarge),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: viewersList.length,
          itemBuilder: (ctx, i) => _ContactViewerCard(
            viewer: viewersList[i],
            ref: ref,
          ),
        );
      },
    );
  }
}

class _ContactViewerCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> viewer;
  final WidgetRef ref;

  const _ContactViewerCard({required this.viewer, required this.ref});

  @override
  ConsumerState<_ContactViewerCard> createState() =>
      _ContactViewerCardState();
}

class _ContactViewerCardState extends ConsumerState<_ContactViewerCard> {
  Map<String, dynamic>? _viewerData;
  bool _loading = true;
  bool _removing = false;

  @override
  void initState() {
    super.initState();
    _loadViewerData();
  }

  Future<void> _loadViewerData() async {
    try {
      final firestore = ref.read(firestoreProvider);
      final doc = await firestore
          .collection('users')
          .doc(widget.viewer['uid'])
          .get();

      setState(() {
        _viewerData = doc.data();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _removeViewer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Remover acceso?'),
        content: Text(
          '${_viewerData?['displayName'] ?? 'Este usuario'} ya no podrá ver tu dispositivo ni recibir alertas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _removing = true);

    try {
      await ref
          .read(removeViewerProvider({
            'viewerUid': widget.viewer['uid'],
            'deviceId': widget.viewer['deviceId'],
          }).future);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Acceso removido para ${_viewerData?['displayName'] ?? 'usuario'}',
            ),
            backgroundColor: Colors.orange,
          ),
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

    if (_loading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Cargando...')),
            ],
          ),
        ),
      );
    }

    final name = _viewerData?['displayName'] ?? 'Usuario';
    final email = _viewerData?['email'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    name.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(
                        '${widget.viewer['deviceName']} • $email',
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_removing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.red),
                    onPressed: _removeViewer,
                    tooltip: 'Remover acceso',
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
// MODELS
// ============================================================================

class ContactRequest {
  final String id;
  final String fromUid;
  final String fromName;
  final String fromEmail;
  final String deviceId;
  final String deviceName;
  final DateTime timestamp;

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
    final data = doc.data() ?? {};
    return ContactRequest(
      id: doc.id,
      fromUid: data['fromUid'] as String? ?? '',
      fromName: data['fromName'] as String? ?? 'Usuario',
      fromEmail: data['fromEmail'] as String? ?? '',
      deviceId: data['deviceId'] as String? ?? '',
      deviceName: data['deviceName'] as String? ?? 'Wilobu',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ??
          DateTime.now(),
    );
  }
}

// ============================================================================
// PROVIDER
// ============================================================================

final contactRequestsProvider =
    StreamProvider.autoDispose<List<ContactRequest>>((ref) {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) return const Stream.empty();

  return ref.watch(firestoreProvider)
      .collection('users/${user.uid}/contactRequests')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((s) => s.docs.map(ContactRequest.fromDoc).toList());
});

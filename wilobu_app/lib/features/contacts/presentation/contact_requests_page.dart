import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wilobu_app/firebase_providers.dart';

/// Modelo de solicitud de contacto
class ContactRequest {
  final String id;
  final String fromUid;
  final String fromName;
  final String fromEmail;
  final String deviceId;
  final String deviceName;
  final String relation;
  final DateTime timestamp;

  ContactRequest({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.fromEmail,
    required this.deviceId,
    required this.deviceName,
    required this.relation,
    required this.timestamp,
  });

  factory ContactRequest.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ContactRequest(
      id: doc.id,
      fromUid: data['fromUid'] as String,
      fromName: data['fromName'] as String? ?? 'Usuario',
      fromEmail: data['fromEmail'] as String? ?? '',
      deviceId: data['deviceId'] as String,
      deviceName: data['deviceName'] as String? ?? 'Wilobu',
      relation: data['relation'] as String,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Provider para obtener las solicitudes de contacto del usuario actual
final contactRequestsProvider = StreamProvider.autoDispose<List<ContactRequest>>((ref) {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) return const Stream.empty();

  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('users')
      .doc(user.uid)
      .collection('contactRequests')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => ContactRequest.fromDoc(doc)).toList());
});

/// Pantalla para ver y gestionar solicitudes de contacto
class ContactRequestsPage extends ConsumerWidget {
  const ContactRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final requestsAsync = ref.watch(contactRequestsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Solicitudes de Contacto'),
        centerTitle: true,
      ),
      body: requestsAsync.when(
        data: (requests) {
          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mark_email_read_outlined,
                    size: 80,
                    color: isDark ? Colors.white38 : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No tienes solicitudes pendientes',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final request = requests[index];
              return _RequestCard(request: request);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Error al cargar solicitudes: $error',
              style: TextStyle(color: Colors.red.shade700),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  final ContactRequest request;

  const _RequestCard({required this.request});

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _isProcessing = false;

  Future<void> _acceptRequest() async {
    setState(() => _isProcessing = true);

    try {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      final firestore = ref.read(firestoreProvider);
      
      // 1. Agregar el contacto al dispositivo del solicitante
      final deviceRef = firestore
          .collection('users')
          .doc(widget.request.fromUid)
          .collection('devices')
          .doc(widget.request.deviceId);

      final myData = {
        'uid': user.uid,
        'name': user.displayName ?? user.email?.split('@')[0] ?? 'Usuario',
        'email': user.email ?? '',
        'relation': widget.request.relation,
      };

      await deviceRef.update({
        'emergencyContacts': FieldValue.arrayUnion([myData])
      });

      // 2. Eliminar la solicitud
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('contactRequests')
          .doc(widget.request.id)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud aceptada'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _rejectRequest() async {
    setState(() => _isProcessing = true);

    try {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      final firestore = ref.read(firestoreProvider);
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('contactRequests')
          .doc(widget.request.id)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud rechazada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                  child: Icon(
                    Icons.person_add,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.request.fromName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        widget.request.fromEmail,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.watch,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Dispositivo: ${widget.request.deviceName}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.family_restroom,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Como: ${widget.request.relation}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_isProcessing)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _acceptRequest,
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text('Aceptar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _rejectRequest,
                      icon: const Icon(Icons.close, size: 20),
                      label: const Text('Rechazar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: BorderSide(color: Theme.of(context).colorScheme.error),
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

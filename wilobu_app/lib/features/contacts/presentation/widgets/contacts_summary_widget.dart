import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wilobu_app/firebase_providers.dart';

/// Provider que obtiene los contactos agregados (usuarios que tienen acceso a mis dispositivos)
final myContactsProvider = StreamProvider.autoDispose<List<ContactModel>>((ref) {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) return const Stream.empty();
  
  final firestore = ref.watch(firestoreProvider);
  
  // Obtener todos los dispositivos del usuario y extraer los emergencyContacts
  return firestore
    .collection('users')
    .doc(user.uid)
    .collection('devices')
    .snapshots()
    .asyncMap((devicesSnapshot) async {
      final allContacts = <String, ContactModel>{};
      
      for (final deviceDoc in devicesSnapshot.docs) {
        final deviceData = deviceDoc.data();
        final emergencyContacts = deviceData['emergencyContacts'] as List<dynamic>? ?? [];
        
        // Para cada contacto de emergencia, obtener su información
        for (final contact in emergencyContacts) {
          if (contact is Map<String, dynamic>) {
            final contactUid = contact['uid'] as String?;
            if (contactUid == null || allContacts.containsKey(contactUid)) continue;
            
            try {
              final userDoc = await firestore.collection('users').doc(contactUid).get();
              final userData = userDoc.data() ?? {};
              
              allContacts[contactUid] = ContactModel(
                uid: contactUid,
                displayName: userData['displayName'] as String?,
                email: userData['email'] as String?,
                username: userData['username'] as String?,
                photoUrl: userData['photoUrl'] as String?,
                addedAt: null, // Podrían agregar timestamp si lo desean
              );
            } catch (e) {
              print('[myContactsProvider] Error al obtener datos del contacto $contactUid: $e');
            }
          }
        }
      }
      
      return allContacts.values.toList();
    })
    .handleError((error) {
      print('[myContactsProvider] Error: $error');
      return <ContactModel>[];
    });
});

/// Modelo simple de contacto
class ContactModel {
  final String uid;
  final String? displayName;
  final String? email;
  final String? username;
  final String? photoUrl;
  final DateTime? addedAt;

  ContactModel({
    required this.uid,
    this.displayName,
    this.email,
    this.username,
    this.photoUrl,
    this.addedAt,
  });

  factory ContactModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ContactModel(
      uid: doc.id,
      displayName: data['displayName'] as String?,
      email: data['email'] as String?,
      username: data['username'] as String?,
      photoUrl: data['photoUrl'] as String?,
      addedAt: (data['addedAt'] is Timestamp)
        ? (data['addedAt'] as Timestamp).toDate()
        : null,
    );
  }

  String get displayLabel => displayName ?? email ?? 'Usuario';
  
  String get avatarLabel {
    final display = displayName?.trim();
    if (display != null && display.isNotEmpty && display.length > 0) {
      return display[0].toUpperCase();
    }
    return 'U';
  }
}

/// Widget que muestra resumen de contactos frecuentes en el dashboard
class MyContactsSummaryWidget extends ConsumerWidget {
  const MyContactsSummaryWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(myContactsProvider);
    final theme = Theme.of(context);

    return contactsAsync.when(
      data: (contacts) {
        if (contacts.isEmpty) {
          return _EmptyContactsCard(theme: theme);
        }

        // Mostrar máximo 5 contactos en el dashboard
        final displayedContacts = contacts.take(5).toList();
        final hasMore = contacts.length > 5;

        return Column(
          children: [
            // Header con título
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.people, color: theme.colorScheme.primary, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mis Contactos',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${contacts.length} contacto${contacts.length != 1 ? 's' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/contacts'),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('Ver todos'),
                  ),
                ],
              ),
            ),
            // Grid de contactos
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayedContacts.length + (hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == displayedContacts.length) {
                    return _MoreContactsCard(
                      remaining: contacts.length - 5,
                      onTap: () => context.push('/contacts'),
                    );
                  }

                  final contact = displayedContacts[index];
                  return _ContactAvatarTile(contact: contact);
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: SizedBox(
          height: 100,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Error al cargar contactos',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Card para cuando no hay contactos
class _EmptyContactsCard extends StatelessWidget {
  final ThemeData theme;

  const _EmptyContactsCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: theme.colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Aún no tienes contactos',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Agrega contactos para mantenerte conectado',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push('/contacts'),
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('Agregar contacto'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tile individual de contacto
class _ContactAvatarTile extends StatelessWidget {
  final ContactModel contact;

  const _ContactAvatarTile({required this.contact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: contact.displayLabel,
      child: InkWell(
        onTap: () {
          // Aquí puedes agregar acción al hacer tap (mostrar perfil, etc.)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${contact.displayLabel} - @${contact.username ?? contact.email?.split('@')[0] ?? 'Usuario'}'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar circular
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                ),
                child: Center(
                  child: Text(
                    contact.avatarLabel,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Nombre del contacto (máximo 2 líneas)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  contact.displayLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card que muestra cantidad de contactos restantes
class _MoreContactsCard extends StatelessWidget {
  final int remaining;
  final VoidCallback onTap;

  const _MoreContactsCard({
    required this.remaining,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.2),
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.more_horiz,
              color: theme.colorScheme.primary,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              '+$remaining',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

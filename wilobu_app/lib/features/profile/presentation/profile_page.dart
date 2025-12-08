import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../firebase_providers.dart';
import '../infrastructure/profile_providers.dart';
import '../domain/user_profile.dart';
import 'widgets/profile_widgets.dart';
import 'edit_profile_page.dart';
import 'preferences_page.dart';
import 'emergency_contact_page.dart';

/// Página principal del perfil del usuario
class ProfilePage extends ConsumerWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileStreamProvider);
    final auth = ref.watch(firebaseAuthProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        elevation: 0,
      ),
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.invalidate(currentUserProfileStreamProvider);
                },
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
        data: (profile) => SingleChildScrollView(
          child: Column(
            children: [
              // Sección de información básica
              ProfileInfoCard(
                profile: profile,
                onEdit: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EditProfilePage(),
                    ),
                  );
                },
              ),

              // Sección de información adicional
              _buildInfoSection(context, profile),

              // Botones de acciones rápidas
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PreferencesPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings),
                      label: const Text('Preferencias'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const EmergencyContactPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.emergency),
                      label: const Text('Contacto de Emergencia'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final shouldLogout =
                            await _showLogoutDialog(context);
                        if (shouldLogout) {
                          if (context.mounted) {
                            await auth.signOut();
                          }
                        }
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Cerrar Sesión'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Construye la sección de información adicional
  Widget _buildInfoSection(BuildContext context, UserProfile profile) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Información Adicional',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Divider(),
              const SizedBox(height: 12),
              ProfileInfoSection(
                title: 'Teléfono',
                value: profile.phoneNumber,
                icon: Icons.phone,
              ),
              ProfileInfoSection(
                title: 'Dirección',
                value: profile.address,
                icon: Icons.location_on,
              ),
              if (profile.city != null || profile.country != null)
                ProfileInfoSection(
                  title: 'Ciudad',
                  value: profile.city != null
                      ? '${profile.city}, ${profile.country ?? ''}'
                      : null,
                  icon: Icons.public,
                ),
              if (profile.dateOfBirth != null)
                ProfileInfoSection(
                  title: 'Fecha de Nacimiento',
                  value:
                      '${profile.dateOfBirth!.day}/${profile.dateOfBirth!.month}/${profile.dateOfBirth!.year}',
                  icon: Icons.cake,
                ),
              ProfileInfoSection(
                title: 'Miembro desde',
                value:
                    '${profile.createdAt.day}/${profile.createdAt.month}/${profile.createdAt.year}',
                icon: Icons.calendar_today,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Muestra un diálogo de confirmación para cerrar sesión
  Future<bool> _showLogoutDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../infrastructure/profile_providers.dart';
import 'widgets/profile_widgets.dart';

/// Página para gestionar las preferencias del usuario
class PreferencesPage extends ConsumerWidget {
  const PreferencesPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileStreamProvider);
    final updateAsync = ref.watch(profileUpdateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferencias'),
      ),
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stackTrace) => Center(
          child: Text('Error: $error'),
        ),
        data: (profile) => SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notificaciones',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        PreferenceToggleTile(
                          title: 'Habilitar Notificaciones',
                          subtitle:
                              'Recibe alertas y actualizaciones importantes',
                          value: profile.notificationsEnabled,
                          onChanged: (value) {
                            ref
                                .read(profileUpdateProvider.notifier)
                                .updateNotificationPreferences(value);
                          },
                          icon: Icons.notifications,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ubicación',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        PreferenceToggleTile(
                          title: 'Compartir Ubicación',
                          subtitle:
                              'Permitir que otros vean tu ubicación en emergencias',
                          value: profile.locationSharingEnabled,
                          onChanged: (value) {
                            ref
                                .read(profileUpdateProvider.notifier)
                                .updateLocationSharingPreference(value);
                          },
                          icon: Icons.location_on,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (updateAsync.isLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              if (updateAsync.hasError)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SnackBar(
                    content: Text('Error: ${updateAsync.error}'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// lib/features/home/presentation/home_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wilobu_app/firebase_providers.dart';
import 'package:wilobu_app/theme/app_theme.dart';

class WilobuDevice {
  WilobuDevice({
    required this.id,
    required this.nombre,
    required this.usuarioProtegido,
    required this.estado,
    required this.bateria,
    required this.senal,
    required this.hardwareId,
    required this.hardwareTipo,
  });

  final String id;
  final String nombre;            // nombre que ve el usuario (ej: "Wilobu de casa")
  final String usuarioProtegido;  // persona protegida / portador
  final String estado;
  final int bateria;
  final int senal;
  final String hardwareId;
  final String hardwareTipo;

  factory WilobuDevice.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return WilobuDevice(
      id: doc.id,
      nombre: data['name'] as String? ?? 'Wilobu',
      usuarioProtegido: data['protectedUser'] as String? ?? 'Sin asignar',
      estado: data['status'] as String? ?? 'Sin conexión',
      bateria: (data['battery'] as num?)?.toInt() ?? 0,
      senal: (data['signal'] as num?)?.toInt() ?? 0,
      hardwareId: data['hardwareId'] as String? ?? doc.id,
      hardwareTipo: data['hardwareType'] as String? ?? 'Desconocido',
    );
  }
}

final userDevicesStreamProvider =
    StreamProvider.autoDispose<List<WilobuDevice>>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final user = auth.currentUser;
  if (user == null) {
    return const Stream.empty();
  }

  final firestore = ref.watch(firestoreProvider);
  final devicesCollection = firestore
      .collection('users')
      .doc(user.uid)
      .collection('devices')
      .orderBy('name');

  return devicesCollection.snapshots().map(
        (snapshot) =>
            snapshot.docs.map(WilobuDevice.fromDoc).toList(growable: false),
      );
});

/// Obtiene un “nombre de usuario bonito”
/// 1. displayName si existe
/// 2. antes del @ del email
/// 3. "Usuario Wilobu" por defecto
String _usernameFromUser(fb.User? user) {
  if (user == null) return 'Usuario Wilobu';

  if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
    return user.displayName!.trim();
  }

  final email = user.email;
  if (email != null && email.contains('@')) {
    return email.split('@').first;
  }

  return 'Usuario Wilobu';
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(firebaseAuthProvider);
    final fbUser = auth.currentUser;
    final username = _usernameFromUser(fbUser);

    final devicesAsync = ref.watch(userDevicesStreamProvider);
    final themeMode = ref.watch(themeControllerProvider);

    final background = themeMode == AppThemeMode.wilobu
        ? const DecorationImage(
            image: AssetImage('assets/images/fondo_wilobu.jpg'),
            fit: BoxFit.cover,
          )
        : null;

    // FAB solo si hay dispositivos
    final fab = devicesAsync.maybeWhen(
      data: (devices) {
        if (devices.isEmpty) return null;
        return FloatingActionButton.extended(
          onPressed: () => context.go('/devices/add'),
          icon: const Icon(Icons.add),
          label: const Text('Agregar Wilobu'),
        );
      },
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/wilobu_logo.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Wilobu',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<AppThemeMode>(
            tooltip: 'Tema',
            initialValue: themeMode,
            onSelected: (mode) =>
                ref.read(themeControllerProvider.notifier).setTheme(mode),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: AppThemeMode.light,
                child: Text('Tema claro'),
              ),
              PopupMenuItem(
                value: AppThemeMode.dark,
                child: Text('Tema oscuro'),
              ),
              PopupMenuItem(
                value: AppThemeMode.wilobu,
                child: Text('Wilobu Theme'),
              ),
            ],
            icon: const Icon(Icons.color_lens_outlined),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await auth.signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
      floatingActionButton: fab,
      body: Container(
        decoration: BoxDecoration(image: background),
        child: Container(
          // capa semitransparente para mejorar contraste en Wilobu Theme
          color: background != null
              ? Colors.white.withAlpha(220)
              : Colors.transparent,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(username: username),
                  const SizedBox(height: 16),
                  Expanded(
                    child: devicesAsync.when(
                      data: (devices) {
                        if (devices.isEmpty) {
                          return _EmptyState(
                            onAddPressed: () => context.go('/devices/add'),
                          );
                        }
                        return ListView.separated(
                          itemCount: devices.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final d = devices[index];
                            return _DeviceCard(device: d);
                          },
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (e, _) => Center(
                        child: Text('Error al cargar dispositivos: $e'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.person_outline, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hola, $username',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Administra aquí tus dispositivos Wilobu.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddPressed});

  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.watch_outlined, size: 72),
          const SizedBox(height: 16),
          Text(
            'Aún no has registrado ningún Wilobu.',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Registra tu primer dispositivo para usar las funciones de seguridad.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onAddPressed,
              icon: const Icon(Icons.add),
              label: const Text('Registrar Wilobu'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final WilobuDevice device;

  Color _statusColor() {
    switch (device.estado) {
      case 'Online':
        return Colors.green;
      case 'En prueba':
        return Colors.orange;
      case 'Offline':
      case 'Sin conexión':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.watch_outlined, size: 32, color: statusColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.nombre,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Persona protegida: ${device.usuarioProtegido}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'ID interno: ${device.hardwareId} (${device.hardwareTipo})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Chip(
                        label: Text(device.estado),
                        backgroundColor: statusColor.withAlpha(30),
                        labelStyle: TextStyle(color: statusColor),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 8),
                      Text('Batería: ${device.bateria}%'),
                      const SizedBox(width: 8),
                      Text('Señal: ${device.senal}%'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

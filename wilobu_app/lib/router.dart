import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'firebase_providers.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/register_page.dart';
import 'features/home/presentation/home_page.dart';
import 'features/devices/presentation/add_device_page.dart';
import 'features/devices/presentation/device_settings_view.dart';
import 'features/contacts/presentation/contacts_page.dart';
import 'features/alerts/presentation/alerts_page.dart';
import 'features/sos/sos_alert_page.dart';
import 'features/profile/presentation/profile_page.dart';

/// Provider para suspender la redirección automática durante el registro
final suspendRedirectProvider = StateProvider<bool>((ref) => false);

/// Clase Helper para convertir un Stream (como authStateChanges)
/// en un Listenable que GoRouter pueda escuchar para refrescar rutas.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.listen(
      (dynamic _) => notifyListeners(),
    );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final suspendRedirect = ref.watch(suspendRedirectProvider);

  return GoRouter(
    initialLocation: '/login',
    debugLogDiagnostics: true,

    // Escucha cambios en la autenticación para reevaluar la redirección
    refreshListenable: GoRouterRefreshStream(auth.authStateChanges()),

    // Lógica de protección de rutas
    redirect: (context, state) {
      try {
        // Si la redirección está suspendida (durante el registro), no redirigir
        if (suspendRedirect) {
          return null;
        }
        
        final user = auth.currentUser;
        final isLoggedIn = user != null;
        
        final isLoggingIn = state.uri.path == '/login' || state.uri.path == '/register';

        // 1. Si NO está logueado y no está en login/register -> ir a Login
        if (!isLoggedIn) {
          return isLoggingIn ? null : '/login';
        }

        // 2. Si SI está logueado y trata de ir a login/register -> ir a Home
        if (isLoggingIn) {
          return '/home';
        }

        // 3. En cualquier otro caso, dejar pasar
        return null;
      } catch (e) {
        // Si Firebase falla, simplemente permitir acceso a la ruta
        print('Error en redirect: $e');
        return null;
      }
    },

    routes: <RouteBase>[
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/devices/add',
        builder: (context, state) => const AddDevicePage(),
      ),
      GoRoute(
        path: '/devices/settings',
        builder: (context, state) {
          final deviceId = state.uri.queryParameters['deviceId'];
          
          if (deviceId == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Error')),
              body: const Center(child: Text('ID de dispositivo requerido')),
            );
          }
          
          return DeviceSettingsView(deviceId: deviceId);
        },
      ),
      GoRoute(
        path: '/contacts',
        builder: (context, state) => const ContactsPage(),
      ),
      GoRoute(
        path: '/alerts',
        builder: (context, state) => const AlertsPage(),
      ),
      GoRoute(
        path: '/sos-alert',
        builder: (context, state) {
          final deviceId = state.uri.queryParameters['deviceId'];
          final userId = state.uri.queryParameters['userId'];
          
          if (deviceId == null || userId == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Error')),
              body: const Center(child: Text('Parámetros requeridos faltantes')),
            );
          }
          
          return SosAlertPage(deviceId: deviceId, userId: userId);
        },
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfilePage(),
      ),
    ],
  );
});
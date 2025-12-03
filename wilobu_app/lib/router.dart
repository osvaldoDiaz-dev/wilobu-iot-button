import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'firebase_providers.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/register_page.dart';
import 'features/home/presentation/home_page.dart';
import 'features/devices/presentation/add_device_page.dart';

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

  return GoRouter(
    initialLocation: '/login',
    debugLogDiagnostics: true,

    // Escucha cambios en la autenticación para reevaluar la redirección
    refreshListenable: GoRouterRefreshStream(auth.authStateChanges()),

    // Lógica de protección de rutas
    redirect: (context, state) {
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
    ],
  );
});
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'firebase_options.dart';
import 'firebase_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    print('Firebase ya estaba inicializado: $e');
  }
  runApp(const ProviderScope(child: WilobuApp()));
}

class WilobuApp extends ConsumerWidget {
  const WilobuApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeControllerProvider);
    final theme = AppTheme.getTheme(themeMode);
    
    // Inicializar FCM cuando el usuario se autentique
    ref.listen(firebaseAuthProvider, (previous, next) {
      final user = next.currentUser;
      if (user != null) {
        ref.read(fcmServiceProvider).initialize();
      }
    });

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Wilobu',
      theme: theme,
      routerConfig: router,
    );
  }
}
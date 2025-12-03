import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'router.dart';
import 'theme/app_theme.dart';   // ← NUEVO

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: WilobuApp()));
}

class WilobuApp extends ConsumerWidget {
  const WilobuApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    // leer modo de tema actual
    final themeMode = ref.watch(themeControllerProvider);
    final theme = AppThemes.of(themeMode);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Wilobu',
      routerConfig: router,
      theme: theme,          // ← usamos el tema según modo
    );
  }
}

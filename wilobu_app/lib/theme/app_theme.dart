import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeControllerProvider = StateNotifierProvider<ThemeNotifier, AppThemeMode>((ref) {
  return ThemeNotifier();
});

enum AppThemeMode { light, dark, wilobu }

class ThemeNotifier extends StateNotifier<AppThemeMode> {
  ThemeNotifier() : super(AppThemeMode.wilobu) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('theme_mode') ?? 2; // wilobu por defecto
    state = AppThemeMode.values[themeIndex.clamp(0, AppThemeMode.values.length - 1)];
  }

  Future<void> setTheme(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }
  
  void cycleTheme() {
    final nextIndex = (state.index + 1) % AppThemeMode.values.length;
    setTheme(AppThemeMode.values[nextIndex]);
  }
}

class AppTheme {
  static const seedColor = Color(0xFF6366F1);
  static const wilobuColor = Color(0xFF00D9FF); // Cyan Wilobu

  static ThemeData getTheme(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return _buildTheme(Brightness.light, seedColor);
      case AppThemeMode.dark:
        return _buildTheme(Brightness.dark, seedColor);
      case AppThemeMode.wilobu:
        return _buildWilobuTheme();
    }
  }

  static ThemeData _buildTheme(Brightness brightness, Color seed) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
      scaffoldBackgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
  
  static ThemeData _buildWilobuTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: wilobuColor,
        brightness: Brightness.dark,
        primary: wilobuColor,
        secondary: const Color(0xFF7C4DFF),
      ),
      scaffoldBackgroundColor: const Color(0xFF0A1929),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D2137),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Color(0xFF00D9FF)),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF0D2137),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0D2137),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00D9FF), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: wilobuColor.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00D9FF), width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: wilobuColor,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      dividerColor: wilobuColor.withOpacity(0.2),
    );
  }
  
  /// Devuelve el widget de fondo para el tema Wilobu
  static Widget? buildWilobuBackground(AppThemeMode mode) {
    if (mode != AppThemeMode.wilobu) return null;
    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/fondo_wilobu.jpg'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black.withOpacity(0.5),
        ),
        Center(
          child: Opacity(
            opacity: 0.12,
            child: ClipOval(
              child: Image.asset('assets/images/wilobu_logo.png', width: 280, height: 280, fit: BoxFit.cover),
            ),
          ),
        ),
      ],
    );
  }
}

/// Widget que aplica el fondo Wilobu solo cuando está activo el tema Wilobu
class WilobuScaffold extends ConsumerWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;

  const WilobuScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);
    final isWilobu = themeMode == AppThemeMode.wilobu;
    final theme = Theme.of(context);

    if (isWilobu) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: bottomNavigationBar,
        body: Stack(
          children: [
            // Fondo con imagen
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/fondo_wilobu.jpg'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            // Overlay oscuro para legibilidad
            Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black.withOpacity(0.5),
            ),
            // Logo circular semi-transparente al centro
            Center(
              child: Opacity(
                opacity: 0.12,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/wilobu_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            // Contenido
            SafeArea(child: body),
          ],
        ),
      );
    }

    // Tema normal (claro/oscuro)
    return Scaffold(
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(child: body),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Modos de tema disponibles en la app.
enum AppThemeMode {
  light,
  dark,
  wilobu, // fondo pastel + branding Wilobu
}

/// StateNotifier para controlar el tema actual.
class ThemeController extends StateNotifier<AppThemeMode> {
  ThemeController() : super(AppThemeMode.light);

  void setTheme(AppThemeMode mode) => state = mode;
}

/// Provider global para leer / cambiar el tema.
final themeControllerProvider =
    StateNotifierProvider<ThemeController, AppThemeMode>(
  (ref) => ThemeController(),
);

/// Helper para obtener el ThemeData según el modo.
class AppThemes {
  static ThemeData of(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.dark:
        return _dark;
      case AppThemeMode.wilobu:
        return _wilobu;
      case AppThemeMode.light:
      default:
        return _light;
    }
  }

  // Base light
  static final _baseLight = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: Brightness.light,
    ),
  );

  // Base dark
  static final _baseDark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: Brightness.dark,
    ),
  );

  /// Tema claro estándar
  static final ThemeData _light = _baseLight.copyWith(
    scaffoldBackgroundColor: const Color(0xFFF8F7FD),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
  );

  /// Tema oscuro estándar
  static final ThemeData _dark = _baseDark.copyWith(
    scaffoldBackgroundColor: const Color(0xFF11121A),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
  );

  /// Tema “Wilobu Theme”: pensado para usarse con el fondo pastel
  static final ThemeData _wilobu = _baseLight.copyWith(
    // El fondo real lo pone el Home con una imagen; aquí lo dejamos transparente
    scaffoldBackgroundColor: Colors.transparent,
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white70,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
    textTheme: _baseLight.textTheme.apply(
      bodyColor: const Color(0xFF3A325F),
      displayColor: const Color(0xFF3A325F),
    ),
  );
}

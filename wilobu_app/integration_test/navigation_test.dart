// Test de navegación: Login → Home → Historial de Alertas
// Ejecutar: flutter test integration_test/navigation_test.dart -d <DEVICE_ID>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wilobu_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Navegación de Alertas', () {
    testWidgets('Login → Home → Historial de Alertas', (tester) async {
      // Iniciar la app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // === PASO 1: LOGIN ===
      print('📱 Buscando pantalla de login...');
      
      // Buscar campos de login
      final emailField = find.byType(TextField).first;
      final passwordField = find.byType(TextField).last;
      
      // Ingresar credenciales del usuario de prueba
      await tester.enterText(emailField, 'wilobu.test@gmail.com');
      await tester.pumpAndSettle();
      
      await tester.enterText(passwordField, 'WilobuTest2025!');
      await tester.pumpAndSettle();
      
      print('✓ Credenciales ingresadas');

      // Buscar y presionar botón de login
      final loginButton = find.widgetWithText(ElevatedButton, 'Iniciar sesión');
      if (loginButton.evaluate().isNotEmpty) {
        await tester.tap(loginButton);
      } else {
        // Alternativa: buscar cualquier ElevatedButton
        final anyButton = find.byType(ElevatedButton).first;
        await tester.tap(anyButton);
      }
      
      await tester.pumpAndSettle(const Duration(seconds: 5));
      print('✓ Login ejecutado');

      // === PASO 2: VERIFICAR HOME ===
      // Esperar a que cargue el home
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      // Buscar el AppBar con "Wilobu"
      final homeTitle = find.text('Wilobu');
      expect(homeTitle, findsWidgets, reason: 'Debe estar en el Home');
      print('✓ Home cargado correctamente');

      // === PASO 3: NAVEGAR A ALERTAS ===
      // Buscar el ícono de notificaciones (campana)
      final alertsButton = find.byIcon(Icons.notifications);
      expect(alertsButton, findsOneWidget, reason: 'Debe haber botón de alertas');
      
      await tester.tap(alertsButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      print('✓ Navegando a historial de alertas...');

      // === PASO 4: VERIFICAR PANTALLA DE ALERTAS ===
      // Verificar que estamos en la pantalla de alertas
      final alertsTitle = find.text('Historial de Alertas');
      expect(alertsTitle, findsOneWidget, reason: 'Debe estar en Historial de Alertas');
      
      // Verificar tabs
      final receivedTab = find.text('Recibidas');
      final sentTab = find.text('Enviadas');
      expect(receivedTab, findsOneWidget);
      expect(sentTab, findsOneWidget);
      print('✓ Pantalla de Historial de Alertas visible');

      // === PASO 5: VERIFICAR TAB RECIBIDAS ===
      await tester.tap(receivedTab);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      // Verificar que hay contenido (alertas o mensaje vacío)
      final noAlertsMessage = find.text('No hay alertas recibidas');
      final alertCards = find.byType(Card);
      
      if (noAlertsMessage.evaluate().isNotEmpty) {
        print('ℹ️ No hay alertas recibidas (estado vacío)');
      } else if (alertCards.evaluate().isNotEmpty) {
        print('✓ Se encontraron ${alertCards.evaluate().length} alertas recibidas');
      }

      // === PASO 6: VERIFICAR TAB ENVIADAS ===
      await tester.tap(sentTab);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      final noSentMessage = find.text('No hay alertas enviadas');
      
      if (noSentMessage.evaluate().isNotEmpty) {
        print('ℹ️ No hay alertas enviadas (estado vacío)');
      } else {
        print('✓ Se encontraron alertas enviadas');
      }

      // === PASO 7: VOLVER AL HOME ===
      final backButton = find.byType(BackButton);
      if (backButton.evaluate().isNotEmpty) {
        await tester.tap(backButton);
      } else {
        // Usar navegación del sistema
        await tester.pageBack();
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      // Verificar que volvimos al home
      expect(find.text('Wilobu'), findsWidgets);
      print('✓ Volvió al Home correctamente');

      print('\n🎉 TEST DE NAVEGACIÓN COMPLETADO');
    });
  });
}

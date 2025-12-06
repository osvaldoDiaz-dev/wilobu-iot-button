import 'package:flutter_test/flutter_test.dart';
import 'package:wilobu_app/main.dart';

void main() {
  testWidgets('App inicia sin errores', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: WilobuApp()));

    // Verify que no hay errores
    expect(find.byType(MaterialApp), findsOneWidget);
    
    // Esperar a que el router se estabilice
    await tester.pumpAndSettle();
    
    // Verificar que estamos en LoginPage
    expect(find.text('Wilobu – Acceso'), findsWidgets);
  });

  testWidgets('Login form se renderiza correctamente', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: WilobuApp()));
    await tester.pumpAndSettle();

    // Buscar campos del formulario
    expect(find.byType(TextFormField), findsWidgets);
    expect(find.text('Conectar'), findsWidgets);
  });
}

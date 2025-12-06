#!/bin/bash
# Script de precompilación para WILOBU

echo ""
echo "📱 WILOBU - PRE-COMPILACIÓN PARA MÓVIL"
echo ""

cd wilobu_app

# 1. Verificar que existan todos los archivos críticos
echo "✓ Verificando estructura..."

FILES=(
    "lib/main.dart"
    "lib/router.dart"
    "lib/firebase_options.dart"
    "lib/firebase_providers.dart"
    "lib/theme/app_theme.dart"
    "lib/features/auth/presentation/login_page.dart"
    "lib/features/home/presentation/home_page.dart"
    "pubspec.yaml"
)

for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ Falta: $file"
        exit 1
    fi
done

echo "✓ Todos los archivos están presentes"
echo ""

# 2. Limpiar
echo "✓ Limpiando proyecto..."
flutter clean > /dev/null 2>&1

# 3. Obtener dependencias
echo "✓ Obteniendo dependencias..."
flutter pub get > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Error en flutter pub get"
    exit 1
fi

# 4. Verificar que no hay errores de sintaxis
echo "✓ Verificando sintaxis..."
dart analyze lib --fatal-infos > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "⚠️ Hay advertencias en el análisis"
    echo "Ejecuta 'flutter analyze' para ver detalles"
fi

echo ""
echo "✅ PRE-COMPILACIÓN EXITOSA"
echo ""
echo "Ahora ejecuta:"
echo "  flutter run"
echo ""
echo "Para ver logs en tiempo real:"
echo "  flutter run -v"
echo ""

#!/bin/bash
# Verificación de compilación de WILOBU App

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  WILOBU - VERIFICACIÓN DE COMPILACIÓN PARA MÓVIL      ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

cd wilobu_app

echo "1️⃣ Limpiando proyecto..."
flutter clean

echo ""
echo "2️⃣ Obteniendo dependencias..."
flutter pub get

if [ $? -ne 0 ]; then
    echo "❌ Error en flutter pub get"
    exit 1
fi

echo ""
echo "3️⃣ Verificando formato de código..."
dart format lib --set-exit-if-changed --dry-run

echo ""
echo "4️⃣ Analizando código..."
flutter analyze

echo ""
echo "5️⃣ Ejecutando tests..."
flutter test

echo ""
echo "✅ VERIFICACIÓN COMPLETADA"
echo ""
echo "Próximo paso para ejecutar en móvil:"
echo "  flutter run"
echo ""

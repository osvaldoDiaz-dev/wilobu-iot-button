#!/bin/bash
# Verificación rápida de que todo está funcional

echo "🔍 WILOBU v2.0 - VERIFICACIÓN RÁPIDA"
echo ""

# Verificar Flutter
echo "1️⃣ Verificando Flutter..."
if command -v flutter &> /dev/null; then
    FLUTTER_VERSION=$(flutter --version | head -1)
    echo "✅ $FLUTTER_VERSION"
else
    echo "❌ Flutter no instalado"
    exit 1
fi

echo ""
echo "2️⃣ Verificando dependencias de pubspec.yaml..."
cd wilobu_app
if [ -f "pubspec.yaml" ]; then
    echo "✅ pubspec.yaml encontrado"
    # Contar dependencias
    DEP_COUNT=$(grep -c "^  " pubspec.yaml)
    echo "   Dependencias: ~$DEP_COUNT"
else
    echo "❌ pubspec.yaml no encontrado"
    exit 1
fi

echo ""
echo "3️⃣ Verificando estructura de app..."
REQUIRED_FILES=(
    "lib/main.dart"
    "lib/router.dart"
    "lib/firebase_options.dart"
    "lib/firebase_providers.dart"
    "lib/theme/app_theme.dart"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file"
    else
        echo "❌ $file FALTA"
        exit 1
    fi
done

echo ""
echo "4️⃣ Verificando vistas..."
VIEWS=(
    "lib/features/auth/presentation/login_page.dart"
    "lib/features/auth/presentation/register_page.dart"
    "lib/features/home/presentation/home_page.dart"
)

for view in "${VIEWS[@]}"; do
    if [ -f "$view" ]; then
        echo "✅ $view"
    else
        echo "❌ $view FALTA"
    fi
done

cd ..

echo ""
echo "5️⃣ Verificando Firmware..."
if [ -f "wilobu_firmware/src/main.cpp" ]; then
    echo "✅ main.cpp presente"
else
    echo "❌ main.cpp FALTA"
fi

echo ""
echo "6️⃣ Verificando Cloud Functions..."
if [ -f "functions/index.js" ]; then
    echo "✅ Cloud Functions presente"
else
    echo "❌ Cloud Functions FALTA"
fi

echo ""
echo "7️⃣ Verificando Cloudflare Worker..."
if [ -f "cloudflare-worker/worker.js" ]; then
    echo "✅ Cloudflare Worker presente"
else
    echo "❌ Cloudflare Worker FALTA"
fi

echo ""
echo "✅ VERIFICACIÓN COMPLETADA"
echo ""
echo "Próximo paso:"
echo "  bash start_app.sh"

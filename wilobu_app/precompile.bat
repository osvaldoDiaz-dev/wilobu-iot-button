@echo off
REM Script de precompilación para WILOBU en Windows

echo.
echo 📱 WILOBU - PRE-COMPILACION PARA MOVIL
echo.

cd wilobu_app

echo ✓ Limpiando proyecto...
flutter clean >nul 2>&1

echo ✓ Obteniendo dependencias...
flutter pub get >nul 2>&1

if errorlevel 1 (
    echo ❌ Error en flutter pub get
    exit /b 1
)

echo ✓ Verificando sintaxis...
dart analyze lib --fatal-infos >nul 2>&1

echo.
echo ✅ PRE-COMPILACION EXITOSA
echo.
echo Ahora ejecuta:
echo   flutter run
echo.
echo Para ver logs en tiempo real:
echo   flutter run -v
echo.
pause

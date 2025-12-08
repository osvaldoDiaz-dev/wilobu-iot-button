@echo off
REM Script para iniciar WILOBU App en Windows
echo ===================================
echo WILOBU - Iniciando App
echo ===================================
echo.

cd wilobu_app

echo 1. Instalando dependencias...
call flutter pub get

if errorlevel 1 (
    echo ERROR: No se pudo instalar las dependencias
    exit /b 1
)

echo.
echo 2. Ejecutando en dispositivo conectado...
echo.
call flutter run

pause

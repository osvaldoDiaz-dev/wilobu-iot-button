#!/bin/bash

echo "==================================="
echo "WILOBU - Iniciando App"
echo "==================================="
echo ""

cd wilobu_app

echo "1. Instalando dependencias..."
flutter pub get

if [ $? -ne 0 ]; then
    echo "ERROR: No se pudo instalar las dependencias"
    exit 1
fi

echo ""
echo "2. Ejecutando en dispositivo conectado..."
echo ""
flutter run

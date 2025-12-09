#!/bin/bash
# Script de validación rápida del flujo SOS "Servidor como Fuente de Verdad"

echo "=== VALIDACIÓN FLUJO SOS ==="

# 1. Simular Disparo 1 (sin ubicación)
echo ""
echo "[1] Simulando Disparo 1: SOS sin ubicación"
curl -X POST \
  "http://localhost:5001/wilobu-d21b2/us-central1/heartbeat" \
  -H "Content-Type: application/json" \
  -d '{
    "deviceId": "TEST_DEVICE_001",
    "ownerUid": "test_user_123",
    "status": "sos_general",
    "lastLocation": null
  }'

echo ""
echo ""

# 2. Verificar que Firebase consultó lastLocation histórica
echo "[2] Verificando documento en Firestore..."
firebase firestore:get "users/test_user_123/devices/TEST_DEVICE_001" --project=wilobu-d21b2

echo ""
echo ""

# 3. Simular Disparo 2 (con coordenadas)
echo "[3] Simulando Disparo 2: SOS con ubicación precisa"
curl -X POST \
  "http://localhost:5001/wilobu-d21b2/us-central1/heartbeat" \
  -H "Content-Type: application/json" \
  -d '{
    "deviceId": "TEST_DEVICE_001",
    "ownerUid": "test_user_123",
    "status": "sos_general",
    "lastLocation": {
      "lat": -33.8688,
      "lng": 151.2093,
      "accuracy": 8.5
    }
  }'

echo ""
echo ""

# 4. Verificar que lastLocation se actualizó
echo "[4] Verificando lastLocation actualizado..."
firebase firestore:get "users/test_user_123/devices/TEST_DEVICE_001" --project=wilobu-d21b2

echo ""
echo "[✓] Validación completada"

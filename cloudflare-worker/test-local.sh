#!/bin/bash
# Script para probar el worker localmente con wrangler dev

echo "=== TEST LOCAL CLOUDFLARE WORKER ==="
echo ""

# Datos de prueba (simula lo que envía el ESP32)
PAYLOAD='{
  "deviceId": "AABBCCDDEEFF00",
  "ownerUid": "test123uid456",
  "status": "online",
  "timestamp": '$(date +%s)',
  "lastLocation": {
    "latitude": -33.4489,
    "longitude": -70.6693,
    "accuracy": 15.5
  }
}'

echo "Payload enviado:"
echo "$PAYLOAD" | jq .
echo ""

# Enviar POST al worker local (puerto 8787 por defecto)
echo "Enviando POST a http://localhost:8787..."
curl -X POST http://localhost:8787 \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  --verbose

echo ""
echo "=== FIN TEST ==="

# 🚨 WILOBU - Sistema IoT de Seguridad Personal

Sistema de emergencia para niños con TEA: dispositivo wearable ESP32 + LTE + GPS + App móvil.

## 📁 Estructura

```
wilobu_app/          → App Flutter (iOS/Android)
wilobu_firmware/     → Firmware ESP32 (C++/PlatformIO)
functions/           → Cloud Functions (Node.js - FCM)
cloudflare-worker/   → Proxy HTTP→HTTPS para Tier B/C
```

---

## 🚀 GUÍA DE EVALUACIÓN

### A. Probar App Móvil (5 min)

**1. Ejecutar app:**
```bash
cd wilobu_app
flutter pub get
flutter run
```

**2. Flujo de prueba:**
- Login con email/password cualquiera
- Dashboard → Botón "+" → Simula vinculación BLE
- Ver lista de dispositivos
- Gestión de contactos de emergencia
- Cambiar tema (Claro/Oscuro/Wilobu)

**3. Test automatizado:**
```bash
flutter test test/features/auth/login_flow_test.dart
```

---

### B. Probar Firmware ESP32 (Hardware requerido)

**Hardware soportado:**
- **Tier A:** LILYGO T-SIM7080G (HTTPS nativo)
- **Tier B:** ESP32 + A7670SA + Batería (Proxy Cloudflare)
- **Tier C:** ESP32 + A7670SA sin batería (Lab)

**1. Compilar y flashear:**
```bash
cd wilobu_firmware
pio run -t upload
pio device monitor
```

**2. Configuración crítica:**
Editar `platformio.ini` y descomentar hardware:
```ini
build_flags = 
    -D HARDWARE_B  # o HARDWARE_A, HARDWARE_C
```

**3. Flujo de vinculación:**
- Boot → LED parpadea → Apaga (Idle)
- Mantener Botón 1 (5s) → LED fijo (BLE Advertising)
- Conectar desde app → LED parpadea (Handshake)
- Éxito → LED apaga → Reinicia

**4. Test SOS:**
- Botón 1 (3s) → SOS General
- Botón 2 (3s) → SOS Médica
- Botón 3 (3s) → SOS Seguridad
- LED alerta parpadea rápido
- GPS cold start (45s)
- Envío a Firebase vía LTE

**5. Heartbeat:**
- Tier A: cada 15 min + Deep Sleep
- Tier B/C: cada 5 min + Conexión activa

---

### C. Probar Cloudflare Worker (Tier B/C)

**1. Deploy Worker:**
```bash
cd cloudflare-worker
npm install -g wrangler
wrangler login
wrangler secret put FIREBASE_API_KEY  # Pegar API Key de Firebase
wrangler deploy
```

**2. Actualizar firmware con URL:**
Copiar URL del deploy (ej. `wilobu-proxy.xxx.workers.dev`) y editar:
```cpp
// wilobu_firmware/include/ModemProxy.h línea 14
const char* proxyUrl = "wilobu-proxy.TU-SUBDOMAIN.workers.dev";
```

**3. Monitor de logs en tiempo real:**
```bash
wrangler tail wilobu-proxy
```

**4. Test manual:**
```bash
curl -X POST https://wilobu-proxy.xxx.workers.dev/heartbeat \
  -H "Content-Type: application/json" \
  -d '{
    "deviceId": "TEST123",
    "ownerUid": "test456",
    "status": "online",
    "timestamp": 1234567890,
    "lastLocation": {
      "latitude": -33.4489,
      "longitude": -70.6693,
      "accuracy": 15.5
    }
  }'
```

**Respuesta esperada (200):**
```json
{"success": true, "message": "Device state updated"}
```

---

### D. Verificar Cloud Functions

**Deploy:**
```bash
cd functions
npm install
firebase deploy --only functions
```

**Test notificación SOS:**
Verificar que al enviar SOS desde hardware:
1. Worker recibe alerta
2. Cloud Function `heartbeat` procesa
3. FCM envía push a contactos
4. App muestra notificación con mapa

---

## 🐛 Troubleshooting

| Problema | Solución |
|----------|----------|
| `flutter run` falla | `flutter clean && flutter pub get` |
| App no conecta Firebase | Verificar `google-services.json` en `android/app/` |
| Firmware no compila | Verificar `platformio.ini` tiene solo 1 `HARDWARE_X` |
| BLE no conecta | Permisos Bluetooth en Android/iOS |
| Worker 401 | `wrangler secret put FIREBASE_API_KEY` |
| Heartbeat no funciona | Verificar APN correcto en NVS |
| GPS sin fix | Esperar 45s cold start al aire libre |

---

## 📊 Arquitectura

```
[ESP32 + Módem LTE]
        ↓
   GPS + Botón SOS
        ↓
  ┌─────┴─────┐
  │           │
Tier A      Tier B/C
(HTTPS)     (HTTP → Cloudflare Worker → HTTPS)
  │           │
  └─────┬─────┘
        ↓
   Firebase Firestore
        ↓
  Cloud Functions
        ↓
   FCM Multicast
        ↓
[App Móvil Contactos]
```

---

## 📝 Cambios Recientes

### v2.0.1 (2025-12-08)
- ✅ Fix: Heartbeat no actualizaba `lastHeartbeat` → Enviaba solo 1 vez
- ✅ Fix: GPS formato inconsistente `lat/lng` → `latitude/longitude`
- ✅ Fix: Faltaba `timestamp` en heartbeat payload
- ✅ Cloudflare Worker: Configuración con secrets, no hardcoded
- ✅ Documentación unificada en README raíz

---

**Autor:** Osvaldo Díaz  
**Licencia:** MIT  
**Estado:** ✅ Producción


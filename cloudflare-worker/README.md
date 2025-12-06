# Cloudflare Worker - Proxy de Seguridad Wilobu

## Propósito

Este Worker actúa como intermediario de seguridad entre el hardware Tier B/C (ESP32 + A7670SA) y Firebase Firestore.

### Problema que resuelve

El módulo SIMCOM A7670SA **no soporta HTTPS directo** debido a limitaciones en el manejo de certificados SSL. Para mantener la seguridad de los datos:

1. El ESP32 envía datos en **HTTP plano** sobre la red LTE privada (cifrada por la operadora)
2. El Worker recibe la solicitud HTTP y la valida
3. El Worker **fuerza cifrado HTTPS/TLS 1.2** al retransmitir a Firebase
4. Firestore recibe los datos de forma segura

## Deployment

### Paso 1: Instalar Wrangler CLI

```bash
npm install -g wrangler
```

### Paso 2: Autenticarse

```bash
wrangler login
```

### Paso 3: Configurar API Key

Edita `worker.js` y reemplaza:

```javascript
const FIRESTORE_API_KEY = 'TU_API_KEY_AQUI';
```

Para obtener la API Key:
1. Ve a [Firebase Console](https://console.firebase.google.com/)
2. Selecciona tu proyecto `wilobu-d21b2`
3. Ve a **Configuración del proyecto** > **Claves web**
4. Copia la "Clave de API web"

### Paso 4: Desplegar

```bash
cd cloudflare-worker
wrangler deploy
```

El Worker quedará disponible en:
```
https://wilobu-proxy.workers.dev
```

## Uso desde el Firmware

El ESP32 envía un POST con este formato JSON:

```json
{
  "deviceId": "A4CF12FFEB80",
  "ownerUid": "firebase-user-uid-123",
  "status": "sos_general",
  "lastLocation": {
    "latitude": -33.4489,
    "longitude": -70.6693,
    "accuracy": 12.5
  }
}
```

## Seguridad

- ✅ Validación de campos requeridos (deviceId, ownerUid)
- ✅ Cifrado TLS 1.2 hacia Firebase
- ✅ API Key no expuesta en el hardware
- ✅ CORS deshabilitado (solo hardware autorizado)

## Logs

Ver logs en tiempo real:

```bash
wrangler tail
```

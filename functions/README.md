# Cloud Functions - Wilobu

Firebase Cloud Functions para notificaciones push del sistema Wilobu.

## Función Principal

### `onDeviceStatusChange`

Trigger de Firestore que se activa cuando cambia el `status` de un dispositivo.

**Path**: `users/{userId}/devices/{deviceId}`

**Lógica**:
1. Detecta cambio de status a `sos_*`
2. Lee array `emergencyContacts` del dispositivo
3. Por cada UID de contacto:
   - Busca documento en `users/{contactUid}`
   - Extrae tokens FCM (`fcmTokens[]`)
4. Envía notificación multicast a todos los dispositivos
5. Limpia tokens inválidos

## Estructura de Notificación

```javascript
{
  notification: {
    title: "🚨 ALERTA DE EMERGENCIA",
    body: "Usuario ha enviado una alerta [tipo]"
  },
  data: {
    type: "sos_general" | "sos_medica" | "sos_seguridad",
    deviceId: "string",
    userId: "string",
    timestamp: "ISO8601"
  },
  android: {
    priority: "high",
    notification: {
      channelId: "emergency_alerts",
      sound: "emergency_sound",
      priority: "max"
    }
  }
}
```

## Instalación

```bash
npm install
```

## Deployment

```bash
# Desarrollo
firebase deploy --only functions --project wilobu-d21b2

# Producción
firebase deploy --only functions:onDeviceStatusChange --project wilobu-d21b2
```

## Configuración

El proyecto usa Node.js **18** (LTS):

```json
{
  "engines": {
    "node": "18"
  }
}
```

## Dependencias

```json
{
  "firebase-admin": "^12.0.0",
  "firebase-functions": "^5.0.0"
}
```

## Logs

Ver logs en tiempo real:

```bash
firebase functions:log --project wilobu-d21b2
```

## Testing Local

```bash
firebase emulators:start --only functions,firestore
```

## Variables de Entorno

No requiere variables adicionales. Usa las credenciales por defecto de Firebase Admin SDK.

## Permisos Requeridos

La función necesita:
- Lectura en `users/{uid}`
- Lectura en `users/{userId}/devices/{deviceId}`
- No requiere permisos de escritura

## Costos Estimados

- **Invocaciones**: ~1 por alerta SOS
- **Lecturas Firestore**: 1 + N (donde N = número de contactos)
- **FCM**: Gratis hasta 1M mensajes/mes

## Mejoras Futuras

- [ ] Rate limiting para evitar spam
- [ ] Caché de tokens FCM
- [ ] Analytics de alertas
- [ ] Webhooks para servicios externos
- [ ] Integración con servicios de emergencia

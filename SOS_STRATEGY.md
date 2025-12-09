# Estrategia SOS: "Servidor como Fuente de Verdad"

## Problema Original
El firmware guardaba ubicaciones en NVS y las enviaba en alertas SOS. Esto causaba:
- Gasto innecesario de memoria en el dispositivo
- Duplicación de almacenamiento (NVS + Firestore)
- Complejidad en la sincronización

## Solución Implementada
**Backend Firebase es la fuente única de verdad para ubicaciones**.

### Flujo en Dos Disparos

#### **Disparo 1: Inmediato (Trigger - Sin Ubicación)**
```
1. Usuario mantiene botón SOS 3 segundos
2. LED parpadea RÁPIDO
3. Firmware envía POST:
   {
     "deviceId": "...",
     "ownerUid": "...",
     "status": "sos_general",
     "lastLocation": null  // ← IMPORTANTE: NULL
   }
4. Backend recibe alerta vacía
5. Backend consulta documento del dispositivo en Firestore
6. Backend obtiene `lastLocation` histórica ya guardada
7. Backend envía notificación con ubicación histórica
8. ✓ Alerta enviada en < 5 segundos
```

#### **Disparo 2: Preciso (Update - Con Ubicación)**
```
1. Firmware inicia búsqueda GPS en background
2. Espera hasta 45 segundos por fix válido
3. Si obtiene coordenadas válidas:
   - Firmware envía POST:
     {
       "deviceId": "...",
       "ownerUid": "...",
       "status": "sos_general",
       "lastLocation": {
         "lat": -33.8688,
         "lng": 151.2093,
         "accuracy": 8.5
       }  // ← Coordenadas precisas
     }
4. Backend actualiza `lastLocation` en Firestore
5. Backend envía segunda notificación con ubicación real
6. App muestra actualización en tiempo real
```

### Beneficios
✅ **Latencia < 5s**: Primera notificación llega inmediatamente
✅ **Precisión mejorada**: Segunda notificación con coordenadas reales
✅ **Menor gasto de RAM**: El firmware no guarda ubicaciones
✅ **Simplicidad**: Sin sincronización NVS
✅ **Escalabilidad**: Backend centralizado maneja el estado

### Cambios Requeridos

#### Firmware (`main.cpp`)
- ✅ `sendSOSAlert()` ahora envía dos disparos
- ✅ Disparo 1 con `lastLocation = null`
- ✅ Disparo 2 (opcional) con coordenadas si GPS disponible
- ✅ NO GUARDA ubicaciones en NVS

#### Backend (`functions/index.js`)
- ✅ `heartbeat` endpoint reconoce SOS sin ubicación
- ✅ Si `status.startsWith('sos_')` y `!lastLocation`:
  - Usa la `lastLocation` histórica del documento
- ✅ Si llega Disparo 2 con coordenadas:
  - Actualiza `lastLocation` en Firestore

#### App Flutter (`sos_alert_page.dart`)
- ✅ Muestra ubicación de `lastLocation` en tiempo real
- ✅ Si es NULL: "Ubicación no disponible"
- ✅ Se actualiza cuando Disparo 2 llega

#### Cloudflare Worker
- ✅ Simplemente retransmite (sin cambios)

### Flujo en Firestore

**Documento `users/{uid}/devices/{deviceId}`:**
```json
{
  "deviceId": "ABC123...",
  "ownerUid": "user123...",
  "status": "sos_general",  // ← Actualizado inmediatamente en Disparo 1
  "lastLocation": {
    "geopoint": GeoPoint(-33.8688, 151.2093),  // ← Histórica en Disparo 1
    "accuracy": 8.5,
    "timestamp": 2025-12-08T10:30:00Z
  },
  "lastSeen": 2025-12-08T10:30:00Z
}
```

**Sub-colección `alerts/{alertId}`** (creada automáticamente):
```json
{
  "type": "general",
  "sosType": "sos_general",
  "location": GeoPoint(-33.8688, 151.2093),  // ← Ubicación al momento del SOS
  "timestamp": 2025-12-08T10:30:00Z,
  "contactsNotified": [...]
}
```

### Testing

1. **Latencia (< 5s)**: Botón SOS → Notificación debe llegar < 5 seg
2. **Dos disparos**: Verificar que `status` aparece inmediatamente
3. **GPS**: Si hay fix, segunda notificación debe tener coordenadas nuevas
4. **Sin GPS**: Si no hay fix en 45s, solo Disparo 1 válido
5. **Histórica**: Ubicación viene de `lastLocation` existente, no del botón

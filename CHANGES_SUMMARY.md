# Resumen de Correcciones: Flujo SOS "Servidor como Fuente de Verdad"

## Problema Identificado
El firmware enviaba ubicaciones guardadas en NVS durante alertas SOS, violando el principio de "servidor como fuente de verdad".

## Solución Implementada

### 1. **Firmware** (`wilobu_firmware/src/main.cpp`)
✅ **Cambio principal**: Función `sendSOSAlert()` ahora implementa **2 disparos**

```cpp
// DISPARO 1: Inmediato con ubicación NULL
GPSLocation emptyLocation = {0.0, 0.0, 999.0, 0, false};
bool sent1 = modem->sendSOSAlert(deviceId, ownerUid, sosType, emptyLocation);

// DISPARO 2: Preciso (si GPS disponible)
if (gpsFound) {
    bool sent2 = modem->sendSOSAlert(deviceId, ownerUid, sosType, preciseLocation);
    lastLocation = preciseLocation; // Actualizar últimas coordenadas
}
```

**Beneficios:**
- Alerta llega en < 5 segundos (sin esperar GPS)
- Backend consulta `lastLocation` histórica automáticamente
- Si hay GPS, segunda notificación con coordenadas precisas
- **NO guarda ubicaciones en NVS** (firmware = stateless)

---

### 2. **Backend Firebase** (`functions/index.js`)

#### Cambio A: Enriquecimiento automático en `heartbeat`
```javascript
if (status && status.startsWith('sos_')) {
    if (!lastLocation || !lastLocation.lat || !lastLocation.lng) {
        // Disparo 1: Usar lastLocation histórica
        console.log(`SOS sin ubicación -> Usando lastLocation histórica`);
        // Mantener la ubicación que ya existe en Firestore
    } else {
        // Disparo 2: Actualizar con nuevas coordenadas
        update.lastLocation = {
            geopoint: new admin.firestore.GeoPoint(...),
            timestamp: ...
        };
    }
}
```

#### Cambio B: Soporte para GeoPoint en `processSosAlert()`
```javascript
// Soportar tanto { geopoint: GeoPoint } como GeoPoint directo
if (location.geopoint) {
    lat = location.geopoint._latitude;
    lng = location.geopoint._longitude;
} else if (location._latitude !== undefined) {
    lat = location._latitude;
    lng = location._longitude;
}
```

**Resultado:**
- Primera notificación con ubicación histórica (< 5s)
- Segunda notificación con ubicación precisa (si disponible)
- No requiere cambios en la app

---

### 3. **App Flutter** (sin cambios necesarios)
✅ App ya funciona correctamente, simplemente:
- Lee `lastLocation` de Firestore
- Muestra en mapa y notificaciones
- Se actualiza automáticamente cuando Disparo 2 llega

---

### 4. **Cloudflare Worker** (sin cambios)
✅ Solo retransmite solicitudes HTTP → HTTPS

---

## Flujo Completo en Acción

```
┌─ USUARIO PULSA BOTÓN SOS (3s)
│
├─► FIRMWARE (main.cpp)
│   │
│   ├─ DISPARO 1 (Inmediato)
│   │  └─ POST /heartbeat { status: "sos_general", lastLocation: null }
│   │     └─ ✓ Llega en < 5s
│   │
│   └─ Busca GPS en background...
│      ├─ Si fix en 45s:
│      │  └─ DISPARO 2 (Preciso)
│      │     └─ POST /heartbeat { status: "sos_general", lastLocation: {...} }
│      │
│      └─ Si NO fix:
│         └─ Solo Disparo 1 válido
│
├─► FIREBASE BACKEND (functions/index.js)
│   │
│   ├─ Disparo 1:
│   │  ├─ Recibe SOS sin ubicación
│   │  ├─ Consulta lastLocation histórica del documento
│   │  ├─ Envía notificación con ubicación histórica
│   │  └─ ✓ Contactos notificados en < 5s
│   │
│   └─ Disparo 2:
│      ├─ Recibe SOS con coordenadas
│      ├─ Actualiza lastLocation en Firestore
│      ├─ Envía segunda notificación con ubicación real
│      └─ ✓ Ubicación más precisa disponible
│
└─► APP FLUTTER (sos_alert_page.dart)
    ├─ Muestra notificación inmediata (Disparo 1)
    ├─ Actualiza mapa con ubicación real cuando llega Disparo 2
    └─ Usuario ve alerta + ubicación en tiempo real
```

---

## Validación

### Checklist de Prueba
- [ ] Botón SOS → Notificación en < 5 segundos
- [ ] Notificación 1 tiene ubicación (histórica)
- [ ] Si hay GPS → Notificación 2 con coordenadas nuevas
- [ ] Si NO hay GPS → Notificación 1 es final
- [ ] `lastLocation` en Firestore se actualiza correctamente
- [ ] Archivo `alertHistory` guardado con ubicación
- [ ] App muestra ubicación en mapa (si disponible)

---

## Beneficios Finales

| Aspecto | Antes | Después |
|---------|-------|---------|
| Latencia SOS | 45-60s (esperar GPS) | < 5s |
| Ubicación | Guardada en NVS | Firestore (servidor) |
| Precisión | Histórica (desactualizada) | Histórica (Disparo 1) + Precisa (Disparo 2) |
| Memoria RAM | Gastada en device | Disponible para GPS |
| Simplicidad | Compleja (sincronización) | Simple (2 disparos) |

---

## Archivos Modificados
- ✅ `wilobu_firmware/src/main.cpp` - Nueva función `sendSOSAlert()`
- ✅ `functions/index.js` - Enriquecimiento en `heartbeat` y `processSosAlert()`
- ✅ (Documentación) `SOS_STRATEGY.md` - Guía detallada
- ✅ (Test) `test-sos-flow.sh` - Script de validación

---

## Próximos Pasos
1. Compilar y flashear firmware actualizado
2. Deploy de Cloud Functions
3. Ejecutar `test-sos-flow.sh` para validar
4. Prueba end-to-end con dispositivo real

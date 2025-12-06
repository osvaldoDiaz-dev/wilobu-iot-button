# INTEGRACIÓN HARDWARE → FIREBASE

## Contrato de Datos: Batería y Ubicación

El firmware ESP32 debe actualizar estos campos en Firestore para que la App muestre datos reales.

### 📍 Estructura del Documento

**Ruta Firestore**: `users/{ownerUid}/devices/{deviceId}`

```json
{
  "ownerUid": "String (UID del propietario)",
  "deviceId": "String (MAC Address del ESP32)",
  "name": "Wilobu",  // ⚠️ VALOR POR DEFECTO - El usuario puede cambiarlo después en la app
  "status": "online | sos_general | sos_medica | sos_seguridad",
  
  // ✅ DATOS DE BATERÍA (REQUERIDO)
  "battery": 85,  // int (0-100) - Porcentaje de batería
  
  // ✅ DATOS DE UBICACIÓN (REQUERIDO)
  "lastLocation": {
    "geopoint": GeoPoint(latitude, longitude),  // Tipo GeoPoint de Firestore
    "timestamp": Timestamp  // Timestamp de Firestore (servidor)
  },
  
  "emergencyContacts": [...],
  "sosMessages": {...},
  "createdAt": Timestamp,
  "otaProgress": 0
}
```

---

## 🔋 Implementación: Envío de Batería

### C++ (ESP32 - PlatformIO)

```cpp
#include <ArduinoJson.h>
#include <FirebaseClient.h>

// Leer voltaje de batería (ejemplo con ADC)
int getBatteryPercentage() {
  int adcValue = analogRead(BATTERY_PIN);
  float voltage = (adcValue / 4095.0) * 3.3 * 2; // Ajustar según divisor de voltaje
  
  // Mapear voltaje a porcentaje (ejemplo: 3.0V = 0%, 4.2V = 100%)
  int percentage = map(voltage * 100, 300, 420, 0, 100);
  return constrain(percentage, 0, 100);
}

// Actualizar batería en Firestore cada 5 minutos
void updateBattery() {
  int batteryLevel = getBatteryPercentage();
  
  String path = "users/" + String(ownerUid) + "/devices/" + String(deviceId);
  
  FirebaseJson json;
  json.set("battery", batteryLevel);
  
  Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "", path.c_str(), json.raw(), "battery");
  
  Serial.printf("Batería actualizada: %d%%\n", batteryLevel);
}
```

---

## 📍 Implementación: Envío de Ubicación GPS

### C++ (ESP32 con Módulo GPS)

```cpp
#include <TinyGPS++.h>

TinyGPSPlus gps;
HardwareSerial gpsSerial(2); // RX=22, TX=21

void setupGPS() {
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
}

// Actualizar ubicación cuando haya fix GPS válido
void updateLocation() {
  if (!gps.location.isValid()) {
    Serial.println("Sin señal GPS");
    return;
  }
  
  double latitude = gps.location.lat();
  double longitude = gps.location.lng();
  
  String path = "users/" + String(ownerUid) + "/devices/" + String(deviceId);
  
  // Firestore requiere formato específico para GeoPoint
  FirebaseJson json;
  FirebaseJson geopoint;
  geopoint.set("_latitude", latitude);
  geopoint.set("_longitude", longitude);
  
  FirebaseJson location;
  location.set("geopoint", geopoint);
  location.set("timestamp", "FieldValue.serverTimestamp()"); // El servidor pone la hora
  
  json.set("lastLocation", location);
  
  Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "", path.c_str(), json.raw(), "lastLocation");
  
  Serial.printf("Ubicación: %.6f, %.6f\n", latitude, longitude);
}
```

---

## 🔄 Lógica de Actualización Periódica

```cpp
unsigned long lastBatteryUpdate = 0;
unsigned long lastLocationUpdate = 0;

const unsigned long BATTERY_INTERVAL = 5 * 60 * 1000;  // 5 minutos
const unsigned long LOCATION_INTERVAL = 2 * 60 * 1000; // 2 minutos (normal)
const unsigned long LOCATION_SOS_INTERVAL = 10 * 1000; // 10 segundos (SOS activo)

void loop() {
  unsigned long now = millis();
  
  // Leer GPS constantemente
  while (gpsSerial.available() > 0) {
    gps.encode(gpsSerial.read());
  }
  
  // Actualizar batería cada 5 minutos
  if (now - lastBatteryUpdate >= BATTERY_INTERVAL) {
    updateBattery();
    lastBatteryUpdate = now;
  }
  
  // Actualizar ubicación según estado
  unsigned long locationInterval = isSosActive ? LOCATION_SOS_INTERVAL : LOCATION_INTERVAL;
  
  if (now - lastLocationUpdate >= locationInterval && gps.location.isUpdated()) {
    updateLocation();
    lastLocationUpdate = now;
  }
}
```

---

## 🚨 Caso Especial: SOS con Ubicación en Tiempo Real

Cuando el usuario presiona un botón SOS, el firmware debe:

1. **Cambiar status** inmediatamente
2. **Enviar ubicación** cada 10 segundos (en lugar de cada 2 minutos)
3. **Enviar notificación** a contactos de emergencia

```cpp
void handleSOSButton(String sosType) {
  // 1. Cambiar status
  FirebaseJson json;
  json.set("status", sosType); // "sos_general", "sos_medica", "sos_seguridad"
  Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "", path.c_str(), json.raw(), "status");
  
  // 2. Enviar ubicación inmediata
  updateLocation();
  
  // 3. Activar modo alta frecuencia
  isSosActive = true;
  
  Serial.println("SOS ACTIVADO: " + sosType);
}
```

---

## 📊 Visualización en la App

La App Flutter ya está configurada para mostrar:

- **🔋 Batería**: Icono con color (verde >50%, naranja >20%, rojo ≤20%)
- **📍 Ubicación**: Texto "Hace Xmin/Xh/Xd" basado en `lastLocation.timestamp`
- **🗺️ Mapa SOS**: En pantalla de emergencia, muestra marcador en `lastLocation.geopoint`

### Ejemplo de Lectura en Flutter

```dart
class WilobuDevice {
  final int bateria;                 // battery
  final GeoPoint? lastLocation;      // lastLocation.geopoint
  final Timestamp? lastLocationTimestamp; // lastLocation.timestamp
  
  factory WilobuDevice.fromDoc(DocumentSnapshot doc) {
    final d = doc.data();
    final locData = d['lastLocation'] as Map<String, dynamic>?;
    
    return WilobuDevice(
      bateria: (d['battery'] as num?)?.toInt() ?? 0,
      lastLocation: locData?['geopoint'] as GeoPoint?,
      lastLocationTimestamp: locData?['timestamp'] as Timestamp?,
    );
  }
}
```

---

## ✅ Checklist de Validación

Para confirmar que el hardware está enviando datos correctamente:

1. **Verificar en Firebase Console**:
   - Ir a Firestore → `users/{uid}/devices/{deviceId}`
   - Confirmar que existe el campo `battery` (número 0-100)
   - Confirmar que existe `lastLocation` con subcampos `geopoint` y `timestamp`

2. **Probar en la App**:
   - Abrir HomePage y ver tarjeta del dispositivo
   - Debe mostrar `XX%` de batería con icono de color
   - Debe mostrar "Hace Xmin" (si hay datos) o "Sin ubicación"

3. **Logs del Hardware**:
   ```
   Batería actualizada: 85%
   Ubicación: -12.046374, -77.042793
   ```

---

## ⚠️ Notas Importantes

1. **GeoPoint Format**: Firestore requiere el tipo `GeoPoint` nativo. No enviar como string o array.
2. **Timestamp Server**: Usar `FieldValue.serverTimestamp()` para evitar problemas de zona horaria.
3. **Batería**: El firmware debe implementar calibración según el tipo de batería (LiPo 3.7V típicamente).
4. **GPS Fix**: Solo enviar ubicación cuando `gps.location.isValid()` sea `true`.
5. **Deep Sleep**: Si el dispositivo entra en deep sleep, debe despertar periódicamente para actualizar datos.

---

## 🔌 Aprovisionamiento Inicial (Primera Vinculación)

### Flujo de Vinculación

1. **Usuario presiona botón físico 5 segundos** → Activa modo BLE
2. **App escanea** → Detecta "Wilobu-XXXX" vía Bluetooth
3. **App envía** → `ownerUid` al dispositivo vía BLE
4. **Firmware crea documento** en Firestore:

```cpp
void createDeviceDocument(String ownerUid) {
  String macAddress = WiFi.macAddress();
  macAddress.replace(":", "");  // Remover separadores
  
  String path = "users/" + ownerUid + "/devices/" + macAddress;
  
  FirebaseJson json;
  json.set("ownerUid", ownerUid);
  json.set("deviceId", macAddress);
  json.set("name", "Wilobu");  // ⚠️ NOMBRE POR DEFECTO - Usuario lo cambia en app después
  json.set("status", "online");
  json.set("battery", 100);
  json.set("emergencyContacts", "[]");
  json.set("createdAt", "FieldValue.serverTimestamp()");
  
  Firebase.Firestore.createDocument(&fbdo, FIREBASE_PROJECT_ID, "", path.c_str(), json.raw());
  
  // ⚠️ IMPORTANTE: Apagar Bluetooth permanentemente después de provisionar
  btStop();
  Serial.println("✓ Dispositivo vinculado. Bluetooth deshabilitado.");
}
```

### ⚠️ Reglas Críticas

- **NO** pedir nombre al usuario durante vinculación
- **Valor por defecto**: `"Wilobu"` (genérico)
- Usuario puede personalizar después en: Configuración → Editar Nombre
- **Kill Switch BLE**: Apagar radio Bluetooth tras vinculación exitosa por seguridad

---

## 🔌 Dependencias del Firmware

```ini
[env:hardware_a]
lib_deps = 
    firebase-arduino-client @ ^4.3.1
    TinyGPSPlus @ ^1.0.3
    ArduinoJson @ ^6.21.3
```

**Archivo**: `wilobu_firmware/INTEGRACION_HARDWARE.md`

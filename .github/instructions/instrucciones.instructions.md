---
applyTo: '**'
---
INSTRUCCIONES DEL PROYECTO WILOBU (ENFOQUE MINIMALISTA)

ROL Y OBJETIVO
Actúa como un Ingeniero de Software Senior pragmático especializado en IoT.
Tu meta principal es lograr la funcionalidad requerida con la menor cantidad de líneas de código posible. Prioriza la simplicidad y el uso de librerías probadas.

1. FILOSOFIA DE DESARROLLO (LOW-CODE / HIGH-EFFICIENCY)
- NO a la Sobre-ingeniería: No implementes patrones complejos si una solución simple funciona.
- YAGNI (You Ain't Gonna Need It): No escribas código para el futuro.
- DRY (Don't Repeat Yourself): Si duplicas lógica, refactoriza inmediatamente.
- Preferencia de Librerías: Usa paquetes de la comunidad (ej. flutter_map, flutter_blue_plus, riverpod, Update.h).

2. CONTEXTO DEL SISTEMA
Proyecto: Wilobu (Sistema de seguridad IoT para niños con TEA).
- Hardware: ESP32 + Módems SIMCom.
- Móvil: Flutter (Android/iOS).
- Cloud: Firebase (Backend Serverless) + Cloudflare Workers.

3. REGLAS ESPECIFICAS POR TECNOLOGIA

A. FIRMWARE (C++ / PlatformIO)
- Estrategia de Build (platformio.ini):
  - `[env:tier_a]`: Flag `-D HARDWARE_TIER_A` (LILYGO/SIM7080).
  - `[env:tier_b]`: Flag `-D HARDWARE_TIER_B` (ESP32/A7670SA).
- Abstracción IModem (Comandos AT Específicos):
  - **Tier A (SIM7080G):** Usa familia estándar `AT+CGPS=1`, `AT+SHCONF` (HTTPS).
  - **Tier B (A7670SA) - IMPORTANTE:**
    - **GNSS (Diferente familia):**
      - ERROR COMÚN: `AT+CGPS=1` falla. NO USAR.
      - ENCENDIDO: `AT+CGNSSPWR=1` -> Esperar URC `+CGNSSPWR: READY!`.
      - CONFIG: `AT+CGNSSTST=1` -> `AT+CGNSSPORTSWITCH=0,1` (Salida NMEA).
      - LECTURA: `AT+CGNSSINFO` o `AT+CGPSINFO`.
      - REINICIO (Si no hay Fix): `AT+CGPSCOLD`.
    - **HTTP:**
      - Ciclo Estricto: `AT+HTTPINIT` -> `AT+HTTPPARA` -> `AT+HTTPACTION` -> `AT+HTTPTERM`.
      - Nota: `AT+HTTPTERM` devuelve ERROR si no hay sesión activa (siempre hacer INIT antes).
- Pines Hardware (Mapeo por Flag):
  - Tier A (LILYGO): Botones SOS=15, 4, 13; Power=27; Módem integrado.
  - Tier B (Dev): Botón SOS=15; TX=17 (UART2); RX=16 (UART2).
- Feedback Visual (Patrones LED):
  - Boot: `LED_LINK` parpadea -> Apaga (Idle).
  - Vinculación: `LED_LINK` FIJO (Esperando) -> PARPADEA (Conectando).
  - Alerta SOS: `LED_ALERT` parpadea RÁPIDO.
  - OTA: Ambos parpadean.
- Input Handling:
  - Botón 1 (Asistencia): 3s = SOS General | 5s = Modo Vinculación (Solo en Idle).
  - Botón 2 (Médica) / Botón 3 (Seguridad): 3s = SOS.
- Bluetooth (BLE): Solo activación manual. Security Kill tras éxito.
- Gestión de Energía y Boot:
  - **Secuencia de Arranque (Boot):**
    1. Check NVS: ¿Tiene `owner_uid`?
    2. **SI (Provisionado):** Inicia GNSS -> Fix -> Heartbeat Inicial -> Deep Sleep.
    3. **NO (Virgen):** Idle (Radio Off). Espera Botón 1 (5s).
  - **Ciclo Normal:** Despierta -> Envía -> Deep Sleep (Tier A: 15m / Tier B: 5m).

B. FLUTTER (Dart)
- Gestión de Estado: Riverpod.
- Arquitectura: MVVM Pragmática.
- Temas: Claro, Oscuro, "Wilobu Theme".
- Mapa y Monitoreo (Lógica "En Línea"):
  - **Cálculo Local:** `isOnline = (Ahora - device.lastHeartbeat) < (Intervalo + Buffer)`.
  - **Estado:** Verde (Online) / Gris (Offline).

C. CLOUD (Firebase & Cloudflare)
- Firestore (NoSQL):
  - Colección 'users/{uid}': Arrays `owned_devices` y `monitored_devices`.
  - Colección 'devices/{deviceId}':
    - ID Documento: ID Físico (MAC/Serial).
    - Campo `owner_uid`: UID dueño. **REGLA:** Debe ser `null` para vincular.
    - Campos: `lastLocation`, `cmd_reset`, `target_firmware_ver`.
    - Sub-colección 'alerts'.
- Cloudflare Workers: Proxy HTTP->HTTPS.

4. FLUJOS CRITICOS

A. VINCULACION (PROVISIONING SEGURO)
1. Activación: Botón 1 (5s) -> LED Fijo.
2. App: Lee ID -> Checkea `owner_uid == null` -> Escribe UID.
3. Hardware: Guarda NVS -> Kill BLE -> Reboot (Ejecuta Boot Provisionado).

B. FLUJO SOS (ESTRATEGIA DOBLE DISPARO)
1. Activación: Botón 3s -> `LED_ALERT` rápido.
2. DISPARO 1 (Inmediato):
   - Envía POST: `{ type: 'SOS', status: 'preliminary' }`.
   - Backend: Busca `lastLocation` histórica y notifica.
3. Espera Activa: Firmware espera Fix GNSS (Polling `AT+CGNSSINFO`).
4. DISPARO 2 (Preciso):
   - Envía POST: `{ lat: live_lat, lng: live_lng, status: 'precise' }`.
   - Backend: Actualiza mapa y notifica ubicación exacta.

C. ACTUALIZACION OTA
1. Heartbeat detecta versión nueva -> Descarga -> Flashea -> Reboot.

D. DESVINCULACION (RESET)
1. App (Soft): `cmd_reset=true` -> Heartbeat -> Borra NVS -> Firestore libera `owner_uid`.
2. Físico: Botón 1 (5s) -> Entra Vinculación -> App conecta y fuerza liberación.

F. PRUEBAS Y VALIDACIONES (QA)
1. Hardware: Latencia SOS < 5s. Precisión GNSS < 10m.
2. App: Prevención duplicados. Estado Online/Offline correcto.
3. Estrés: Debounce SOS.

5. FORMATO DE RESPUESTA
- Dame solo el código necesario.
- Omite explicaciones obvias.
- Si puedes borrar archivos o simplificar la estructura, sugiérelo.
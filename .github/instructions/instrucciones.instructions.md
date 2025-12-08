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
- Abstracción IModem:
  1. Tier A (SIM7080G): Cliente HTTPS Nativo (TLS 1.2). Directo a Firebase.
  2. Tier B (A7670SA): Cliente HTTP estándar. Vía Proxy (Cloudflare).
- Conectividad (APN):
  - Tier A (Prod): SIM Global **Hologram** (APN="hologram").
  - Tier B (Dev): SIM Local (APN="internet" o según proveedor).
- Pines Hardware:
  - Tier A (LILYGO): Botones SOS=GPIO 15, 4, 13; Power=GPIO 27.
  - Tier B (Dev): Botón SOS=GPIO 15; TX=17 (UART2 TX); RX=16 (UART2 RX).
- Feedback Visual (Patrones LED):
  - Boot/Inicio: `LED_LINK` parpadea -> Apaga (Idle).
  - Activación Aprovisionamiento: `LED_LINK` FIJO (Esperando).
  - Conectando App: `LED_LINK` PARPADEA.
  - Alerta SOS: `LED_ALERT` parpadea RÁPIDO.
  - OTA: Ambos parpadean.
- Input Handling:
  - Botón 1 (Asistencia): 3s = SOS General | 5s = Modo Vinculación (Solo en Idle).
  - Botón 2 (Médica) / Botón 3 (Seguridad): 3s = SOS.
- Bluetooth (BLE): Off por defecto. Solo activación manual. Security Kill tras éxito.
- Gestión de Energía (Heartbeat):
  - Tier A: 15 min + Deep Sleep.
  - Tier B: 5 min + Conexión activa.

B. FLUTTER (Dart)
- Gestión de Estado: Riverpod.
- Arquitectura: MVVM Pragmática.
- Temas: Claro, Oscuro, "Wilobu Theme".
- Mapa: Marcadores por color.

C. CLOUD (Firebase & Cloudflare)
- Firestore (NoSQL):
  - Colección 'users/{uid}': Arrays `owned_devices` y `monitored_devices`.
  - Colección 'devices/{deviceId}':
    - ID del Documento: ID Físico (MAC/Serial).
    - Campo `owner_uid`: UID del dueño. **REGLA:** Debe ser `null` para permitir vinculación.
    - Campos: `lastLocation`, `cmd_reset`, `target_firmware_ver`.
    - Sub-colección 'alerts'.
- Cloudflare Workers: Proxy HTTP->HTTPS.

4. FLUJOS CRITICOS

A. VINCULACION (PROVISIONING SEGURO)
1. Boot (Sin dueño): LED parpadea -> Apaga (Idle).
2. Activación: Usuario mantiene Botón 1 (5s) -> LED Fijo (Advertising).
3. Conexión & Validación:
   - App conecta BLE y lee Device ID.
   - **Check Cloud:** App consulta `devices/{deviceId}`.
   - **Bloqueo:** Si `owner_uid != null`, ERROR ("Ya tiene dueño").
   - **Éxito:** Si `owner_uid == null`, procede.
4. Escritura: App escribe UID en Hardware (NVS) y en Firestore (`owner_uid` = UID).
5. Finalización: Hardware apaga BLE (Security Kill) -> Reinicia.

B. FLUJO SOS (DOBLE DISPARO)
1. Botón 3s -> `LED_ALERT` rápido -> GNSS Cold Start.
2. Disparo 1: Memoria. Disparo 2: GNSS Preciso.

C. ACTUALIZACION OTA
1. Heartbeat detecta versión nueva -> Descarga -> Flashea -> Reboot.

D. DESVINCULACION (RESET)
1. App (Soft): `cmd_reset=true` -> Heartbeat -> Borra NVS -> Firestore libera `owner_uid`.
2. Físico: Botón 1 (5s) -> Entra Vinculación -> App conecta y fuerza liberación.

F. PRUEBAS Y VALIDACIONES (QA)
1. Hardware: Latencia SOS < 5s. Precisión GNSS < 10m.
2. App: Prevención de duplicados.
3. Estrés: Debounce SOS. Bloqueo BLE.

5. FORMATO DE RESPUESTA
- Dame solo el código necesario.
- Omite explicaciones obvias.
- Si puedes borrar archivos o simplificar la estructura, sugiérelo.
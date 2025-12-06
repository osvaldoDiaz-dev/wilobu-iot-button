---
applyTo: '**'
---
WILOBU - CONTEXTO TECNICO MAESTRO (MODO PRAGMATICO)

OBJETIVO SUPREMO Construir el sistema "Wilobu" (Dispositivo de Seguridad IoT Universal) funcional con la menor cantidad de código posible. Prioriza la velocidad, la simplicidad (principio KISS) y el uso de librerías existentes (riverpod_generator, freezed, flutter_map) sobre la arquitectura compleja.

PRINCIPIOS DE EFICIENCIA

Cero Sobre-Ingeniería: No escribas código para casos hipotéticos del futuro.

Backend Serverless: No crees servidores propios. Usa exclusivamente Firebase y Cloudflare Workers.

Agnosticismo: La App es un cliente "tonto" que visualiza datos. No debe contener lógica de hardware.

Generación de Código: Usa herramientas automáticas para reducir el código repetitivo (boilerplate) en Flutter.

MATRIZ DE HARDWARE (C++ / PLATFORMIO) El código de firmware debe compilar para 3 variantes usando directivas de preprocesador (#define).

VARIANTE 1: HARDWARE_A (Producto Final)

Placa: LILYGO T-PCIE + SIM7080G (Cat-M).

Red: HTTPS Directo (TLS 1.2).

APN: "hologram".

VARIANTE 2: HARDWARE_B (Prototipo Batería)

Placa: ESP32 DevKit + SIMCOM A7670SA (Cat-1).

Red: HTTP estándar apuntando a un Proxy en Cloudflare (el módem falla con SSL directo).

APN: Prepago local.

VARIANTE 3: HARDWARE_C (Demo USB)

Igual al Hardware B, pero sin batería (alimentado por USB).

MAPA DE PINES (CRITICO - NO CAMBIAR)

Modem TX: 21

Modem RX: 22

Botón SOS (General): 15

Botón Médica: 5

Botón Seguridad: 13

Switch Encendido: 27

LED Estado (Azul): 23

LED Auxiliar (Verde): 19 (Solo en Hardware B)

CONTRATO DE DATOS (FIREBASE JSON) Ruta del documento: users/{userId}/devices/{deviceId} Esquema estricto:

{ "ownerUid": "String (UID del dueño/admin)", "emergencyContacts": [ { "uid": "String", "name": "String", "relation": "String" } ], "sosMessages": { "general": "Texto alerta general", "medica": "Texto alerta médica", "seguridad": "Texto alerta seguridad" }, "status": "online" | "sos_general" | "sos_medica" | "sos_seguridad", "lastLocation": { "geopoint": "GeoPoint", "timestamp": "Timestamp" }, "deviceId": "String (MAC Address)", "otaProgress": 0 (Entero 0-100) }

REGLAS DE NEGOCIO Y PRIVACIDAD

Publico Universal: La UI debe usar lenguaje neutro (ej: "El usuario ha enviado una alerta").

Privacidad: El Bluetooth se usa UNA sola vez para el aprovisionamiento (enviar credenciales WiFi/User). Luego debe ejecutarse un "Kill Switch" que apague la radio Bluetooth permanentemente.

Proxy (Solo Hardware B/C): El ESP32 envía JSON plano a Cloudflare Worker -> El Worker valida y cifra el tráfico hacia Firebase.

ARQUITECTURA SIMPLIFICADA

Firmware: Usa una clase base abstracta IModem y dos implementaciones hijas (ModemHTTPS, ModemProxy). El archivo main.cpp instancia la correcta según el #define.

App: Usa Riverpod para la gestión de estado. Las pantallas de alerta escuchan directamente el Stream de Firestore.

FLUJO DE PANTALLAS (UI/UX FLUTTER) A. ONBOARDING (Primer uso):

LoginView / RegisterView: Autenticación básica.

EditProfileView: Guardar nombre del usuario principal.

DashboardView (Estado Vacío): Botón grande "Añadir Wilobu".

ProvisioningView (Tutorial Bluetooth):

Instrucción "Presiona Botón 1 por 5 segundos".

Escaneo BLE y Vinculación.

Envío de ownerUid al dispositivo.

Confirmación de éxito y redirección.

B. CONFIGURACION:

DeviceSettingsView: Menú de opciones. Botón "Desvincular" (Borra en Firebase y fuerza reinicio de fábrica en Hardware).

ManageContactsView: Buscador por Email. Si el email tiene cuenta en Wilobu (colección users), agrega su UID a la lista de contactos del dispositivo.

C. EMERGENCIA (Critico):

Trigger: La App detecta cambio de status a "sos_..." vía Stream.

SosAlertView (Pantalla Roja):

Muestra Mapa con marcador en lastLocation.

Muestra mensaje de consejo específico según el tipo de SOS.

Botones: "Llamar", "Cómo llegar", "Contactar Autoridades".

LOGICA AVANZADA Y SISTEMAS CRITICOS

A. GESTION DE ENERGIA Y ARRANQUE (FIRMWARE)

Secuencia de Encendido (Hardware B/C): El módem requiere un pulso físico en el pin PWRKEY (o gestión de energía) para arrancar. No basta con energizar la placa.

Deep Sleep: Si no hay SOS activo, el dispositivo debe dormir para ahorrar batería.

B. ACTUALIZACIONES OTA (FIRMWARE)

El dispositivo consulta la colección system/latest en Firestore.

Si la versión en la nube es mayor a la local, descarga el binario y actualiza.

Reporta el progreso en el campo otaProgress del dispositivo.

C. LOGICA DE NOTIFICACION (CLOUD FUNCTION)

Problema: La lista emergencyContacts solo tiene UIDs, no tokens de notificación.

Solución (Join en Backend):

Trigger: onUpdate en status == SOS.

Leer array emergencyContacts.

Buscar cada UID en la colección raíz users para obtener sus fcmTokens.

Enviar mensaje Multicast a todos los dispositivos encontrados.  
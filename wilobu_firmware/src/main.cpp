#include <Arduino.h>
// ===== LOGGING MINIMALISTA =====
// Macros para log por nivel: 0=ERROR, 1=INFO, 2=DEBUG
int logLevel = 1; // 0=ERROR, 1=INFO, 2=DEBUG (configurable)
#define LOG_ERROR(x) do { if (logLevel >= 0) { Serial.print("[ERROR] "); Serial.println(x); } } while(0)
#define LOG_INFO(x)  do { if (logLevel >= 1) { Serial.print("[INFO] "); Serial.println(x); } } while(0)
#define LOG_DEBUG(x) do { if (logLevel >= 2) { Serial.print("[DEBUG] "); Serial.println(x); } } while(0)
#include <NimBLEDevice.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <esp_mac.h>
#include <esp_sleep.h>

// ===== SELECCIÓN DE HARDWARE =====
// Selecciona la variante de hardware y módem a usar
// Descomentar SOLO UNA de las siguientes líneas:
// #define HARDWARE_A  // SIM7080G con HTTPS directo
// #define HARDWARE_B  // A7670SA con batería (Prototipo)
#define HARDWARE_C  // A7670SA sin batería (Laboratorio)

// Importar la clase correcta según hardware seleccionado
#ifdef HARDWARE_A
  #include "ModemHTTPS.h"
  #define MODEM_TYPE "SIM7080G (HTTPS)"
#else
  #include "ModemProxy.h"
  #define MODEM_TYPE "A7670SA (Proxy)"
#endif

// ===== PINES (NO CAMBIAR - CRÍTICO) =====
// Definición de pines para UART, botones y LEDs
// Cableado físico: D22=TX, D21=RX
#define PIN_MODEM_TX      17  // ESP32 TX2 (GPIO17) → Módem RX
#define PIN_MODEM_RX      16  // ESP32 RX2 (GPIO16) ← Módem TX
#define PIN_BTN_SOS       15  // Botón SOS General
#define PIN_BTN_MEDICA    5   // Botón SOS Médica
#define PIN_BTN_SEGURIDAD 13  // Botón SOS Seguridad
#define PIN_SWITCH_PWR    27  // Switch de encendido
#define PIN_LED_LINK      23  // LED Link/Estado (Azul) - Vinculación y estado general
#define PIN_LED_ALERT     19  // LED Alert (Rojo) - Solo alertas SOS

// ===== CONFIGURACIÓN BLE =====
// UUIDs y nombre BLE para aprovisionamiento
#define SERVICE_UUID           "0000ffaa-0000-1000-8000-00805f9b34fb"
#define CHAR_OWNER_UUID        "0000ffab-0000-1000-8000-00805f9b34fb"
#define CHAR_DEVICE_ID_UUID    "0000ffae-0000-1000-8000-00805f9b34fb"
#define CHAR_WIFI_SSID_UUID    "0000ffac-0000-1000-8000-00805f9b34fb"
#define CHAR_WIFI_PASS_UUID    "0000ffad-0000-1000-8000-00805f9b34fb"
#define DEVICE_NAME_PREFIX     "Wilobu-"

// ===== CONSTANTES =====
// Tiempos y parámetros globales del sistema
#define DEEP_SLEEP_ENABLED     false // Cambiar a true en producción
#define DEEP_SLEEP_TIME        3600  // 1 hora en modo idle
#define GPS_COLD_START_TIME    45000 // 45 segundos para GPS "cold start"
#define LOCATION_UPDATE_INTERVAL 30000 // Actualizar ubicación cada 30s
#define BUTTON_DEBOUNCE_TIME   100   // 100ms debounce
#define SOS_ALERT_TIMEOUT      5000  // Timeout para envío de alerta SOS
#ifdef HARDWARE_A
  #define HEARTBEAT_INTERVAL     900000UL // 15 minutos (Tier A)
#else
  #define HEARTBEAT_INTERVAL     300000UL // 5 minutos (Tier B/C)
#endif

// Ventana inicial para detectar desprovisionamiento rapido tras un unlink
#define HEARTBEAT_EARLY_WINDOW_MS 300000UL // 5 minutos
#define HEARTBEAT_FAST_INTERVAL   30000UL  // 30s en ventana inicial o cuando provisioned=false

// ===== MÁQUINA DE ESTADOS =====
// Controla el modo global del dispositivo
DeviceState deviceState = DeviceState::PROVISIONING;
DeviceState previousState = DeviceState::PROVISIONING;

// ===== VARIABLES GLOBALES =====
// Estado global, buffers y configuración persistente
HardwareSerial ModemSerial(2);  // UART2 para módem
IModem* modem = nullptr;
Preferences preferences;

// Identificación del dispositivo
String deviceId = "";
String ownerUid = "";
String modemApn = "";
String wifiSSID = "";
String wifiPassword = "";
bool isProvisioned = false;
bool lastHeartbeatOk = false; // true solo cuando el heartbeat recibe 2xx
unsigned long bootTimestamp = 0;

// Localización
GPSLocation lastLocation = {0.0, 0.0, 999.0, 0, false};
unsigned long lastLocationUpdate = 0;
unsigned long lastHeartbeat = 0;
bool firstHeartbeatSent = false;
bool isOTAInProgress = false;

// BLE
NimBLEServer* pServer = nullptr;
NimBLEAdvertising* pAdvertising = nullptr;
bool bleConnected = false;

// ===== CALLBACKS BLE =====
// Manejan eventos BLE: escritura de Owner UID y conexión/desconexión

// Callback para recibir Owner UID desde la app móvil
class OwnerUIDCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pCharacteristic) override {
        std::string value = pCharacteristic->getValue();
        // Validación mínima: longitud razonable
        if (value.length() >= 6 && value.length() <= 64) {
            ownerUid = String(value.c_str());
            Serial.println("[BLE] UID recibido: " + ownerUid);

            // Guardar en memoria no volátil (NVS)
            preferences.begin("wilobu", false);
            preferences.putString("ownerUid", ownerUid);
            preferences.putBool("provisioned", true);
            preferences.end();

            isProvisioned = true;
            Serial.println("[BLE] Dispositivo aprovisionado en NVS");
        } else {
            Serial.println("[BLE] UID recibido inválido (longitud)");
        }
    }
};

// Callback para eventos de conexión y desconexión BLE
class ServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer) override {
        bleConnected = true;
        Serial.println("[BLE] ✓ Cliente conectado - LED parpadeando");
        // LED parpadea durante handshake (se maneja en el loop de provisioning)
    }

    void onDisconnect(NimBLEServer* pServer) override {
        bleConnected = false;
        Serial.println("[BLE] ✗ Cliente desconectado");
        // Si se aprovisionó, mantener LED encendido; si no, volver a parpadear
    }
};

// ===== INICIALIZACIÓN BLE =====
// Prepara BLE para aprovisionamiento y advertising
void setupBLE() {
    Serial.println("[SETUP] Inicializando BLE para aprovisionamiento...");
    
    // Usar deviceId que ya se generó en setup()
    String shortId = deviceId.substring(6);
    String deviceName = String(DEVICE_NAME_PREFIX) + shortId;
    
    NimBLEDevice::init(deviceName.c_str());
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);
    
    // Crear servidor BLE
    pServer = NimBLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());
    
    // Crear servicio
    NimBLEService* pService = pServer->createService(SERVICE_UUID);
    
    // Característica para Owner UID (WRITE)
    NimBLECharacteristic* pCharOwner = pService->createCharacteristic(
        CHAR_OWNER_UUID,
        NIMBLE_PROPERTY::WRITE
    );
    pCharOwner->setCallbacks(new OwnerUIDCallbacks());
    
    // Característica de solo lectura para exponer el DeviceID real al móvil
    NimBLECharacteristic* pCharDeviceId = pService->createCharacteristic(
        CHAR_DEVICE_ID_UUID,
        NIMBLE_PROPERTY::READ
    );
    // Usar std::string explícitamente para evitar corrupción
    std::string deviceIdStr = deviceId.c_str();
    pCharDeviceId->setValue(deviceIdStr);
    Serial.print("[BLE] DeviceID characteristic set to: ");
    Serial.println(deviceId);
    
    // Iniciar servicio
    pService->start();
    
    // Configurar advertising
    pAdvertising = NimBLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->start();
    
    Serial.println("═════════════════════════════════════");
    Serial.println("  WILOBU EN MODO APROVISIONAMIENTO");
    Serial.println("═════════════════════════════════════");
    Serial.print("  Nombre BLE: ");
    Serial.println(deviceName);
    Serial.print("  Device ID:  ");
    Serial.println(deviceId);
    Serial.println("═════════════════════════════════════");
}

// ===== DECLARACIONES FORWARD =====
void attemptAutoRecovery();

// ===== INICIALIZACIÓN DEL MÓDEM =====
// Inicializa el módem y prueba varios baudrates
void setupModem() {
    Serial.println("[SETUP] Inicializando modem...");
        LOG_INFO("Inicializando modem...");
    
    // Probar múltiples baudrates
    long baudrates[] = {115200, 9600, 57600, 38400};
    int numBauds = 4;
    
    for (int b = 0; b < numBauds; b++) {
            LOG_INFO(String("Probando baudrate: ") + baudrates[b]);
        
        ModemSerial.begin(baudrates[b], SERIAL_8N1, PIN_MODEM_RX, PIN_MODEM_TX);
        delay(2000);
        
        #ifdef HARDWARE_A
            modem = new ModemHTTPS(&ModemSerial);
        #else
            modem = new ModemProxy(&ModemSerial, modemApn.c_str());
        #endif
        
        if (modem->init() && modem->connect()) {
            LOG_INFO(String("Conectado a ") + baudrates[b]);
            
            // Intentar auto-recuperación si no está aprovisionado
            if (!isProvisioned) {
                attemptAutoRecovery();
            }
            return;
        }
        
        delete modem;
        modem = nullptr;
        ModemSerial.end();
        delay(500);
    }
    
        LOG_ERROR("Fallo conexión módem");
        LOG_ERROR("  - Verifica cables TX/RX");
        LOG_ERROR("  - Verifica que el módem esté encendido");
    modem = nullptr;
}

// ===== INICIALIZACIÓN DE PINES =====
// Configura entradas (botones) y salidas (LEDs)
void setupPins() {
    Serial.println("[SETUP] Configurando pines...");
    
    // Entrada (botones con PULLUP interno)
    pinMode(PIN_BTN_SOS, INPUT_PULLUP);
    pinMode(PIN_BTN_MEDICA, INPUT_PULLUP);
    pinMode(PIN_BTN_SEGURIDAD, INPUT_PULLUP);
    pinMode(PIN_SWITCH_PWR, INPUT_PULLUP);
    
    // Salida (LEDs)
    pinMode(PIN_LED_LINK, OUTPUT);
    digitalWrite(PIN_LED_LINK, LOW);
    
    #if defined(HARDWARE_B) || defined(HARDWARE_C)
        pinMode(PIN_LED_ALERT, OUTPUT);
        digitalWrite(PIN_LED_ALERT, LOW);
    #endif
    
    Serial.println("[SETUP] ✓ Pines configurados");
}

// ===== ENVÍO DE ALERTA SOS (2 DISPAROS) =====
// Disparo 1: Inmediato con ubicación NULL (Backend busca lastLocation)
// Disparo 2: Preciso con coordenadas reales si GPS está disponible
void sendSOSAlert(const String& sosType) {
    Serial.println("[SOS] Iniciando alerta: " + sosType);

    if (!modem || !modem->isConnected()) {
        Serial.println("[SOS] ✗ Modem no disponible");
        return;
    }

    // LED parpadea RÁPIDO durante el proceso SOS
    unsigned long sosStart = millis();
    
    // ===== DISPARO 1: INMEDIATO (ubicación NULL) =====
    Serial.println("[SOS] DISPARO 1: Enviando alerta vacía (Backend consulta lastLocation)...");
    GPSLocation emptyLocation = {0.0, 0.0, 999.0, 0, false}; // GPS inválido
    bool sent1 = modem->sendSOSAlert(deviceId, ownerUid, sosType, emptyLocation);
    
    if (!sent1) {
        Serial.println("[SOS] ✗ DISPARO 1 falló");
        return;
    }
    Serial.println("[SOS] ✓ DISPARO 1 exitoso");
    
    // ===== ESPERA ACTIVA PARA GPS =====
    Serial.println("[SOS] Iniciando búsqueda GPS (cold start)...");
    modem->initGNSS();
    
    GPSLocation preciseLocation = {0.0, 0.0, 999.0, 0, false};
    unsigned long gpsStart = millis();
    bool gpsFound = false;
    
    while ((millis() - gpsStart) < GPS_COLD_START_TIME) {
        if (modem->getLocation(preciseLocation)) {
            if (preciseLocation.isValid) {
                gpsFound = true;
                Serial.printf("[SOS] ✓ GPS válido: %.6f, %.6f (accuracy: %.1fm)\n", 
                    preciseLocation.latitude, preciseLocation.longitude, preciseLocation.accuracy);
                break;
            }
        }
        delay(100);
    }
    
    // ===== DISPARO 2: PRECISO (si GPS disponible) =====
    if (gpsFound) {
        Serial.println("[SOS] DISPARO 2: Enviando ubicación precisa...");
        bool sent2 = modem->sendSOSAlert(deviceId, ownerUid, sosType, preciseLocation);
        if (sent2) {
            Serial.println("[SOS] ✓ DISPARO 2 exitoso");
            lastLocation = preciseLocation; // Actualizar últimas coordenadas
        } else {
            Serial.println("[SOS] ⚠️ DISPARO 2 falló (pero alerta ya enviada)");
        }
    } else {
        Serial.println("[SOS] ⚠️ GPS no disponible - Solo Disparo 1 enviado");
    }
    
    // Actualizar estado (updateLEDs() manejará el LED)
    deviceState = (sosType == "general") ? DeviceState::SOS_GENERAL :
                  (sosType == "medica") ? DeviceState::SOS_MEDICA : DeviceState::SOS_SEGURIDAD;

    // Volver a ONLINE tras completar la alerta para permitir nuevos disparos
    deviceState = DeviceState::ONLINE;
}

// ===== ACTIVAR MODO APROVISIONAMIENTO BLE =====
// Inicia el flujo de vinculación BLE con la app
void enterProvisioningMode() {
    Serial.println("\n[BLE] Activando modo aprovisionamiento...");
    deviceState = DeviceState::PROVISIONING;
    
    setupBLE();
    
    Serial.println("[LED] FIJO = Esperando App | PARPADEO = Conectando");
    
    unsigned long startTime = millis();
    while (!isProvisioned && (millis() - startTime) < 300000) {  // Timeout 5 min
        delay(50);
        
        if (bleConnected) {
            Serial.println("[PROVISIONING] Cliente conectado...");
        }
    }
    
    if (!isProvisioned) {
        Serial.println("[BLE] Timeout - Volviendo a IDLE");
        NimBLEDevice::deinit(true);
        deviceState = DeviceState::IDLE;
        return;
    }
    
    // Vinculación exitosa
    Serial.println("[BLE] Vinculacion exitosa");
    
    // Apagar BLE
    NimBLEDevice::deinit(true);
    bleConnected = false;
    
    // Dar tiempo a la app para crear el documento en Firestore (20s para evitar race condition)
    Serial.println("[BLE] Esperando 20s para que la app complete la vinculación en Firestore...");
    delay(20000);
    
    // Inicializar módem y pasar a ONLINE SIN REINICIAR
    setupModem();
    deviceState = DeviceState::ONLINE;
    Serial.println("[BLE] Modo ONLINE activado");
}

// ===== LECTURA DE BOTONES =====
// Detecta pulsaciones largas para SOS o vinculación
void checkButtons() {
    static unsigned long btnHoldStart = 0;
    static bool btnWasPressed = false;
    static bool actionTriggered = false;
    static unsigned long lastLogTime = 0;
    
    // Botón SOS principal - detectar hold
    if (digitalRead(PIN_BTN_SOS) == LOW) {
        if (!btnWasPressed) {
            btnWasPressed = true;
            btnHoldStart = millis();
            actionTriggered = false;
            Serial.println("[BTN] Botón SOS presionado - Iniciando contador...");
        }
        
        unsigned long holdTime = millis() - btnHoldStart;
        
        // Log cada segundo mientras se mantiene presionado
        if ((millis() - lastLogTime) >= 1000) {
            lastLogTime = millis();
            Serial.printf("[BTN] Manteniendo... %lu segundos\n", holdTime / 1000);
        }
        
        // 5 segundos = Activar vinculación (solo si no aprovisionado y en IDLE)
        if (holdTime >= 5000 && !actionTriggered && !isProvisioned && deviceState == DeviceState::IDLE) {
            actionTriggered = true;
            Serial.println("[BTN] ✓ 5s detectados - Activando vinculación");
            enterProvisioningMode();
            return;
        }
        
        // 3 segundos = Enviar SOS (solo si aprovisionado)
            if (holdTime >= 3000 && !actionTriggered && isProvisioned) {
            actionTriggered = true;
            Serial.println("[BTN] ✓ 3s detectados - Enviando SOS");
            sendSOSAlert("general");
            return;
        }
    } else {
        if (btnWasPressed && !actionTriggered) {
            unsigned long holdTime = millis() - btnHoldStart;
            Serial.printf("[BTN] Soltado después de %lu ms (sin acción)\n", holdTime);
        }
        btnWasPressed = false;
        actionTriggered = false;
    }
    
    // Solo verificar otros botones si está aprovisionado
    if (!isProvisioned) return;
    
    // Botón Médica
    if (digitalRead(PIN_BTN_MEDICA) == LOW) {
        delay(BUTTON_DEBOUNCE_TIME);
        if (digitalRead(PIN_BTN_MEDICA) == LOW) {
            unsigned long start = millis();
            while (digitalRead(PIN_BTN_MEDICA) == LOW && (millis() - start) < 3000) delay(50);
            if ((millis() - start) >= 3000) {
                sendSOSAlert("medica");
            }
        }
    }
    
    // Botón Seguridad
    if (digitalRead(PIN_BTN_SEGURIDAD) == LOW) {
        delay(BUTTON_DEBOUNCE_TIME);
        if (digitalRead(PIN_BTN_SEGURIDAD) == LOW) {
            unsigned long start = millis();
            while (digitalRead(PIN_BTN_SEGURIDAD) == LOW && (millis() - start) < 3000) delay(50);
            if ((millis() - start) >= 3000) {
                sendSOSAlert("seguridad");
            }
        }
    }
}

// ===== MÁQUINA DE ESTADOS PRINCIPAL =====
// Cambia el comportamiento según el estado global
void updateStateMachine() {
    if (deviceState == previousState) return;
    
    // Log compacto de transición (protección de rango)
    const char* stateNames[] = {"IDLE","PROVISIONING","ONLINE","SOS_GEN","SOS_MED","SOS_SEG","OTA"};
    int prevIdx = (int)previousState;
    int curIdx = (int)deviceState;
    const int STATE_COUNT = sizeof(stateNames) / sizeof(stateNames[0]);
    if (prevIdx >= 0 && prevIdx < STATE_COUNT && curIdx >= 0 && curIdx < STATE_COUNT) {
        Serial.printf("[STATE] %s -> %s\n", stateNames[prevIdx], stateNames[curIdx]);
    } else {
        Serial.printf("[STATE] %d -> %d\n", prevIdx, curIdx);
    }
    
    // Los LEDs se actualizan en updateLEDs(), no aquí
    previousState = deviceState;
}

// ===== ACTUALIZACIÓN DE LEDS =====
// Centraliza toda la lógica de LEDs para evitar conflictos
// Patrones según especificación:
// - Boot: LED_LINK parpadea -> Apaga (Idle)
// - Vinculación: LED_LINK FIJO (Esperando) -> PARPADEA (Conectando)
// - Alerta SOS: LED_ALERT parpadea RÁPIDO
// - OTA: Ambos parpadean
void updateLEDs() {
    // OTA: Ambos LEDs parpadean
    if (isOTAInProgress) {
        bool blink = (millis() / 300) % 2;
        digitalWrite(PIN_LED_LINK, blink);
        #if defined(HARDWARE_B) || defined(HARDWARE_C)
            digitalWrite(PIN_LED_ALERT, blink);
        #endif
        return;
    }
    
    // SOS: LED_ALERT parpadea RÁPIDO
    if (deviceState >= DeviceState::SOS_GENERAL && deviceState <= DeviceState::SOS_SEGURIDAD) {
        bool blinkFast = (millis() / 150) % 2;
        digitalWrite(PIN_LED_LINK, LOW);
        #if defined(HARDWARE_B) || defined(HARDWARE_C)
            digitalWrite(PIN_LED_ALERT, blinkFast);
        #endif
        return;
    }
    
    // Vinculación: LED_LINK FIJO (esperando) -> PARPADEA (conectando)
    if (deviceState == DeviceState::PROVISIONING) {
        if (bleConnected) {
            // Conectando: PARPADEA
            bool blink = (millis() / 200) % 2;
            digitalWrite(PIN_LED_LINK, blink);
        } else {
            // Esperando: FIJO
            digitalWrite(PIN_LED_LINK, HIGH);
        }
        #if defined(HARDWARE_B) || defined(HARDWARE_C)
            digitalWrite(PIN_LED_ALERT, LOW);
        #endif
        return;
    }

    // Modo ONLINE/IDLE: LED_LINK apagado (Idle)
    digitalWrite(PIN_LED_LINK, LOW);
    #if defined(HARDWARE_B) || defined(HARDWARE_C)
        digitalWrite(PIN_LED_ALERT, LOW);
    #endif
}

// ===== ACTUALIZACIÓN PERIÓDICA DE UBICACIÓN =====
// Actualiza la ubicación GPS periódicamente
void updateLocation() {
    if (!modem || !modem->isConnected()) {
        return;
    }
    
    if ((millis() - lastLocationUpdate) < LOCATION_UPDATE_INTERVAL) {
        return;
    }
    
    // Inicializar GPS si no está activo
    modem->initGNSS();
    
    // Obtener última ubicación
    if (modem->getLocation(lastLocation)) {
        Serial.print("[GPS] Ubicación actualizada: ");
        Serial.print(lastLocation.latitude, 6);
        Serial.print(", ");
        Serial.println(lastLocation.longitude, 6);
    }
    
    lastLocationUpdate = millis();
}

// ===== AUTO-RECUPERACIÓN DE APROVISIONAMIENTO =====
// Intenta recuperar el ownerUid desde Firestore si el dispositivo existe pero no está aprovisionado localmente
void attemptAutoRecovery() {
    if (isProvisioned || !modem || !modem->isConnected()) {
        return;
    }
    
    Serial.println("[AUTO-RECOVER] Dispositivo no aprovisionado localmente - Intentando recuperación...");
    String recoveredOwnerUid = modem->checkProvisioningStatus(deviceId);
    
    if (recoveredOwnerUid.length() > 0) {
        // ¡Encontrado! Aprovisionar automáticamente
        ownerUid = recoveredOwnerUid;
        preferences.begin("wilobu", false);
        preferences.putString("ownerUid", ownerUid);
        preferences.putBool("provisioned", true);
        preferences.end();
        
        isProvisioned = true;
        Serial.println("[AUTO-RECOVER] ✓✓✓ Dispositivo auto-aprovisionado exitosamente");
        Serial.println("[AUTO-RECOVER] Owner UID: " + ownerUid);
        
        // Cambiar a estado ONLINE
        deviceState = DeviceState::ONLINE;
    } else {
        Serial.println("[AUTO-RECOVER] Dispositivo no encontrado en Firestore - Requiere vinculación manual");
    }
}

// ===== ENVÍO PERIÓDICO DE HEARTBEAT =====
// Envía estado y ubicación periódicamente al backend
void sendHeartbeat() {
    if (!modem || !modem->isConnected() || !isProvisioned) {
        return;
    }

    // Verificar si está en proceso de desprovisión (provisioned=false en NVS)
    preferences.begin("wilobu", true);
    bool nvs_provisioned = preferences.getBool("provisioned", true);
    preferences.end();
    
    // Intervalo adaptativo para detección rápida de unlink
    unsigned long heartbeat_check_interval = HEARTBEAT_INTERVAL;
    
    // Si está desprovisionado, usar intervalo rápido
    if (!nvs_provisioned) {
        heartbeat_check_interval = HEARTBEAT_FAST_INTERVAL;
    }
    
    if ((millis() - lastHeartbeat) < heartbeat_check_interval) {
        return;
    }

    bool sent = modem->sendHeartbeat(ownerUid, deviceId, lastLocation);

    // Para ModemProxy (A7670SA) con HTTPS directo
    ModemProxy* m = (ModemProxy*)modem;
    if (m) {
        int st = m->getLastHttpStatus();
        lastHeartbeatOk = (st >= 200 && st < 300);
        Serial.printf("[HEARTBEAT] lastHeartbeatOk=%d (status=%d)\n", lastHeartbeatOk, st);
    }

    if (sent) {
        lastHeartbeat = millis();
        firstHeartbeatSent = true;
        Serial.println("[HEARTBEAT] ✓ Enviado");
    } else {
        Serial.println("[HEARTBEAT] ✗ Error");
    }
}
// ===== FACTORY RESET =====
// Borra configuración y reinicia el dispositivo
void performFactoryReset() {
    Serial.println("[RESET] ⚠️ Ejecutando Factory Reset...");
    
    // Borrar NVS
    preferences.begin("wilobu", false);
    preferences.clear();
    preferences.end();
    
    Serial.println("[RESET] ✓ NVS borrada");
    Serial.println("[RESET] Reiniciando...");
    delay(1000);
    ESP.restart();
}

// ===== VERIFICAR CMD_RESET =====
// Ejecuta reset si el backend lo solicita
void checkFactoryReset() {
    #ifdef HARDWARE_A
        ModemHTTPS* m = (ModemHTTPS*)modem;
        if (m && m->factoryResetPending) performFactoryReset();
    #else
        ModemProxy* m = (ModemProxy*)modem;
        if (m && m->factoryResetPending) performFactoryReset();
    #endif
}

// ===== SETUP =====
// Inicialización global: pines, BLE, módem, configuración
void setup() {
    Serial.begin(115200);
    delay(2000);
    bootTimestamp = millis();
    
    Serial.println("\n╔═════════════════════════════════════════════╗");
    Serial.println("║       WILOBU FIRMWARE v2.0 (IoT)           ║");
    Serial.println("║  Sistema de Seguridad Personal con LTE+GPS  ║");
    Serial.println("╚═════════════════════════════════════════════╝\n");
    
    // Inicializar componentes
    setupPins();
    
    // Boot: LED_LINK parpadea durante inicialización
    for (int i = 0; i < 6; i++) {
        digitalWrite(PIN_LED_LINK, i % 2);
        delay(120);
    }
    digitalWrite(PIN_LED_LINK, LOW); // Apagar tras boot
    
    // Cargar configuración desde NVS
    preferences.begin("wilobu", true);  // read-only
    isProvisioned = preferences.getBool("provisioned", false);
    logLevel = preferences.getInt("logLevel", 1); // Leer nivel de log desde NVS
    // Leer APN opcional para módem A7670SA
    modemApn = preferences.getString("apn", "");
    if (modemApn.length() > 0) {
        Serial.print("[NVS] APN: "); Serial.println(modemApn);
    }
    // Si no hay APN en NVS, usar APNs universales que funcionan con la mayoría de operadores
    // web.gprsuniversal es estándar Vodafone internacional y soportado por muchos operadores
    if (modemApn.length() == 0) {
        modemApn = String("web.gprsuniversal");
        Serial.println("[NVS] APN no configurado. Usando 'web.gprsuniversal' (universal compatible).");
    }
    if (isProvisioned) {
        ownerUid = preferences.getString("ownerUid", "");
        Serial.println("[NVS] Dispositivo aprovisionado previamente");
        Serial.print("[NVS]   Owner UID: ");
        Serial.println(ownerUid);
    } else {
        Serial.println("[NVS] Dispositivo no aprovisionado");
        Serial.println("[INFO] Mantén Botón SOS 5 segundos para vincular");
    }
    Serial.print("[NVS] logLevel: ");
    Serial.println(logLevel);
    preferences.end();
        // (Serial handler moved to loop)
    
    // Generar Device ID basado en MAC WiFi (siempre disponible)
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    char macStr[13];
    snprintf(macStr, sizeof(macStr), "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    deviceId = String(macStr);
    
    Serial.print("[DEVICE] ID: ");
    Serial.println(deviceId);
    
    // Intentar inicializar módem siempre (para auto-recovery)
    setupModem();
    
    // Si ya está aprovisionado: GNSS + Heartbeat inicial + Deep Sleep
    if (isProvisioned && modem && modem->isConnected()) {
        deviceState = DeviceState::ONLINE;
        Serial.println("\n[BOOT] Dispositivo provisionado -> Obteniendo ubicación inicial...");
        
        // Iniciar GNSS
        modem->initGNSS();
        unsigned long gpsStart = millis();
        bool fixObtained = false;
        
        // Esperar hasta 45s para obtener Fix
        while ((millis() - gpsStart) < GPS_COLD_START_TIME) {
            if (modem->getLocation(lastLocation) && lastLocation.isValid) {
                fixObtained = true;
                Serial.printf("[BOOT] ✓ GPS Fix: %.6f, %.6f\n", lastLocation.latitude, lastLocation.longitude);
                break;
            }
            delay(100);
        }
        
        if (!fixObtained) {
            Serial.println("[BOOT] ⚠️ GPS timeout - Enviando heartbeat sin ubicación");
            lastLocation.isValid = false;
        }
        
        // Enviar heartbeat inicial (con o sin GPS)
        Serial.println("[BOOT] Enviando heartbeat inicial...");
        bool sent = modem->sendHeartbeat(ownerUid, deviceId, lastLocation);

        // Actualizar flag de éxito para la lógica de LED (online visible)
        ModemProxy* m = (ModemProxy*)modem;
        if (m) {
            int st = m->getLastHttpStatus();
            lastHeartbeatOk = (st >= 200 && st < 300);
        }
        
        if (sent) {
            Serial.println("[BOOT] ✓ Heartbeat enviado");
            lastHeartbeat = millis();
            firstHeartbeatSent = true;
            #if DEEP_SLEEP_ENABLED
            // Deep Sleep según tier
            unsigned long sleepTime = HEARTBEAT_INTERVAL / 1000; // Convertir a segundos
            Serial.printf("[BOOT] Deep Sleep %lu segundos\n", sleepTime);
            esp_sleep_enable_timer_wakeup(sleepTime * 1000000ULL);
            esp_deep_sleep_start();
            #else
            Serial.println("[BOOT] Deep Sleep DESACTIVADO (dev mode)");
            #endif
        } else {
            Serial.println("[BOOT] ✗ Error en heartbeat - Continuando en modo normal");
        }
    } else if (!isProvisioned) {
        // Dispositivo virgen: IDLE con radio apagada
        deviceState = DeviceState::IDLE;
        Serial.println("\n[BOOT] Dispositivo NO provisionado -> IDLE (Radio OFF)");
        
        // Apagar módem para ahorrar energía
        if (modem) {
            Serial.println("[BOOT] Apagando radio LTE...");
        }
    }
}

// ===== LOOP PRINCIPAL =====
// Bucle principal: gestiona estado, botones, heartbeat y LEDs
void loop() {
    // Handler serial en runtime: comandos simples (ej. "log <0|1|2>")
    if (Serial.available()) {
        String cmd = Serial.readStringUntil('\n');
        cmd.trim();
        if (cmd.startsWith("log ")) {
            int lvl = cmd.substring(4).toInt();
            if (lvl >= 0 && lvl <= 2) {
                logLevel = lvl;
                preferences.begin("wilobu", false);
                preferences.putInt("logLevel", logLevel);
                preferences.end();
                Serial.print("[LOG] Nivel cambiado a: ");
                Serial.println(logLevel);
            } else {
                Serial.println("[LOG] Valor inválido. Usa 0=ERROR, 1=INFO, 2=DEBUG");
            }
        }
        else if (cmd.startsWith("apn ")) {
            String newApn = cmd.substring(4);
            modemApn = newApn;
            preferences.begin("wilobu", false);
            preferences.putString("apn", modemApn);
            preferences.end();
            Serial.print("[APN] Cambiado a: "); Serial.println(modemApn);
            Serial.println("[APN] Requiere reinicio para aplicar cambios. Usa 'restart'");
        }
        else if (cmd == "restart") {
            Serial.println("[RESTART] Reiniciando en 2s...");
            delay(2000);
            ESP.restart();
        }
        else if (cmd == "factory_reset") {
            Serial.println("[FACTORY_RESET] Limpiando NVS y reiniciando...");
            preferences.begin("wilobu", false);
            preferences.clear();  // Borrar todo
            preferences.end();
            Serial.println("[FACTORY_RESET] NVS limpiada. Reiniciando en 2s...");
            delay(2000);
            ESP.restart();
        }
        else if (cmd.startsWith("at ")) {
            String atcmd = cmd.substring(3);
            Serial.print("[SERIAL AT] Enviando a modem: "); Serial.println(atcmd);
            if (modem) {
                // send directly to modem UART and capture response
                ModemSerial.println(atcmd);
                unsigned long start = millis();
                String resp = "";
                while (millis() - start < 3000) {
                    while (ModemSerial.available()) {
                        char c = (char)ModemSerial.read();
                        resp += c;
                    }
                }
                if (resp.length() == 0) resp = "<no response>";
                Serial.print("[SERIAL AT] Resp: "); Serial.println(resp);
            } else {
                Serial.println("[SERIAL AT] Modem no inicializado");
            }
        }
        else if (cmd == "gps_test") {
            Serial.println("\n=== Test GPS A7670SA ===");
            if (modem) {
                // Test 1: Verificación básica
                Serial.println("\n[1] Verificando comunicación...");
                ModemSerial.println("AT");
                delay(500);
                while (ModemSerial.available()) {
                    Serial.write(ModemSerial.read());
                }
                
                // Test 2: Info del módulo
                Serial.println("\n[2] Info del módulo (AT+SIMCOMATI)...");
                ModemSerial.println("AT+SIMCOMATI");
                delay(1000);
                while (ModemSerial.available()) {
                    Serial.write(ModemSerial.read());
                }
                
                // Test 3: Estado GNSS Power
                Serial.println("\n[3] Consultando GNSS Power (AT+CGNSSPWR=?)...");
                ModemSerial.println("AT+CGNSSPWR=?");
                delay(1000);
                while (ModemSerial.available()) {
                    Serial.write(ModemSerial.read());
                }
                
                Serial.println("\n[4] Estado actual (AT+CGNSSPWR?)...");
                ModemSerial.println("AT+CGNSSPWR?");
                delay(1000);
                while (ModemSerial.available()) {
                    Serial.write(ModemSerial.read());
                }
                
                // Test 4: Energizar GNSS
                Serial.println("\n[5] Energizando GNSS (AT+CGNSSPWR=1)...");
                ModemSerial.println("AT+CGNSSPWR=1");
                delay(2000);
                while (ModemSerial.available()) {
                    Serial.write(ModemSerial.read());
                }
                
                // Test 5: Esperar READY
                Serial.println("\n[6] Esperando +CGNSSPWR: READY! (10s)...");
                unsigned long start = millis();
                while (millis() - start < 10000) {
                    if (ModemSerial.available()) {
                        Serial.write(ModemSerial.read());
                    }
                }
                
                // Test 6: Activar salida
                Serial.println("\n[7] Activando salida (AT+CGNSSTST=1)...");
                ModemSerial.println("AT+CGNSSTST=1");
                delay(1000);
                while (ModemSerial.available()) {
                    Serial.write(ModemSerial.read());
                }
                
                // Test 7: Puerto NMEA
                Serial.println("\n[8] Configurando puerto (AT+CGNSSPORTSWITCH=0,1)...");
                ModemSerial.println("AT+CGNSSPORTSWITCH=0,1");
                delay(1000);
                while (ModemSerial.available()) {
                    Serial.write(ModemSerial.read());
                }
                
                // Test 8: Intentar fix (5 intentos)
                Serial.println("\n[9] Intentando obtener fix GPS (5 intentos)...");
                for (int i = 0; i < 5; i++) {
                    Serial.printf("  Intento %d/5 (AT+CGPSINFO)...\n", i+1);
                    ModemSerial.println("AT+CGPSINFO");
                    delay(3000);
                    while (ModemSerial.available()) {
                        Serial.write(ModemSerial.read());
                    }
                }
                
                // Test 9: Info adicional
                Serial.println("\n[10] Info adicional (AT+CGNSSINFO)...");
                ModemSerial.println("AT+CGNSSINFO");
                delay(2000);
                while (ModemSerial.available()) {
                    Serial.write(ModemSerial.read());
                }
                
                Serial.println("\n=== Fin Test GPS ===\n");
            } else {
                Serial.println("[GPS_TEST] Modem no inicializado");
            }
        }
    }
    updateStateMachine();
    checkButtons();
    
    // Si no está aprovisionado, solo verificar botones
    if (!isProvisioned) {
        updateLEDs();
        delay(100);
        return;
    }
    
    // Modo ONLINE - funcionalidad completa
    updateLocation();
    sendHeartbeat();
    checkFactoryReset();
    updateLEDs();
    
    // Deep sleep si no está en SOS y pasó el intervalo
    bool inSOS = (deviceState == DeviceState::SOS_GENERAL || 
                  deviceState == DeviceState::SOS_MEDICA || 
                  deviceState == DeviceState::SOS_SEGURIDAD);
    
    #if DEEP_SLEEP_ENABLED
    if (!inSOS && firstHeartbeatSent && (millis() - lastHeartbeat) >= HEARTBEAT_INTERVAL) {
        Serial.println("[POWER] Ciclo completado -> Deep Sleep");
        unsigned long sleepTime = HEARTBEAT_INTERVAL / 1000;
        Serial.printf("[POWER] Deep Sleep %lu segundos\n", sleepTime);
        esp_sleep_enable_timer_wakeup(sleepTime * 1000000ULL);
        esp_deep_sleep_start();
    }
    #endif
    
    delay(100);
}

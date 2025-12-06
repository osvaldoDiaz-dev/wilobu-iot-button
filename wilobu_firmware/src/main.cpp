#include <Arduino.h>
#include <NimBLEDevice.h>
#include <ArduinoJson.h>
#include <Preferences.h>

// ===== SELECCIÓN DE HARDWARE =====
// Descomentar SOLO UNA de las siguientes líneas:
// #define HARDWARE_A  // SIM7080G con HTTPS directo
// #define HARDWARE_B  // A7670SA con batería (Prototipo)
#define HARDWARE_C  // A7670SA sin batería (Laboratorio)

// Importar la clase correcta según hardware
#ifdef HARDWARE_A
  #include "ModemHTTPS.h"
  #define MODEM_TYPE "SIM7080G (HTTPS)"
#else
  #include "ModemProxy.h"
  #define MODEM_TYPE "A7670SA (Proxy)"
#endif

// ===== PINES (NO CAMBIAR - CRÍTICO) =====
#define PIN_MODEM_TX      21
#define PIN_MODEM_RX      22
#define PIN_BTN_SOS       15  // Botón SOS General
#define PIN_BTN_MEDICA    5   // Botón SOS Médica
#define PIN_BTN_SEGURIDAD 13  // Botón SOS Seguridad
#define PIN_SWITCH_PWR    27  // Switch de encendido
#define PIN_LED_ESTADO    23  // LED estado (Azul)
#define PIN_LED_AUX       19  // LED auxiliar (Verde, solo Hardware B)

// ===== CONFIGURACIÓN BLE =====
#define SERVICE_UUID           "0000ffaa-0000-1000-8000-00805f9b34fb"
#define CHAR_OWNER_UUID        "0000ffab-0000-1000-8000-00805f9b34fb"
#define CHAR_WIFI_SSID_UUID    "0000ffac-0000-1000-8000-00805f9b34fb"
#define CHAR_WIFI_PASS_UUID    "0000ffad-0000-1000-8000-00805f9b34fb"
#define DEVICE_NAME_PREFIX     "Wilobu-"

// ===== CONSTANTES =====
#define DEEP_SLEEP_TIME        3600  // 1 hora en modo idle
#define GPS_COLD_START_TIME    45000 // 45 segundos para GPS "cold start"
#define LOCATION_UPDATE_INTERVAL 30000 // Actualizar ubicación cada 30s
#define BUTTON_DEBOUNCE_TIME   100   // 100ms debounce
#define SOS_ALERT_TIMEOUT      5000  // Timeout para envío de alerta SOS

// ===== MÁQUINA DE ESTADOS =====
DeviceState deviceState = DeviceState::PROVISIONING;
DeviceState previousState = DeviceState::PROVISIONING;

// ===== VARIABLES GLOBALES =====
HardwareSerial ModemSerial(2);  // UART2 para módem
IModem* modem = nullptr;
Preferences preferences;

// Identificación del dispositivo
String deviceId = "";
String ownerUid = "";
String wifiSSID = "";
String wifiPassword = "";
bool isProvisioned = false;

// Localización
GPSLocation lastLocation = {0.0, 0.0, 999.0, 0, false};
unsigned long lastLocationUpdate = 0;

// BLE
NimBLEServer* pServer = nullptr;
NimBLEAdvertising* pAdvertising = nullptr;
bool bleConnected = false;

// ===== CALLBACKS BLE =====

// Callback para recibir Owner UID
class OwnerUIDCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pCharacteristic) override {
        std::string value = pCharacteristic->getValue();
        if (value.length() > 0) {
            ownerUid = String(value.c_str());
            Serial.println("[BLE] ✓ UID Recibido: " + ownerUid);
            
            // Guardar en memoria no volátil (NVS)
            preferences.begin("wilobu", false);
            preferences.putString("ownerUid", ownerUid);
            preferences.putBool("provisioned", true);
            preferences.end();
            
            isProvisioned = true;
            Serial.println("[BLE] ✓ Dispositivo aprovisionado en memoria");
        }
    }
};

// Callback para conexión/desconexión BLE
class ServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer) override {
        bleConnected = true;
        Serial.println("[BLE] ✓ Cliente conectado");
        digitalWrite(PIN_LED_ESTADO, HIGH);
    }

    void onDisconnect(NimBLEServer* pServer) override {
        bleConnected = false;
        Serial.println("[BLE] ✗ Cliente desconectado");
        digitalWrite(PIN_LED_ESTADO, LOW);
    }
};

// ===== INICIALIZACIÓN BLE =====
void setupBLE() {
    Serial.println("[SETUP] Inicializando BLE para aprovisionamiento...");
    
    NimBLEDevice::init("");
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);
    
    // Generar Device ID basado en MAC
    std::string macStr = NimBLEDevice::getAddress().toString();
    deviceId = String(macStr.c_str());
    deviceId.replace(":", "");
    deviceId.toUpperCase();
    
    String shortId = deviceId.substring(6);
    String deviceName = String(DEVICE_NAME_PREFIX) + shortId;
    
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
    
    // Iniciar servicio
    pService->start();
    
    // Configurar advertising
    pAdvertising = NimBLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setName(deviceName.c_str());
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

// ===== INICIALIZACIÓN DEL MÓDEM =====
void setupModem() {
    Serial.println("[SETUP] Inicializando módem...");
    
    ModemSerial.begin(115200, SERIAL_8N1, PIN_MODEM_RX, PIN_MODEM_TX);
    delay(1000);
    
    #ifdef HARDWARE_A
        modem = new ModemHTTPS(&ModemSerial);
        Serial.println("[SETUP] ✓ Hardware A: SIM7080G + HTTPS directo");
    #else
        modem = new ModemProxy(&ModemSerial);
        Serial.println("[SETUP] ✓ Hardware B/C: A7670SA + Proxy Cloudflare");
    #endif
    
    if (!modem->init()) {
        Serial.println("[ERROR] Fallo al inicializar módem");
        return;
    }
    
    if (!modem->connect()) {
        Serial.println("[WARN] No conectado a red aún, reintentar después");
        return;
    }
    
    Serial.println("[SETUP] ✓ Módem conectado a la red");
}

// ===== INICIALIZACIÓN DE PINES =====
void setupPins() {
    Serial.println("[SETUP] Configurando pines...");
    
    // Entrada (botones con PULLUP interno)
    pinMode(PIN_BTN_SOS, INPUT_PULLUP);
    pinMode(PIN_BTN_MEDICA, INPUT_PULLUP);
    pinMode(PIN_BTN_SEGURIDAD, INPUT_PULLUP);
    pinMode(PIN_SWITCH_PWR, INPUT_PULLUP);
    
    // Salida (LEDs)
    pinMode(PIN_LED_ESTADO, OUTPUT);
    digitalWrite(PIN_LED_ESTADO, LOW);
    
    #if defined(HARDWARE_B) || defined(HARDWARE_C)
        pinMode(PIN_LED_AUX, OUTPUT);
        digitalWrite(PIN_LED_AUX, LOW);
    #endif
    
    Serial.println("[SETUP] ✓ Pines configurados");
}

// ===== ENVÍO DE ALERTA SOS =====
void sendSOSAlert(const String& sosType) {
    Serial.println("[SOS] Enviando alerta: " + sosType);
    
    // Inicializar GPS si no está habilitado
    if (!modem->initGNSS()) {
        Serial.println("[SOS] Advertencia: No se pudo inicializar GPS");
    }
    
    // Esperar a que GPS tenga fix (máximo GPS_COLD_START_TIME ms)
    unsigned long gpsStart = millis();
    while (!lastLocation.isValid && (millis() - gpsStart) < GPS_COLD_START_TIME) {
        if (modem->getLocation(lastLocation)) {
            break;
        }
        delay(100);
    }
    
    // Construir JSON de alerta
    StaticJsonDocument<512> doc;
    doc["deviceId"] = deviceId;
    doc["ownerUid"] = ownerUid;
    doc["status"] = "sos_" + sosType;
    doc["sosType"] = sosType;
    doc["timestamp"] = millis();
    
    if (lastLocation.isValid) {
        doc["lastLocation"]["latitude"] = lastLocation.latitude;
        doc["lastLocation"]["longitude"] = lastLocation.longitude;
        doc["lastLocation"]["accuracy"] = lastLocation.accuracy;
    } else {
        // Usar última ubicación conocida
        doc["lastLocation"]["latitude"] = 0.0;
        doc["lastLocation"]["longitude"] = 0.0;
        doc["lastLocation"]["accuracy"] = 999.0;
    }
    
    String jsonData;
    serializeJson(doc, jsonData);
    
    // Parpadear LED para indicar alerta
    for (int i = 0; i < 5; i++) {
        digitalWrite(PIN_LED_ESTADO, HIGH);
        delay(100);
        digitalWrite(PIN_LED_ESTADO, LOW);
        delay(100);
    }
    
    // Enviar alerta
    if (modem && modem->isConnected()) {
        if (modem->sendSOSAlert(sosType, lastLocation)) {
            Serial.println("[SOS] ✓ Alerta enviada correctamente");
            digitalWrite(PIN_LED_ESTADO, HIGH); // LED encendido en alerta
        } else {
            Serial.println("[SOS] ✗ Fallo al enviar alerta");
        }
    } else {
        Serial.println("[SOS] ✗ Sin conexión a la red");
    }
    
    // Cambiar estado
    deviceState = (sosType == "general") ? DeviceState::SOS_GENERAL :
                  (sosType == "medica") ? DeviceState::SOS_MEDICA : DeviceState::SOS_SEGURIDAD;
}

// ===== LECTURA DE BOTONES =====
void checkButtons() {
    static unsigned long lastButtonTime = 0;
    
    // Botón SOS General (GPIO 15)
    if (digitalRead(PIN_BTN_SOS) == LOW && (millis() - lastButtonTime) > BUTTON_DEBOUNCE_TIME) {
        delay(BUTTON_DEBOUNCE_TIME);
        if (digitalRead(PIN_BTN_SOS) == LOW) {
            Serial.println("[BTN] Presionado: SOS GENERAL");
            sendSOSAlert("general");
            lastButtonTime = millis();
            while (digitalRead(PIN_BTN_SOS) == LOW) {
                delay(50);
            }
        }
    }
    
    // Botón SOS Médica (GPIO 5)
    if (digitalRead(PIN_BTN_MEDICA) == LOW && (millis() - lastButtonTime) > BUTTON_DEBOUNCE_TIME) {
        delay(BUTTON_DEBOUNCE_TIME);
        if (digitalRead(PIN_BTN_MEDICA) == LOW) {
            Serial.println("[BTN] Presionado: SOS MÉDICA");
            sendSOSAlert("medica");
            lastButtonTime = millis();
            while (digitalRead(PIN_BTN_MEDICA) == LOW) {
                delay(50);
            }
        }
    }
    
    // Botón SOS Seguridad (GPIO 13)
    if (digitalRead(PIN_BTN_SEGURIDAD) == LOW && (millis() - lastButtonTime) > BUTTON_DEBOUNCE_TIME) {
        delay(BUTTON_DEBOUNCE_TIME);
        if (digitalRead(PIN_BTN_SEGURIDAD) == LOW) {
            Serial.println("[BTN] Presionado: SOS SEGURIDAD");
            sendSOSAlert("seguridad");
            lastButtonTime = millis();
            while (digitalRead(PIN_BTN_SEGURIDAD) == LOW) {
                delay(50);
            }
        }
    }
}

// ===== MÁQUINA DE ESTADOS PRINCIPAL =====
void updateStateMachine() {
    if (deviceState == previousState) return;
    
    Serial.println("[STATE-MACHINE] Transición de estado:");
    Serial.print("  De: ");
    
    switch (previousState) {
        case DeviceState::IDLE:
            Serial.println("IDLE");
            break;
        case DeviceState::PROVISIONING:
            Serial.println("PROVISIONING");
            break;
        case DeviceState::ONLINE:
            Serial.println("ONLINE");
            break;
        case DeviceState::SOS_GENERAL:
            Serial.println("SOS_GENERAL");
            break;
        case DeviceState::SOS_MEDICA:
            Serial.println("SOS_MEDICA");
            break;
        case DeviceState::SOS_SEGURIDAD:
            Serial.println("SOS_SEGURIDAD");
            break;
        case DeviceState::OTA_UPDATE:
            Serial.println("OTA_UPDATE");
            break;
    }
    
    Serial.print("  A:  ");
    
    switch (deviceState) {
        case DeviceState::IDLE:
            Serial.println("IDLE");
            // Habilitar Deep Sleep
            modem->disableGNSS();
            break;
        case DeviceState::PROVISIONING:
            Serial.println("PROVISIONING");
            break;
        case DeviceState::ONLINE:
            Serial.println("ONLINE");
            digitalWrite(PIN_LED_ESTADO, LOW);
            break;
        case DeviceState::SOS_GENERAL:
            Serial.println("SOS_GENERAL");
            digitalWrite(PIN_LED_ESTADO, HIGH);
            break;
        case DeviceState::SOS_MEDICA:
            Serial.println("SOS_MEDICA");
            digitalWrite(PIN_LED_ESTADO, HIGH);
            break;
        case DeviceState::SOS_SEGURIDAD:
            Serial.println("SOS_SEGURIDAD");
            digitalWrite(PIN_LED_ESTADO, HIGH);
            break;
        case DeviceState::OTA_UPDATE:
            Serial.println("OTA_UPDATE");
            break;
    }
    
    previousState = deviceState;
}

// ===== ACTUALIZACIÓN PERIÓDICA DE UBICACIÓN =====
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

// ===== SETUP =====
void setup() {
    Serial.begin(115200);
    delay(2000);
    
    Serial.println("\n╔═════════════════════════════════════════════╗");
    Serial.println("║       WILOBU FIRMWARE v2.0 (IoT)           ║");
    Serial.println("║  Sistema de Seguridad Personal con LTE+GPS  ║");
    Serial.println("╚═════════════════════════════════════════════╝\n");
    
    // Inicializar componentes
    setupPins();
    
    // Cargar configuración desde NVS
    preferences.begin("wilobu", true);  // read-only
    isProvisioned = preferences.getBool("provisioned", false);
    if (isProvisioned) {
        ownerUid = preferences.getString("ownerUid", "");
        Serial.println("[NVS] ✓ Dispositivo aprovisionado previamente");
        Serial.print("[NVS]   Owner UID: ");
        Serial.println(ownerUid);
    } else {
        Serial.println("[NVS] ✗ Dispositivo no aprovisionado aún");
    }
    preferences.end();
    
    // Esperar aprovisionamiento BLE si es necesario
    if (!isProvisioned) {
        setupBLE();
        deviceState = DeviceState::PROVISIONING;
        
        Serial.println("\n[WAIT] Esperando aprovisionamiento BLE...");
        unsigned long startTime = millis();
        while (!isProvisioned && (millis() - startTime) < 300000) {  // Timeout 5 minutos
            delay(100);
            // Parpadear LED mientras espera
            if ((millis() / 500) % 2 == 0) {
                digitalWrite(PIN_LED_ESTADO, HIGH);
            } else {
                digitalWrite(PIN_LED_ESTADO, LOW);
            }
        }
        
        if (!isProvisioned) {
            Serial.println("[FATAL] Timeout de aprovisionamiento BLE");
            // Reiniciar
            ESP.restart();
        }
    }
    
    digitalWrite(PIN_LED_ESTADO, HIGH);
    delay(2000);
    
    // Desactivar BLE después del aprovisionamiento (KILL SWITCH)
    if (bleConnected || pServer != nullptr) {
        Serial.println("[BLE] KILL SWITCH: Desactivando BLE permanentemente...");
        NimBLEDevice::deinit(true);
        bleConnected = false;
    }
    
    // Inicializar módem
    setupModem();
    
    // Cambiar estado a ONLINE
    deviceState = DeviceState::ONLINE;
    
    Serial.println("\n[SETUP] ✓ Sistema completamente inicializado");
    Serial.println("[MAIN] Ingresando al loop principal...\n");
}

// ===== LOOP PRINCIPAL =====
void loop() {
    // Actualizar máquina de estados
    updateStateMachine();
    
    // Lectura de botones (siempre activa)
    checkButtons();
    
    // Actualizar ubicación periódicamente
    updateLocation();
    
    // Indicador visual según estado
    switch (deviceState) {
        case DeviceState::ONLINE:
            // Parpadeo suave cada 2 segundos
            if ((millis() / 1000) % 2 == 0) {
                digitalWrite(PIN_LED_ESTADO, LOW);
            } else {
                digitalWrite(PIN_LED_ESTADO, HIGH);
            }
            break;
            
        case DeviceState::IDLE:
            // LED apagado en modo idle
            digitalWrite(PIN_LED_ESTADO, LOW);
            break;
            
        case DeviceState::SOS_GENERAL:
        case DeviceState::SOS_MEDICA:
        case DeviceState::SOS_SEGURIDAD:
            // LED encendido en modo SOS
            digitalWrite(PIN_LED_ESTADO, HIGH);
            break;
            
        default:
            break;
    }
    
    delay(100);
}

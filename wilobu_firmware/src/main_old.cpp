#include <Arduino.h>
#include <NimBLEDevice.h>
#include <ArduinoJson.h>
#include <TinyGPSPlus.h>
#include <Preferences.h>

// Selección de hardware
#ifdef HARDWARE_A
  #include "ModemHTTPS.h"
#else
  #include "ModemProxy.h"
#endif

// --- PINES (NO CAMBIAR - CRÍTICO) ---
#define PIN_MODEM_TX      21
#define PIN_MODEM_RX      22
#define PIN_BTN_SOS       15
#define PIN_BTN_MEDICA    5
#define PIN_BTN_SEGURIDAD 13
#define PIN_SWITCH_PWR    27
#define PIN_LED_ESTADO    23
#define PIN_LED_AUX       19  // Solo Hardware B

// --- CONFIGURACIÓN BLE ---
#define SERVICE_UUID      "0000ffaa-0000-1000-8000-00805f9b34fb"
#define DEVICE_NAME_PREFIX "Wilobu-"

// --- VARIABLES GLOBALES ---
HardwareSerial ModemSerial(2);  // UART2
HardwareSerial GPSSerial(1);     // UART1 para GPS
TinyGPSPlus gps;
IModem* modem = nullptr;
Preferences preferences;

// Estado
String deviceId = "";
String ownerUid = "";
String currentStatus = "online";
bool bleEnabled = true;
bool isProvisioned = false;
unsigned long lastLocationUpdate = 0;
const unsigned long LOCATION_INTERVAL = 30000; // 30 segundos

// GPS
float lastLatitude = 0.0;
// --- CARACTERÍSTICA PARA RECIBIR OWNER UID ---
class OwnerCallbacks: public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pCharacteristic) {
      std::string value = pCharacteristic->getValue();
      if (value.length() > 0) {
        ownerUid = String(value.c_str());
        Serial.println(">> UID Recibido: " + ownerUid);
        
        // Guardar en memoria no volátil (NVS)
        preferences.begin("wilobu", false);
        preferences.putString("ownerUid", ownerUid);
        preferences.putBool("provisioned", true);
        preferences.end();
        
        isProvisioned = true;
        
        // KILL SWITCH: Desactivar BLE permanentemente
        Serial.println(">> KILL SWITCH: Desactivando BLE...");
        bleEnabled = false;
        NimBLEDevice::deinit(true);
        
        Serial.println(">> Dispositivo aprovisionado exitosamente");
      }
    }
};      Serial.println(">> KILL SWITCH: Desactivando BLE...");
        bleEnabled = false;
        NimBLEDevice::deinit(true);
        
        // Guardar en EEPROM o preferencias (TODO)
        Serial.println(">> Dispositivo aprovisionado exitosamente");
      }
    }
};

// Callbacks conexión BLE
class MyServerCallbacks: public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer) {
      deviceConnected = true;
      Serial.println(">> App Conectada!");
      digitalWrite(PIN_LED_ESTADO, HIGH);
    };

    void onDisconnect(NimBLEServer* pServer) {
      deviceConnected = false;
      Serial.println(">> App Desconectada");
      digitalWrite(PIN_LED_ESTADO, LOW);
      if (bleEnabled) {
        pAdvertising->start();
      }
    }
};

void setupBLE() {
  NimBLEDevice::init("");

  // Generar Device ID (MAC)
  std::string mac = NimBLEDevice::getAddress().toString();
  deviceId = String(mac.c_str());
  deviceId.replace(":", "");
  deviceId.toUpperCase();
  
  String shortId = deviceId.substring(8);
  String finalName = String(DEVICE_NAME_PREFIX) + shortId;
  
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);
  
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  
  // Característica para escribir OwnerUID
  NimBLECharacteristic *pCharOwner = pService->createCharacteristic(
    "0000ffab-0000-1000-8000-00805f9b34fb",
    NIMBLE_PROPERTY::WRITE
  );
  pCharOwner->setCallbacks(new OwnerCallbacks());
  
  pService->start();

  pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setName(finalName.c_str());
  pAdvertising->start();
  
  Serial.println("-------------------------------------------");
  Serial.print("   WILOBU ACTIVO: "); Serial.println(finalName);
  Serial.print("   Device ID: "); Serial.println(deviceId);
  Serial.println("-------------------------------------------");
}

void setupModem() {
  Serial.println("[SETUP] Inicializando Modem...");
  
  ModemSerial.begin(115200, SERIAL_8N1, PIN_MODEM_RX, PIN_MODEM_TX);
  
  #ifdef HARDWARE_A
    modem = new ModemHTTPS(&ModemSerial);
    Serial.println("[SETUP] Hardware A: SIM7080G + HTTPS");
  #else
    modem = new ModemProxy(&ModemSerial);
    Serial.println("[SETUP] Hardware B/C: A7670SA + Proxy");
  #endif
  
  modem->init();
  modem->connect();
}

void setupGPS() {
  Serial.println("[SETUP] Inicializando GPS...");
  
  // UART1 para GPS (ajustar pines según hardware)
  // Hardware A/B: usar pines específicos del módulo
  GPSSerial.begin(9600, SERIAL_8N1, 16, 17); // RX=16, TX=17 (ajustar según diseño)
  
  Serial.println("[SETUP] GPS iniciado, esperando señal...");
}

void setupPins() {
  pinMode(PIN_BTN_SOS, INPUT_PULLUP);
  pinMode(PIN_BTN_MEDICA, INPUT_PULLUP);
  pinMode(PIN_BTN_SEGURIDAD, INPUT_PULLUP);
  pinMode(PIN_SWITCH_PWR, INPUT_PULLUP);
  pinMode(PIN_LED_ESTADO, OUTPUT);
  
  #if defined(HARDWARE_B) || defined(HARDWARE_C)
    pinMode(PIN_LED_AUX, OUTPUT);
  #endif
  
  digitalWrite(PIN_LED_ESTADO, LOW);
}

void sendStatusToFirebase(const String& status) {
  if (!modem || !modem->isConnected()) {
    Serial.println("[ERROR] Modem no conectado");
    return;
  }
  
  if (ownerUid.isEmpty()) {
    Serial.println("[ERROR] Dispositivo no aprovisionado");
    return;
  }
  
  // Construir JSON completo para el Worker
  JsonDocument doc;
  doc["deviceId"] = deviceId;
  doc["ownerUid"] = ownerUid;
  doc["status"] = status;
  doc["updatedAt"] = millis();
  
  // Incluir última ubicación conocida
  if (lastLatitude != 0.0 && lastLongitude != 0.0) {
    doc["lastLocation"]["latitude"] = lastLatitude;
    doc["lastLocation"]["longitude"] = lastLongitude;
    doc["lastLocation"]["accuracy"] = gpsFixed ? gps.hdop.hdop() : 999.0;
  }
  
  String jsonData;
  serializeJson(doc, jsonData);
  
  Serial.println("[FIREBASE] Actualizando status: " + status);
  modem->sendToFirebase("", jsonData); // Path vacío, el Worker construye la ruta
  
  currentStatus = status;
}

void sendLocationToFirebase() {
  if (!modem || !modem->isConnected()) return;
  if (ownerUid.isEmpty()) return;
  
  // Leer GPS real desde TinyGPSPlus
  float lat = lastLatitude;
  float lon = lastLongitude;
  
  // Si no hay fix GPS, usar última ubicación conocida
  if (!gpsFixed || (lat == 0.0 && lon == 0.0)) {
    Serial.println("[GPS] Sin señal, usando última ubicación conocida");
  }
  
  // Construir JSON completo para el Worker
  JsonDocument doc;
  doc["deviceId"] = deviceId;
  doc["ownerUid"] = ownerUid;
  doc["status"] = currentStatus;
  doc["lastLocation"]["latitude"] = lat;
  doc["lastLocation"]["longitude"] = lon;
  doc["lastLocation"]["accuracy"] = gpsFixed ? gps.hdop.hdop() : 999.0;
  
  String jsonData;
  serializeJson(doc, jsonData);
  
  Serial.print("[GPS] Enviando: ");
  Serial.print(lat, 6);
  Serial.print(", ");
  Serial.println(lon, 6);
  
  modem->sendToFirebase("", jsonData); // Path vacío, el Worker construye la ruta
}

void checkButtons() {
  // Botón SOS General (activo en LOW por PULLUP)
  if (digitalRead(PIN_BTN_SOS) == LOW) {
    delay(100); // Debounce
    if (digitalRead(PIN_BTN_SOS) == LOW) {
      Serial.println("[ALERTA] SOS GENERAL");
      digitalWrite(PIN_LED_ESTADO, HIGH);
      sendStatusToFirebase("sos_general");
      sendLocationToFirebase();
      while(digitalRead(PIN_BTN_SOS) == LOW); // Esperar liberación
    }
  }
  
  // Botón Médica
  if (digitalRead(PIN_BTN_MEDICA) == LOW) {
    delay(100);
    if (digitalRead(PIN_BTN_MEDICA) == LOW) {
      Serial.println("[ALERTA] SOS MÉDICA");
      digitalWrite(PIN_LED_ESTADO, HIGH);
      sendStatusToFirebase("sos_medica");
      sendLocationToFirebase();
      while(digitalRead(PIN_BTN_MEDICA) == LOW);
    }
  }
  
  // Botón Seguridad
  if (digitalRead(PIN_BTN_SEGURIDAD) == LOW) {
    delay(100);
void setup() {
  Serial.begin(115200);
  Serial.println("\n\n===========================================");
  Serial.println("  WILOBU FIRMWARE v2.0");
  Serial.println("===========================================\n");
  
  setupPins();
  
  // Cargar configuración desde NVS
  preferences.begin("wilobu", true); // read-only
  isProvisioned = preferences.getBool("provisioned", false);
  if (isProvisioned) {
    ownerUid = preferences.getString("ownerUid", "");
    Serial.println("[NVS] Dispositivo ya aprovisionado: " + ownerUid);
  }
  preferences.end();
  
  // Solo iniciar BLE si no está aprovisionado
  if (!isProvisioned) {
    setupBLE();
    
    Serial.println("[SETUP] Esperando aprovisionamiento BLE...");
    while (!isProvisioned) {
      delay(1000);
      digitalWrite(PIN_LED_ESTADO, !digitalRead(PIN_LED_ESTADO)); // Parpadeo
    }
  }
  
  Serial.println("[SETUP] Dispositivo aprovisionado!");
  digitalWrite(PIN_LED_ESTADO, HIGH);
  delay(2000);
  
  setupModem();
  setupGPS();
  
  // Enviar status inicial
  sendStatusToFirebase("online");
  sendLocationToFirebase();
  
  Serial.println("[SETUP] Sistema listo");
}

void updateGPS() {
  while (GPSSerial.available() > 0) {
    char c = GPSSerial.read();
    if (gps.encode(c)) {
      if (gps.location.isValid()) {
        lastLatitude = gps.location.lat();
        lastLongitude = gps.location.lng();
        gpsFixed = true;
        
        // Solo mostrar en debug cada 10 segundos
        static unsigned long lastPrint = 0;
        if (millis() - lastPrint > 10000) {
          Serial.print("[GPS] Fix: ");
          Serial.print(lastLatitude, 6);
          Serial.print(", ");
          Serial.print(lastLongitude, 6);
          Serial.print(" | Sats: ");
          Serial.println(gps.satellites.value());
          lastPrint = millis();
        }
      } else {
        gpsFixed = false;
      }
    }
  }
}

void loop() {
  // Actualizar GPS continuamente
  updateGPS();
  
  // Verificar botones
  checkButtons();
  
  // Actualizar ubicación periódicamente
  if (millis() - lastLocationUpdate > LOCATION_INTERVAL) {
    sendLocationToFirebase();
    lastLocationUpdate = millis();
  }
  
  // Parpadeo LED para indicar vida
  if (currentStatus == "online") {
    digitalWrite(PIN_LED_ESTADO, (millis() / 1000) % 2);
  }
  
  delay(100);
}   sendLocationToFirebase();
    lastLocationUpdate = millis();
  }
  
  // Parpadeo LED para indicar vida
  if (currentStatus == "online") {
    digitalWrite(PIN_LED_ESTADO, (millis() / 1000) % 2);
  }
  
  delay(100);
}
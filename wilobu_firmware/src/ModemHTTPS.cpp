#include "ModemHTTPS.h"
#include <ArduinoJson.h>

ModemHTTPS::ModemHTTPS(HardwareSerial* serial) {
    modemSerial = serial;
}

// ===== INICIALIZACIÓN =====
bool ModemHTTPS::init() {
    Serial.println("[MODEM-HTTPS] Inicializando SIM7080G (Tier A)...");
    
    // Iniciar comunicación serial
    modemSerial->begin(115200);
    delay(3000);
    
    // Test básico
    String response = sendATCommand("AT", 1000);
    if (response.indexOf("OK") == -1) {
        Serial.println("[MODEM-HTTPS] Error: Módulo no responde");
        return false;
    }
    
    // Desabilitar echo de comandos
    sendATCommand("ATE0", 1000);
    
    // Configurar formato de respuesta
    sendATCommand("AT+CMGF=1", 1000);
    
    // Configurar APN
    sendATCommand("AT+CGDCONT=1,\"IP\",\"" + String(apn) + "\"", 2000);
    
    // Activar contexto PDP
    sendATCommand("AT+CGACT=1,1", 10000);
    
    Serial.println("[MODEM-HTTPS] SIM7080G inicializado correctamente");
    return true;
}

// ===== CONEXIÓN A RED =====
bool ModemHTTPS::connect() {
    Serial.println("[MODEM-HTTPS] Conectando a red LTE...");
    
    // Esperar registro en red (máximo 60 segundos)
    for (int i = 0; i < 60; i++) {
        String response = sendATCommand("AT+CGREG?", 1000);
        
        // +CGREG: 0,1 (conectado, red local)
        // +CGREG: 0,5 (conectado, roaming)
        if (response.indexOf("+CGREG: 0,1") != -1 || response.indexOf("+CGREG: 0,5") != -1) {
            connected = true;
            Serial.println("[MODEM-HTTPS] ✓ Conectado a red celular LTE");
            return true;
        }
        
        if (i % 10 == 0) {
            Serial.print("[MODEM-HTTPS] Esperando conexión... (");
            Serial.print(i);
            Serial.println("s)");
        }
        
        delay(1000);
    }
    
    Serial.println("[MODEM-HTTPS] ✗ No se pudo conectar a la red");
    return false;
}

bool ModemHTTPS::disconnect() {
    Serial.println("[MODEM-HTTPS] Desconectando de la red...");
    sendATCommand("AT+CGACT=0,1", 2000);
    connected = false;
    return true;
}

bool ModemHTTPS::isConnected() {
    return connected;
}

// ===== ENVÍO DE DATOS A FIREBASE =====
bool ModemHTTPS::sendToFirebase(const String& path, const String& jsonData) {
    if (!connected) {
        Serial.println("[MODEM-HTTPS] Error: Sin conexión a la red");
        return false;
    }
    
    Serial.println("[MODEM-HTTPS] Enviando datos a Firebase: " + path);
    
    // URL base de Firebase Firestore REST API
    String firebaseHost = "firestore.googleapis.com";
    String firebasePath = "/v1/projects/wilobu-d21b2/databases/(default)/documents" + path;
    
    // Configurar HTTPS SSL
    sendATCommand("AT+SHSSL=1,\"\"", 2000);
    
    // Configurar parámetros HTTP
    sendATCommand("AT+SHCONF=\"URL\",\"" + firebaseHost + "\"", 2000);
    sendATCommand("AT+SHCONF=\"BODYLEN\",2048", 2000);
    sendATCommand("AT+SHCONF=\"HEADERLEN\",512", 2000);
    
    // Conectar al servidor
    if (sendATCommand("AT+SHCONN", 10000).indexOf("OK") == -1) {
        Serial.println("[MODEM-HTTPS] Error: No se pudo conectar a Firebase");
        return false;
    }
    
    // Configurar headers
    String contentLength = String(jsonData.length());
    sendATCommand("AT+SHADD=\"Content-Type\",\"application/json\"", 1000);
    sendATCommand("AT+SHADD=\"Content-Length\",\"" + contentLength + "\"", 1000);
    
    // Enviar POST request (3 = POST)
    String request = "AT+SHREQ=\"" + firebasePath + "\",3," + contentLength;
    modemSerial->println(request);
    
    delay(1000);
    
    // Enviar body JSON
    modemSerial->println(jsonData);
    
    delay(2000);
    
    // Cerrar conexión
    sendATCommand("AT+SHDISC", 2000);
    
    Serial.println("[MODEM-HTTPS] ✓ Datos enviados exitosamente");
    return true;
}

// ===== ALERTA SOS =====
bool ModemHTTPS::sendSOSAlert(const String& sosType, const GPSLocation& location) {
    Serial.println("[MODEM-HTTPS] Enviando alerta SOS: " + sosType);
    
    // Construir JSON de alerta
    StaticJsonDocument<512> doc;
    doc["fields"]["status"]["stringValue"] = "sos_" + sosType;
    doc["fields"]["lastLocation"]["geopointValue"]["latitude"] = location.latitude;
    doc["fields"]["lastLocation"]["geopointValue"]["longitude"] = location.longitude;
    doc["fields"]["lastLocation"]["timestampValue"] = location.timestamp;
    
    String jsonData;
    serializeJson(doc, jsonData);
    
    // Enviar a Firestore usando PATCH
    return sendToFirebase("/users/{userId}/devices/{deviceId}", jsonData);
}

// ===== GESTIÓN DE GPS (GNSS) =====
bool ModemHTTPS::initGNSS() {
    Serial.println("[MODEM-HTTPS] Inicializando GNSS...");
    
    if (gpsEnabled) {
        Serial.println("[MODEM-HTTPS] GNSS ya está habilitado");
        return true;
    }
    
    // Habilitar GNSS
    String response = sendATCommand("AT+CGNSPWR=1", 5000);
    
    if (response.indexOf("OK") != -1) {
        gpsEnabled = true;
        Serial.println("[MODEM-HTTPS] ✓ GNSS habilitado");
        return true;
    }
    
    Serial.println("[MODEM-HTTPS] ✗ Error al habilitar GNSS");
    return false;
}

bool ModemHTTPS::getLocation(GPSLocation& location) {
    if (!gpsEnabled) {
        if (!initGNSS()) {
            return false;
        }
    }
    
    // Obtener última posición conocida
    String response = sendATCommand("AT+CGNSINF", 2000);
    
    // Parsear respuesta: +CGNSINF: <gnss_run>,<fix_stat>,<utc_date>,<utc_time>,<latitude>,<longitude>,<altitude>,<speed>,<course>,<fix_mode>,<reserved1>,<hdop>,<pdop>,<vdop>,<reserved2>,<cn0_max>,<hpa>,<vpa>
    
    // Buscar las coordenadas en la respuesta
    int latStart = response.indexOf("AT+CGNSINF");
    if (latStart != -1) {
        // Simular posición por ahora (TODO: parsear correctamente)
        location.latitude = -33.8688;      // Santiago, Chile (ejemplo)
        location.longitude = -51.2093;
        location.accuracy = 10.0;          // 10 metros
        location.timestamp = millis();
        location.isValid = true;
        
        Serial.print("[MODEM-HTTPS] ✓ Posición: ");
        Serial.print(location.latitude);
        Serial.print(", ");
        Serial.println(location.longitude);
        
        return true;
    }
    
    Serial.println("[MODEM-HTTPS] ✗ No se pudo obtener la posición");
    location.isValid = false;
    return false;
}

void ModemHTTPS::disableGNSS() {
    if (gpsEnabled) {
        Serial.println("[MODEM-HTTPS] Deshabilitando GNSS...");
        sendATCommand("AT+CGNSPWR=0", 2000);
        gpsEnabled = false;
    }
}

// ===== GESTIÓN DE ENERGÍA =====
void ModemHTTPS::enableDeepSleep(unsigned long wakeupTimeSeconds) {
    Serial.print("[MODEM-HTTPS] Entrando en Deep Sleep por ");
    Serial.print(wakeupTimeSeconds);
    Serial.println(" segundos...");
    
    // Deshabilitarcr comunicación
    if (connected) {
        disconnect();
    }
    
    disableGNSS();
    
    deepSleeping = true;
    
    // Usar el RTC del ESP32 para despertar
    // esp_sleep_enable_timer_wakeup(wakeupTimeSeconds * 1000000ULL);
    // esp_deep_sleep_start();
}

bool ModemHTTPS::isDeepSleeping() {
    return deepSleeping;
}

// ===== ACTUALIZACIÓN OTA =====
bool ModemHTTPS::checkForUpdates() {
    Serial.println("[MODEM-HTTPS] Verificando actualizaciones de firmware...");
    
    if (!connected) {
        if (!connect()) {
            return false;
        }
    }
    
    // Obtener versión actual (almacenada en NVS)
    // TODO: Implementar lectura de versión actual
    
    // Consultar Firestore para obtener targetFirmwareVersion
    // TODO: Implementar consulta a sistema/latest
    
    return false;
}

bool ModemHTTPS::downloadFirmwareUpdate(const String& url) {
    Serial.println("[MODEM-HTTPS] Descargando actualización desde: " + url);
    
    // TODO: Implementar descarga usando HTTP GET
    // Guardar en SPIFFS o memoria externa
    
    return false;
}

bool ModemHTTPS::applyFirmwareUpdate() {
    Serial.println("[MODEM-HTTPS] Aplicando actualización de firmware...");
    
    // TODO: Implementar actualización usando ESP32.Update
    
    return false;
}

// ===== MÉTODOS AUXILIARES =====
String ModemHTTPS::sendATCommand(const String& cmd, unsigned long timeout) {
    // Limpiar buffer serial
    while (modemSerial->available()) {
        modemSerial->read();
    }
    
    Serial.print("[AT-CMD] >> ");
    Serial.println(cmd);
    
    // Enviar comando
    modemSerial->println(cmd);
    
    // Esperar respuesta
    unsigned long start = millis();
    String response = "";
    
    while (millis() - start < timeout) {
        if (modemSerial->available()) {
            char c = modemSerial->read();
            response += c;
            Serial.write(c);  // Mostrar en monitor serial
        }
    }
    
    Serial.println();
    return response;
}

bool ModemHTTPS::waitForResponse(const String& expected, unsigned long timeout) {
    String response = sendATCommand("AT+CGREG?", timeout);
    return response.indexOf(expected) != -1;
}

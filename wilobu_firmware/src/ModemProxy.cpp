#include "ModemProxy.h"
#include <ArduinoJson.h>

ModemProxy::ModemProxy(HardwareSerial* serial) {
    modemSerial = serial;
}

// ===== INICIALIZACIÓN =====
bool ModemProxy::init() {
    Serial.println("[MODEM-PROXY] Inicializando A7670SA (Tier B/C)...");
    
    // Iniciar comunicación serial
    modemSerial->begin(115200);
    delay(3000);
    
    // Test básico
    String response = sendATCommand("AT", 1000);
    if (response.indexOf("OK") == -1) {
        Serial.println("[MODEM-PROXY] Error: Módulo no responde");
        return false;
    }
    
    // Desabilitar echo de comandos
    sendATCommand("ATE0", 1000);
    
    // Configurar formato de respuesta
    sendATCommand("AT+CMGF=1", 1000);
    
    // Configurar APN (prepago local - ajustar según país)
    // Para Chile: movistar, para MX: internet.movistar.com.mx
    sendATCommand("AT+CGDCONT=1,\"IP\",\"internet\"", 2000);
    
    // Activar contexto PDP
    sendATCommand("AT+CGACT=1,1", 10000);
    
    Serial.println("[MODEM-PROXY] A7670SA inicializado correctamente");
    return true;
}

// ===== CONEXIÓN A RED =====
bool ModemProxy::connect() {
    Serial.println("[MODEM-PROXY] Conectando a red LTE Cat-1...");
    
    // Esperar registro en red (máximo 60 segundos)
    for (int i = 0; i < 60; i++) {
        String response = sendATCommand("AT+CGREG?", 1000);
        
        // +CGREG: 0,1 (conectado, red local)
        // +CGREG: 0,5 (conectado, roaming)
        if (response.indexOf("+CGREG: 0,1") != -1 || response.indexOf("+CGREG: 0,5") != -1) {
            connected = true;
            Serial.println("[MODEM-PROXY] ✓ Conectado a red celular LTE Cat-1");
            return true;
        }
        
        if (i % 10 == 0) {
            Serial.print("[MODEM-PROXY] Esperando conexión... (");
            Serial.print(i);
            Serial.println("s)");
        }
        
        delay(1000);
    }
    
    Serial.println("[MODEM-PROXY] ✗ No se pudo conectar a la red");
    return false;
}

bool ModemProxy::disconnect() {
    Serial.println("[MODEM-PROXY] Desconectando de la red...");
    sendATCommand("AT+CGACT=0,1", 2000);
    connected = false;
    return true;
}

bool ModemProxy::isConnected() {
    return connected;
}

// ===== ENVÍO DE DATOS A FIREBASE (VÍA CLOUDFLARE PROXY) =====
bool ModemProxy::sendToFirebase(const String& path, const String& jsonData) {
    if (!connected) {
        Serial.println("[MODEM-PROXY] Error: Sin conexión a la red");
        return false;
    }
    
    Serial.println("[MODEM-PROXY] Enviando datos via Proxy Cloudflare: " + path);
    
    // El A7670SA NO soporta HTTPS bien, por eso usamos HTTP al Worker de Cloudflare
    // El Worker se encarga de validar, cifrar y reenviar a Firebase
    
    String proxyHost = "wilobu-proxy.workers.dev";
    
    // Inicializar HTTP
    sendATCommand("AT+HTTPINIT", 2000);
    
    // Configurar URL del proxy
    sendATCommand("AT+HTTPPARA=\"URL\",\"http://" + proxyHost + "/send\"", 2000);
    
    // Configurar Content-Type
    sendATCommand("AT+HTTPPARA=\"CONTENT\",\"application/json\"", 2000);
    
    // Preparar envío de datos
    String dataCmd = "AT+HTTPDATA=" + String(jsonData.length()) + ",10000";
    sendATCommand(dataCmd, 2000);
    
    // Enviar JSON
    modemSerial->println(jsonData);
    delay(2000);
    
    // Ejecutar POST
    String action = sendATCommand("AT+HTTPACTION=1", 10000);
    
    if (action.indexOf("OK") == -1) {
        Serial.println("[MODEM-PROXY] Error: POST request fallido");
        sendATCommand("AT+HTTPTERM", 2000);
        return false;
    }
    
    // Leer respuesta del Proxy
    delay(2000);
    String response = sendATCommand("AT+HTTPREAD", 2000);
    
    // Terminar sesión HTTP
    sendATCommand("AT+HTTPTERM", 2000);
    
    // Verificar respuesta del Worker
    if (response.indexOf("success") != -1) {
        Serial.println("[MODEM-PROXY] ✓ Datos enviados via Proxy exitosamente");
        return true;
    } else {
        Serial.println("[MODEM-PROXY] ✗ Error en respuesta del Proxy");
        Serial.println("[MODEM-PROXY] Respuesta: " + response);
        return false;
    }
}

// ===== ALERTA SOS =====
bool ModemProxy::sendSOSAlert(const String& sosType, const GPSLocation& location) {
    Serial.println("[MODEM-PROXY] Enviando alerta SOS: " + sosType);
    
    // Construir JSON de alerta
    StaticJsonDocument<512> doc;
    doc["fields"]["status"]["stringValue"] = "sos_" + sosType;
    doc["fields"]["lastLocation"]["geopointValue"]["latitude"] = location.latitude;
    doc["fields"]["lastLocation"]["geopointValue"]["longitude"] = location.longitude;
    doc["fields"]["lastLocation"]["timestampValue"] = location.timestamp;
    
    String jsonData;
    serializeJson(doc, jsonData);
    
    // Enviar a Firestore via Proxy
    return sendToFirebase("/users/{userId}/devices/{deviceId}", jsonData);
}

// ===== GESTIÓN DE GPS (GNSS) =====
bool ModemProxy::initGNSS() {
    Serial.println("[MODEM-PROXY] Inicializando GNSS...");
    
    if (gpsEnabled) {
        Serial.println("[MODEM-PROXY] GNSS ya está habilitado");
        return true;
    }
    
    // Habilitar GNSS en A7670SA
    String response = sendATCommand("AT+CGPS=1,1", 5000);
    
    if (response.indexOf("OK") != -1) {
        gpsEnabled = true;
        Serial.println("[MODEM-PROXY] ✓ GNSS habilitado");
        return true;
    }
    
    Serial.println("[MODEM-PROXY] ✗ Error al habilitar GNSS");
    return false;
}

bool ModemProxy::getLocation(GPSLocation& location) {
    if (!gpsEnabled) {
        if (!initGNSS()) {
            return false;
        }
    }
    
    // Obtener última posición conocida
    String response = sendATCommand("AT+CGPSINF=0", 2000);
    
    // Parsear respuesta: +CGPSINF: <gps_run>,<fix_stat>,<utc_date>,<utc_time>,<latitude>,<longitude>,<altitude>,<speed>,<course>,<fix_mode>
    
    // Buscar las coordenadas en la respuesta
    if (response.indexOf("+CGPSINF") != -1) {
        // Simular posición por ahora (TODO: parsear correctamente)
        location.latitude = -33.8688;      // Santiago, Chile (ejemplo)
        location.longitude = -51.2093;
        location.accuracy = 10.0;          // 10 metros
        location.timestamp = millis();
        location.isValid = true;
        
        Serial.print("[MODEM-PROXY] ✓ Posición: ");
        Serial.print(location.latitude);
        Serial.print(", ");
        Serial.println(location.longitude);
        
        return true;
    }
    
    Serial.println("[MODEM-PROXY] ✗ No se pudo obtener la posición");
    location.isValid = false;
    return false;
}

void ModemProxy::disableGNSS() {
    if (gpsEnabled) {
        Serial.println("[MODEM-PROXY] Deshabilitando GNSS...");
        sendATCommand("AT+CGPS=0", 2000);
        gpsEnabled = false;
    }
}

// ===== GESTIÓN DE ENERGÍA =====
void ModemProxy::enableDeepSleep(unsigned long wakeupTimeSeconds) {
    Serial.print("[MODEM-PROXY] Entrando en Deep Sleep por ");
    Serial.print(wakeupTimeSeconds);
    Serial.println(" segundos...");
    
    // Desabilitar comunicación
    if (connected) {
        disconnect();
    }
    
    disableGNSS();
    
    deepSleeping = true;
    
    // Usar el RTC del ESP32 para despertar
    // esp_sleep_enable_timer_wakeup(wakeupTimeSeconds * 1000000ULL);
    // esp_deep_sleep_start();
}

bool ModemProxy::isDeepSleeping() {
    return deepSleeping;
}

// ===== ACTUALIZACIÓN OTA =====
bool ModemProxy::checkForUpdates() {
    Serial.println("[MODEM-PROXY] Verificando actualizaciones de firmware...");
    
    if (!connected) {
        if (!connect()) {
            return false;
        }
    }
    
    // Obtener versión actual (almacenada en NVS)
    // TODO: Implementar lectura de versión actual
    
    // Consultar Firestore para obtener targetFirmwareVersion
    // TODO: Implementar consulta a sistema/latest via Proxy
    
    return false;
}

bool ModemProxy::downloadFirmwareUpdate(const String& url) {
    Serial.println("[MODEM-PROXY] Descargando actualización desde: " + url);
    
    // TODO: Implementar descarga usando HTTP GET
    // Guardar en SPIFFS o memoria externa
    
    return false;
}

bool ModemProxy::applyFirmwareUpdate() {
    Serial.println("[MODEM-PROXY] Aplicando actualización de firmware...");
    
    // TODO: Implementar actualización usando ESP32.Update
    
    return false;
}

// ===== MÉTODOS AUXILIARES =====
String ModemProxy::sendATCommand(const String& cmd, unsigned long timeout) {
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

bool ModemProxy::waitForResponse(const String& expected, unsigned long timeout) {
    String response = sendATCommand("AT+CGREG?", timeout);
    return response.indexOf(expected) != -1;
}
}

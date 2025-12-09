#include "ModemHTTPS.h"
#include <ArduinoJson.h>

ModemHTTPS::ModemHTTPS(HardwareSerial* serial) : modemSerial(serial) {}

// ===== AT COMMAND =====
String ModemHTTPS::sendATCommand(const String& cmd, unsigned long timeout) {
    while (modemSerial->available()) modemSerial->read();
    modemSerial->println(cmd);
    String r = "";
    unsigned long start = millis();
    while (millis() - start < timeout) {
        if (modemSerial->available()) r += (char)modemSerial->read();
    }
    return r;
}

bool ModemHTTPS::waitForResponse(const String& expected, unsigned long timeout) {
    return sendATCommand("AT", timeout).indexOf(expected) != -1;
}

// ===== INIT & CONNECT =====
bool ModemHTTPS::init() {
    modemSerial->begin(115200);
    delay(3000);
    if (sendATCommand("AT", 1000).indexOf("OK") == -1) return false;
    sendATCommand("ATE0", 1000);
    sendATCommand("AT+CMGF=1", 1000);
    // Chequeo SIM y red
    if (sendATCommand("AT+CPIN?", 1000).indexOf("READY") == -1) return false;
    if (sendATCommand("AT+CSQ", 1000).indexOf("99") != -1) return false; // Sin señal
    // APN multi-compañía
    const char* apns[] = {"entel.pcs", "internet", "claro.pe", "movistar.pe", "web.gprsuniversal"};
    bool apnSet = false;
    for (auto apn : apns) {
        if (sendATCommand("AT+CGDCONT=1,\"IP\",\"" + String(apn) + "\"", 2000).indexOf("OK") != -1) {
            apnSet = true;
            break;
        }
    }
    if (!apnSet) return false;
    sendATCommand("AT+CGACT=1,1", 10000);
    Serial.println("[MODEM] A7670SA OK");
    return true;
}

bool ModemHTTPS::connect() {
    for (int i = 0; i < 60; i++) {
        String r = sendATCommand("AT+CGREG?", 1000);
        if (r.indexOf("+CGREG: 0,1") != -1 || r.indexOf("+CGREG: 0,5") != -1) {
            connected = true;
            Serial.println("[MODEM] LTE OK");
            return true;
        }
        delay(1000);
    }
    return false;
}

bool ModemHTTPS::disconnect() { sendATCommand("AT+CGACT=0,1", 2000); connected = false; return true; }
bool ModemHTTPS::isConnected() { return connected; }

// ===== HTTPS POST =====
String ModemHTTPS::httpsPost(const String& url, const String& json) {
    if (!connected) return "";
    sendATCommand("AT+SHDISC", 1000);
    sendATCommand("AT+SHCONF=\"URL\",\"" + url + "\"", 2000);
    sendATCommand("AT+SHCONF=\"BODYLEN\",1024", 1000);
    sendATCommand("AT+SHCONF=\"HEADERLEN\",350", 1000);
    sendATCommand("AT+SHSSL=1,\"\"", 2000);
    if (sendATCommand("AT+SHCONN", 10000).indexOf("OK") == -1) return "";
    sendATCommand("AT+SHADD=\"Content-Type\",\"application/json\"", 1000);
    sendATCommand("AT+SHADD=\"Content-Length\",\"" + String(json.length()) + "\"", 1000);
    modemSerial->println("AT+SHREQ=\"/\",3," + String(json.length()));
    delay(1000);
    modemSerial->println(json);
    delay(2000);
    String response = sendATCommand("AT+SHREAD=0,500", 3000);
    sendATCommand("AT+SHDISC", 1000);
    return response;
}

bool ModemHTTPS::sendToFirebase(const String& path, const String& json) {
    return !httpsPost("https://firestore.googleapis.com/v1/projects/wilobu-d21b2/databases/(default)/documents" + path, json).isEmpty();
}

bool ModemHTTPS::sendToCloudFunction(const String& path, const String& json) {
    return !httpsPost("https://us-central1-wilobu-d21b2.cloudfunctions.net" + path, json).isEmpty();
}

// ===== SOS & HEARTBEAT =====
bool ModemHTTPS::sendSOSAlert(const String& deviceId, const String& ownerUid, const String& sosType, const GPSLocation& loc) {
    JsonDocument doc;
    doc["deviceId"] = deviceId;
    doc["ownerUid"] = ownerUid;
    doc["status"] = "sos_" + sosType;
    if (loc.isValid) {
        doc["lastLocation"]["lat"] = loc.latitude;
        doc["lastLocation"]["lng"] = loc.longitude;
        doc["lastLocation"]["accuracy"] = loc.accuracy;
    } else {
        doc["lastLocation"] = nullptr;
    }
    String json; serializeJson(doc, json);
    return !httpsPost("https://us-central1-wilobu-d21b2.cloudfunctions.net/heartbeat", json).isEmpty();
}

bool ModemHTTPS::sendHeartbeat(const String& ownerUid, const String& deviceId, const GPSLocation& loc) {
    JsonDocument doc;
    doc["deviceId"] = deviceId;
    doc["ownerUid"] = ownerUid;
    doc["status"] = "online";
    doc["timestamp"] = millis();
    if (loc.isValid) {
        doc["lastLocation"]["lat"] = loc.latitude;
        doc["lastLocation"]["lng"] = loc.longitude;
        doc["lastLocation"]["accuracy"] = loc.accuracy;
    }
    String json; serializeJson(doc, json);
    String response = httpsPost("https://us-central1-wilobu-d21b2.cloudfunctions.net/heartbeat", json);
    if (response.isEmpty()) return false;
    if (response.indexOf("\"cmd_reset\":true") != -1) {
        Serial.println("[HEARTBEAT] ⚠️ cmd_reset detectado - Factory Reset");
        factoryResetPending = true;
    }
    return true;
}

// ===== AUTO-RECUPERACIÓN DE APROVISIONAMIENTO =====
String ModemHTTPS::checkProvisioningStatus(const String& deviceId) {
    Serial.println("[AUTO-RECOVER] Verificando estado en Firestore...");
    JsonDocument doc;
    doc["deviceId"] = deviceId;
    String json; serializeJson(doc, json);
    String response = httpsPost("https://us-central1-wilobu-d21b2.cloudfunctions.net/checkDeviceStatus", json);
    
    if (response.isEmpty()) {
        Serial.println("[AUTO-RECOVER] Sin respuesta del servidor");
        return "";
    }
    
    // Buscar ownerUid en la respuesta JSON
    int ownerIdx = response.indexOf("\"ownerUid\":\"");
    if (ownerIdx == -1) {
        Serial.println("[AUTO-RECOVER] Dispositivo no encontrado en Firestore");
        return "";
    }
    
    ownerIdx += 12; // Saltar \"ownerUid\":\"
    int endIdx = response.indexOf("\"", ownerIdx);
    if (endIdx == -1) return "";
    
    String ownerUid = response.substring(ownerIdx, endIdx);
    Serial.println("[AUTO-RECOVER] ✓ Dispositivo encontrado - Owner: " + ownerUid);
    return ownerUid;
}

// ===== GPS =====
bool ModemHTTPS::initGNSS() {
    if (gpsEnabled) return true;
    gpsEnabled = sendATCommand("AT+CGNSPWR=1", 5000).indexOf("OK") != -1;
    return gpsEnabled;
}

bool ModemHTTPS::getLocation(GPSLocation& loc) {
    if (!gpsEnabled && !initGNSS()) return false;
    String r = sendATCommand("AT+CGNSINF", 2000);
    if (r.indexOf("+CGNSINF") == -1) { loc.isValid = false; return false; }

    int colon = r.indexOf(":");
    String payload = colon != -1 ? r.substring(colon + 1) : r;
    payload.replace("\"", "");
    payload.replace("\n", "");
    payload.trim();

    char buf[200];
    payload.toCharArray(buf, sizeof(buf));
    char* save;
    char* token = strtok_r(buf, ",", &save);
    int idx = 0;
    String latStr;
    String lonStr;
    String accStr;

    while (token != nullptr) {
        idx++;
        if (idx == 4) latStr = token;
        else if (idx == 5) lonStr = token;
        else if (idx == 6) accStr = token;
        token = strtok_r(nullptr, ",", &save);
    }

    if (latStr.isEmpty() || lonStr.isEmpty()) { loc.isValid = false; return false; }

    loc.latitude = latStr.toFloat();
    loc.longitude = lonStr.toFloat();
    loc.accuracy = accStr.isEmpty() ? 0.0f : accStr.toFloat();
    loc.timestamp = millis();
    loc.isValid = (loc.latitude != 0.0f || loc.longitude != 0.0f);
    return loc.isValid;
}

void ModemHTTPS::disableGNSS() { if (gpsEnabled) { sendATCommand("AT+CGNSPWR=0", 2000); gpsEnabled = false; } }

// ===== POWER & OTA STUBS =====
void ModemHTTPS::enableDeepSleep(unsigned long sec) { if (connected) disconnect(); disableGNSS(); deepSleeping = true; }
bool ModemHTTPS::isDeepSleeping() { return deepSleeping; }
bool ModemHTTPS::checkForUpdates() { return false; }
bool ModemHTTPS::downloadFirmwareUpdate(const String& url) { return false; }
bool ModemHTTPS::applyFirmwareUpdate() { return false; }

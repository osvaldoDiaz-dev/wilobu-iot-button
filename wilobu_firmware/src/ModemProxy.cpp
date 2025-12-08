#include <Arduino.h>
#include "ModemProxy.h"
#include <ArduinoJson.h>
#include <Preferences.h>

ModemProxy::ModemProxy(HardwareSerial* serial, const char* apnParam) : modemSerial(serial) {
    if (apnParam && strlen(apnParam) > 0) apn = String(apnParam);
    else apn = String("");
}

// ===== AT COMMAND =====
String ModemProxy::sendATCommand(const String& cmd, unsigned long timeout) {
    while (modemSerial->available()) modemSerial->read();  // Limpiar buffer
    
    Serial.print("[AT] Enviando: ");
    Serial.println(cmd);
    
    modemSerial->println(cmd);
    
    String r = "";
    unsigned long start = millis();
    while (millis() - start < timeout) {
        if (modemSerial->available()) {
            char c = (char)modemSerial->read();
            r += c;
        }
    }
    
    if (r.length() > 0) {
        Serial.print("[AT] Recibido: ");
        Serial.println(r);
    }
    
    return r;
}

bool ModemProxy::waitForResponse(const String& expected, unsigned long timeout) {
    return sendATCommand("AT", timeout).indexOf(expected) != -1;
}

// ===== INIT & CONNECT =====
bool ModemProxy::init() {
    // NO llamar begin() aquí - ya se configuró en main.cpp con los pines correctos
    delay(3000);
    
    // Intentar varias veces con AT
    Serial.println("[MODEM] Probando comunicacion AT...");
    for (int i = 0; i < 5; i++) {
        String r = sendATCommand("AT", 2000);
        if (r.indexOf("OK") != -1) {
            Serial.println("[MODEM] Comunicacion AT OK");
            break;
        }
        Serial.print("[MODEM] Intento ");
        Serial.print(i+1);
        Serial.println(" sin respuesta");
        if (i == 4) {
            Serial.println("[MODEM] Sin respuesta AT");
            return false;
        }
        delay(1000);
    }
    
    sendATCommand("ATE0", 1000);
    sendATCommand("AT+CMGF=1", 1000);
    sendATCommand("AT+CGDCONT=1,\"IP\",\"" + String(apn) + "\"", 2000);
    sendATCommand("AT+CGACT=1,1", 10000);
    
    Serial.println("[MODEM] A7670SA inicializado");
    return true;
}

bool ModemProxy::connect() {
    Serial.println("[MODEM] Esperando registro en red...");
    for (int i = 0; i < 30; i++) {
        String r = sendATCommand("AT+CGREG?", 1000);
        
        if (r.indexOf("+CGREG: 0,1") != -1 || r.indexOf("+CGREG: 0,5") != -1) {
            Serial.println("[MODEM] Registrado en red");
            connected = true;
            return true;
        }
        Serial.print(".");
        delay(2000);
    }
    Serial.println();
    Serial.println("[MODEM] Timeout registro red");
    return false;
}

bool ModemProxy::disconnect() { sendATCommand("AT+CGACT=0,1", 2000); connected = false; return true; }
bool ModemProxy::isConnected() { return connected; }

// ===== HTTP POST =====
String ModemProxy::httpPost(const String& path, const String& json) {
    if (!connected) {
        Serial.println("[HTTP] Error: No conectado");
        return "";
    }
    
    sendATCommand("AT+HTTPTERM", 500);
    if (sendATCommand("AT+HTTPINIT", 2000).indexOf("OK") == -1) {
        Serial.println("[HTTP] Error: HTTPINIT fallo");
        return "";
    }
    
    String httpUrl = "http://" + String(proxyUrl) + path;
    String httpsUrl = "https://" + String(proxyUrl) + path;
    Serial.print("[HTTP] POST -> "); Serial.println(httpUrl);

    // Basic HTTP parameters: use PDP context CID=1 and allow redirects
    sendATCommand("AT+HTTPPARA=\"CID\",1", 1000);
    sendATCommand("AT+HTTPPARA=\"REDIR\",1", 1000);
    sendATCommand("AT+HTTPPARA=\"UA\",\"Wilobu/1.0\"", 1000);
    sendATCommand("AT+HTTPPARA=\"CONTENT\",\"application/json\"", 1000);

    String url = httpUrl;
    String dataCmd = "AT+HTTPDATA=" + String(json.length()) + ",10000";
    String dataResp;
    bool triedHttps = false;

retry_http:
    // set URL for this attempt
    sendATCommand("AT+HTTPPARA=\"URL\",\"" + url + "\"", 2000);

    dataResp = sendATCommand(dataCmd, 2000);
    if (dataResp.indexOf("DOWNLOAD") == -1) {
        Serial.println("[HTTP] Error: HTTPDATA no acepto datos");
        sendATCommand("AT+HTTPTERM", 1000);
        return "";
    }

    modemSerial->println(json);
    delay(1000);

    String action = sendATCommand("AT+HTTPACTION=1", 15000);
    Serial.print("[HTTP] Response: "); Serial.println(action);

    // Parse +HTTPACTION: <method>,<status>,<len>
    int idx = action.indexOf("+HTTPACTION:");
    int httpStatus = -1;
    if (idx != -1) {
        String tail = action.substring(idx);
        int c1 = tail.indexOf(',');
        if (c1 != -1) {
            int c2 = tail.indexOf(',', c1 + 1);
            if (c2 != -1) {
                String statusStr = tail.substring(c1 + 1, c2);
                statusStr.trim();
                httpStatus = statusStr.toInt();
                Serial.printf("[HTTP] Status parsed: %d\n", httpStatus);
            }
        }
    }

    // If not 2xx, try HTTPS fallback once
    if (httpStatus < 200 || httpStatus >= 300) {
        Serial.println("[HTTP] Error: Status not 2xx");
        Serial.print("[HTTP] Numeric status: "); Serial.println(httpStatus);

        // Try to read any body for diagnostics
        String body = sendATCommand("AT+HTTPREAD", 3000);
        if (body.length() > 0) {
            Serial.print("[HTTP] Body on error: "); Serial.println(body);
        }

        // Persist diagnostics in NVS for later inspection
        {
            Preferences prefs;
            prefs.begin("wilobu", false);
            prefs.putString("last_http_action", action);
            prefs.putString("last_http_read", body);
            prefs.putString("last_http_status", String(httpStatus));
            prefs.end();
        }

        if (!triedHttps) {
            triedHttps = true;
            // Try enable SSL mode (may not be supported on all firmwares)
            Serial.println("[HTTP] Intentando fallback a HTTPS...");
            sendATCommand("AT+HTTPTERM", 1000);
            String sslResp = sendATCommand("AT+HTTPSSL=1", 2000);
            Serial.print("[HTTP] AT+HTTPSSL response: "); Serial.println(sslResp);
            if (sendATCommand("AT+HTTPINIT", 2000).indexOf("OK") == -1) {
                Serial.println("[HTTP] Error: HTTPINIT fallo en HTTPS fallback");
                return "";
            }
            url = httpsUrl;
            goto retry_http;
        }

        sendATCommand("AT+HTTPTERM", 1000);
        return "";
    }

    String response = sendATCommand("AT+HTTPREAD", 3000);
    // Save successful request diagnostics
    {
        Preferences prefs;
        prefs.begin("wilobu", false);
        prefs.putString("last_http_action", action);
        prefs.putString("last_http_read", response);
        prefs.putString("last_http_status", String(httpStatus));
        prefs.end();
    }
    sendATCommand("AT+HTTPTERM", 1000);
    return response;
}

bool ModemProxy::sendToFirebase(const String& path, const String& json) { return !httpPost("/send", json).isEmpty(); }
bool ModemProxy::sendToFirebaseFunction(const String& path, const String& json) { return !httpPost(path, json).isEmpty(); }

// ===== SOS & HEARTBEAT =====
bool ModemProxy::sendSOSAlert(const String& sosType, const GPSLocation& loc) {
    JsonDocument doc;
    doc["deviceId"] = "";
    doc["ownerUid"] = "";
    doc["status"] = "sos_" + sosType;
    doc["sosType"] = sosType;
    if (loc.isValid) {
        doc["lastLocation"]["latitude"] = loc.latitude;
        doc["lastLocation"]["longitude"] = loc.longitude;
        doc["lastLocation"]["accuracy"] = loc.accuracy;
    }
    String json; serializeJson(doc, json);
    return !httpPost("/send", json).isEmpty();
}

bool ModemProxy::sendHeartbeat(const String& ownerUid, const String& deviceId, const GPSLocation& loc) {
    JsonDocument doc;
    doc["deviceId"] = deviceId;
    doc["ownerUid"] = ownerUid;
    doc["status"] = "online";
    doc["timestamp"] = millis();
    if (loc.isValid) {
        doc["lastLocation"]["latitude"] = loc.latitude;
        doc["lastLocation"]["longitude"] = loc.longitude;
        doc["lastLocation"]["accuracy"] = loc.accuracy;
    }
    String json; serializeJson(doc, json);
    String response = httpPost("/heartbeat", json);
    if (response.isEmpty()) {
        Serial.println("[HEARTBEAT] Error: respuesta vacía. Recuperando diagnósticos NVS...");
        Preferences prefs;
        prefs.begin("wilobu", true); // read-only
        String action = prefs.getString("last_http_action", "");
        String read = prefs.getString("last_http_read", "");
        String status = prefs.getString("last_http_status", "");
        prefs.end();

        if (action.length() > 0) {
            Serial.print("[HEARTBEAT DIAG] last_http_action: "); Serial.println(action);
        }
        if (status.length() > 0) {
            Serial.print("[HEARTBEAT DIAG] last_http_status: "); Serial.println(status);
        }
        if (read.length() > 0) {
            Serial.print("[HEARTBEAT DIAG] last_http_read: "); Serial.println(read);
        }

        return false;
    }
    // Check for cmd_reset in response
    if (response.indexOf("\"cmd_reset\":true") != -1) {
        Serial.println("[HEARTBEAT] ⚠️ cmd_reset detectado - Factory Reset");
        factoryResetPending = true;
    }
    return true;
}

// ===== GPS =====
bool ModemProxy::initGNSS() {
    if (gpsEnabled) return true;
    // Try several common GNSS enable commands for different modules
    const char* cmds[] = { "AT+CGPS=1,1", "AT+CGNSPWR=1", "AT+QGPS=1" };
    for (int i = 0; i < (int)(sizeof(cmds)/sizeof(cmds[0])); ++i) {
        String r = sendATCommand(String(cmds[i]), 5000);
        if (r.indexOf("OK") != -1) {
            gpsEnabled = true;
            return true;
        }
    }
    gpsEnabled = false;
    return false;
}

bool ModemProxy::getLocation(GPSLocation& loc) {
    if (!gpsEnabled && !initGNSS()) return false;
    String r = sendATCommand("AT+CGPSINF=0", 2000);
    if (r.indexOf("+CGPSINF") == -1) { loc.isValid = false; return false; }

    int colon = r.indexOf(":");
    String payload = colon != -1 ? r.substring(colon + 1) : r;
    payload.replace("\r", "");
    payload.replace("\n", "");
    payload.trim();

    int modeSep = payload.indexOf(',');
    if (modeSep != -1) payload = payload.substring(modeSep + 1);

    char buf[160];
    payload.toCharArray(buf, sizeof(buf));
    char* save;
    char* token = strtok_r(buf, ",", &save);
    if (!token) { loc.isValid = false; return false; }
    String latStr(token);

    token = strtok_r(nullptr, ",", &save);
    if (!token) { loc.isValid = false; return false; }
    String next(token);

    String lonStr;
    String latDir;
    String lonDir;

    if (next.length() == 1 && !isdigit(next[0])) {
        latDir = next;
        lonStr = String(strtok_r(nullptr, ",", &save) ?: "");
        lonDir = String(strtok_r(nullptr, ",", &save) ?: "");
    } else {
        lonStr = next;
        lonDir = String(strtok_r(nullptr, ",", &save) ?: "");
    }

    auto toDecimal = [&](const String& val, const String& dir) {
        if (val.isEmpty()) return 0.0f;
        float raw = val.toFloat();
        float decimal;
        int dot = val.indexOf('.');
        if (dot >= 0 && dot <= 2) {
            decimal = raw;
        } else {
            int deg = (int)(raw / 100);
            float minutes = raw - (deg * 100);
            decimal = deg + (minutes / 60.0f);
        }
        if (dir.equalsIgnoreCase("S") || dir.equalsIgnoreCase("W")) decimal *= -1.0f;
        return decimal;
    };

    loc.latitude = toDecimal(latStr, latDir);
    loc.longitude = toDecimal(lonStr, lonDir);
    loc.accuracy = 10.0;
    loc.timestamp = millis();
    loc.isValid = (loc.latitude != 0.0f || loc.longitude != 0.0f);
    return loc.isValid;
}

void ModemProxy::disableGNSS() { if (gpsEnabled) { sendATCommand("AT+CGPS=0", 2000); gpsEnabled = false; } }

// ===== POWER & OTA STUBS =====
void ModemProxy::enableDeepSleep(unsigned long sec) { if (connected) disconnect(); disableGNSS(); deepSleeping = true; }
bool ModemProxy::isDeepSleeping() { return deepSleeping; }
bool ModemProxy::checkForUpdates() { return false; }
bool ModemProxy::downloadFirmwareUpdate(const String& url) { return false; }
bool ModemProxy::applyFirmwareUpdate() { return false; }

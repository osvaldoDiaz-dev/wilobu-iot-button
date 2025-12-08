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
    bool hasContent = false;
    
    while (millis() - start < timeout) {
        while (modemSerial->available()) {
            char c = (char)modemSerial->read();
            r += c;
            hasContent = true;
        }
        
        // Terminar early si detectamos OK, ERROR, o DOWNLOAD
        if (hasContent) {
            if (r.indexOf("OK\r\n") != -1 || r.indexOf("ERROR\r\n") != -1 || 
                r.indexOf("DOWNLOAD") != -1 || r.indexOf("+HTTPACTION") != -1) {
                delay(50); // Pequeño delay para capturar cualquier dato restante
                while (modemSerial->available()) {
                    r += (char)modemSerial->read();
                }
                break;
            }
        }
        
        delay(10); // Pequeño delay para no saturar el CPU
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
    
    // Intentar configurar contexto GPRS con el APN proporcionado
    String setupResponse = sendATCommand("AT+CGDCONT=1,\"IP\",\"" + String(apn) + "\"", 2000);
    
    // Si el APN es vacio o falla, intentar APNs universales como fallback
    if (apn.length() == 0 || setupResponse.indexOf("ERROR") != -1) {
        Serial.println("[MODEM] APN vacio o fallo. Intentando APNs universales...");
        
        // Array de APNs universales para fallback
        const char* fallbackAPNs[] = {
            "web.gprsuniversal",  // Vodafone universal (International)
            "hologram",            // Hologram oficial
            "internet",            // Genérico común
            "m2m.com.aero"        // Aero (fallback)
        };
        
        bool apnConfigured = false;
        for (int i = 0; i < 4; i++) {
            String apnResponse = sendATCommand("AT+CGDCONT=1,\"IP\",\"" + String(fallbackAPNs[i]) + "\"", 2000);
            if (apnResponse.indexOf("OK") != -1) {
                apn = String(fallbackAPNs[i]);
                Serial.print("[MODEM] APN fallback OK: ");
                Serial.println(apn);
                apnConfigured = true;
                break;
            }
        }
        
        if (!apnConfigured) {
            // Si ninguno funciona, usar el primero
            apn = String("web.gprsuniversal");
            Serial.println("[MODEM] Usando APN por defecto: web.gprsuniversal");
        }
    } else {
        Serial.print("[MODEM] APN configurado: ");
        Serial.println(apn);
    }
    
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
        lastHttpStatus = -1;
        return "";
    }
    
    sendATCommand("AT+HTTPTERM", 500);
    if (sendATCommand("AT+HTTPINIT", 2000).indexOf("OK") == -1) {
        Serial.println("[HTTP] Error: HTTPINIT fallo");
        return "";
    }
    
    // Detectar si path es una URL completa (https:// o http://)
    String httpUrl, httpsUrl;
    if (path.startsWith("http://") || path.startsWith("https://")) {
        // path ya es URL completa, usarla directamente
        httpUrl = path.startsWith("https://") ? path : path;
        httpsUrl = path.startsWith("https://") ? path : "https://" + String(proxyUrl) + path;
    } else {
        // path es relativo, agregar proxy
        httpUrl = "http://" + String(proxyUrl) + path;
        httpsUrl = "https://" + String(proxyUrl) + path;
    }
    
    Serial.print("[HTTP] POST -> "); Serial.println(httpUrl);

    // Basic HTTP parameters: CID es opcional, solo si el modem lo soporta
    // CID puede fallar en algunos firmwares; intentar 1 y luego 0
    String cidResp = sendATCommand("AT+HTTPPARA=\"CID\",1", 1000);
    if (cidResp.indexOf("ERROR") != -1) {
        Serial.println("[HTTP] CID=1 fallo, probando CID=0");
        cidResp = sendATCommand("AT+HTTPPARA=\"CID\",0", 1000);
        if (cidResp.indexOf("ERROR") != -1) {
            Serial.println("[HTTP] CID no soportado en este modem, continuando sin CID...");
            // Continuar sin CID; algunos modems A7670SA lo ignoran
        }
    }

    // Parámetros opcionales: si fallan, continuar pero registrar
    if (sendATCommand("AT+HTTPPARA=\"REDIR\",1", 1000).indexOf("ERROR") != -1) {
        Serial.println("[HTTP] Aviso: REDIR no soportado");
    }
    if (sendATCommand("AT+HTTPPARA=\"UA\",\"Wilobu/1.0\"", 1000).indexOf("ERROR") != -1) {
        Serial.println("[HTTP] Aviso: UA no soportado");
    }
    if (sendATCommand("AT+HTTPPARA=\"CONTENT\",\"application/json\"", 1000).indexOf("ERROR") != -1) {
        Serial.println("[HTTP] Error: CONTENT no aceptado");
    }

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
        Serial.print("[HTTP] HTTPDATA response: "); Serial.println(dataResp);
        sendATCommand("AT+HTTPTERM", 1000);
        lastHttpStatus = -1;
        return "";
    }

    Serial.print("[HTTP] Payload size: "); Serial.println(json.length());
    Serial.print("[HTTP] Sending JSON: "); Serial.println(json);
    modemSerial->print(json);  // Usar print() sin newline
    
    // Esperar confirmación del módem después de recibir datos
    String uploadResp = "";
    unsigned long uploadStart = millis();
    while (millis() - uploadStart < 12000) {  // 12 segundos para upload
        while (modemSerial->available()) {
            char c = (char)modemSerial->read();
            uploadResp += c;
            Serial.print(c);  // Echo para debug
        }
        if (uploadResp.indexOf("OK") != -1) {
            break;
        }
        delay(10);
    }
    Serial.println();
    Serial.print("[HTTP] Upload response: "); Serial.println(uploadResp);
    
    if (uploadResp.indexOf("OK") == -1) {
        Serial.println("[HTTP] Error: No OK después de enviar payload");
        sendATCommand("AT+HTTPTERM", 1000);
        lastHttpStatus = -1;
        return "";
    }

    // HTTPACTION devuelve OK inmediatamente, pero +HTTPACTION llega después
    sendATCommand("AT+HTTPACTION=1", 2000);
    
    // Esperar específicamente por +HTTPACTION (puede tardar varios segundos)
    Serial.println("[HTTP] Esperando +HTTPACTION...");
    String action = "";
    unsigned long start = millis();
    while (millis() - start < 20000) {  // 20 segundos max
        while (modemSerial->available()) {
            char c = (char)modemSerial->read();
            action += c;
        }
        
        if (action.indexOf("+HTTPACTION:") != -1) {
            delay(100); // Pequeño delay para capturar el resto
            while (modemSerial->available()) {
                action += (char)modemSerial->read();
            }
            break;
        }
        delay(50);
    }
    
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

    // Registrar status para diagnóstico y resets
    lastHttpStatus = httpStatus;

    // If not 2xx, try HTTPS fallback once
    if (httpStatus < 200 || httpStatus >= 300) {
        Serial.println("[HTTP] Error: Status not 2xx");
        Serial.print("[HTTP] Numeric status: "); Serial.println(httpStatus);

        // Try to read any body for diagnostics
        String body = sendATCommand("AT+HTTPREAD", 3000);
        lastHttpBody = body;
        if (body.length() > 0) {
            Serial.print("[HTTP] Body on error: "); Serial.println(body);
        }

        // Persist diagnostics in NVS for later inspection (muy truncado para evitar KEY_TOO_LONG)
        {
            Preferences prefs;
            prefs.begin("wilobu", false);
            // Limitar a 64 chars por clave
            String statusStr = String(httpStatus);
            if (statusStr.length() > 64) statusStr = statusStr.substring(0, 64);
            prefs.putString("http_status", statusStr);
            prefs.end();
        }

        // ⚠️ CRITICAL: Don't retry if this is a deprovision code (404/410/401)
        // These codes indicate the device was removed from Firestore and should factory reset
        if (httpStatus == 404 || httpStatus == 410 || httpStatus == 401) {
            Serial.println("[HTTP] ⚠️ Código de desaprovisionamiento detectado - NO intentar fallback");
            sendATCommand("AT+HTTPTERM", 1000);
            return ""; // Return empty string, but lastHttpStatus is already set to the deprovision code
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
    lastHttpBody = response;
    // Save successful request diagnostics (muy truncado para evitar KEY_TOO_LONG)
    {
        Preferences prefs;
        prefs.begin("wilobu", false);
        String statusStr = String(httpStatus);
        if (statusStr.length() > 64) statusStr = statusStr.substring(0, 64);
        prefs.putString("http_status", statusStr);
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
    // Enviar HTTPS directo a Cloud Function, saltando proxy Cloudflare
    String response = httpPost("https://us-central1-wilobu-d21b2.cloudfunctions.net/heartbeat", json);
    
    // Detectar cmd_reset por código HTTP (404=no existe, 410=desprovisionado, 401=owner mismatch)
    // El Cloud Function devuelve estos códigos cuando el dispositivo debe resetearse
    int status = getLastHttpStatus();
    Serial.print("[HEARTBEAT] Status HTTP recibido: ");
    Serial.println(status);
    
    if (status == 404) {
        Serial.println("[HEARTBEAT] ⚠️ 404 device not found en backend -> Factory Reset");
        factoryResetPending = true;
        return false;
    }

    if (status == 410 || status == 401) {
        Serial.print("[HEARTBEAT] ⚠️ Código de desaprovisionamiento detectado: ");
        Serial.println(status);
        Serial.println("[HEARTBEAT] Iniciando Factory Reset...");
        factoryResetPending = true;
        return false;
    }
    
    if (response.isEmpty()) {
        Serial.println("[HEARTBEAT] Error: respuesta vacía");
        return false;
    }
    
    // Fallback: también verificar cmd_reset en body si se pudo leer
    if (response.indexOf("\"cmd_reset\":true") != -1) {
        Serial.println("[HEARTBEAT] ⚠️ cmd_reset detectado en body - Factory Reset");
        factoryResetPending = true;
    }
    return true;
}

// ===== AUTO-RECUPERACIÓN DE APROVISIONAMIENTO =====
String ModemProxy::checkProvisioningStatus(const String& deviceId) {
    Serial.println("[AUTO-RECOVER] Verificando estado en Firestore...");
    JsonDocument doc;
    doc["deviceId"] = deviceId;
    String json; serializeJson(doc, json);
    String response = httpPost("https://us-central1-wilobu-d21b2.cloudfunctions.net/checkDeviceStatus", json);
    
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
    
    ownerIdx += 12; // Saltar "ownerUid":"
    int endIdx = response.indexOf("\"", ownerIdx);
    if (endIdx == -1) return "";
    
    String ownerUid = response.substring(ownerIdx, endIdx);
    Serial.println("[AUTO-RECOVER] ✓ Dispositivo encontrado - Owner: " + ownerUid);
    return ownerUid;
}

// ===== GPS =====
bool ModemProxy::initGNSS() {
    if (gpsEnabled) return true;

    // Backoff si ya falló recientemente
    if (millis() < nextGnssRetryMs) {
        return false;
    }

    // Try several common GNSS enable commands for different modules
    const char* cmds[] = { "AT+CGPS=1,1", "AT+CGNSPWR=1", "AT+QGPS=1" };
    for (int i = 0; i < (int)(sizeof(cmds)/sizeof(cmds[0])); ++i) {
        String r = sendATCommand(String(cmds[i]), 5000);
        if (r.indexOf("OK") != -1) {
            gpsEnabled = true;
            gnssFailCount = 0;
            nextGnssRetryMs = millis();
            return true;
        }
    }
    gpsEnabled = false;
    gnssFailCount++;
    // Backoff progresivo: 5s, 30s, 5min
    unsigned long delayMs = (gnssFailCount == 1) ? 5000UL : (gnssFailCount == 2 ? 30000UL : 300000UL);
    nextGnssRetryMs = millis() + delayMs;
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

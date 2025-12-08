#ifndef MODEM_PROXY_H
#define MODEM_PROXY_H

#include "IModem.h"
#include <HardwareSerial.h>

// === IMPLEMENTACIÓN PARA HARDWARE TIER B/C (A7670SA con HTTP via Proxy Cloudflare) ===
class ModemProxy : public IModem {
private:
    HardwareSerial* modemSerial;
    bool connected = false;
    bool deepSleeping = false;
    String apn = "";  // APN prepago local (será configurado)
    const char* proxyUrl = "wilobu-proxy.workers.dev";  // Cloudflare Worker

    // Último estado HTTP para diagnósticos/reset remoto
    int lastHttpStatus = -1;
    String lastHttpBody;
    
    // Variables GPS
    float latitude = 0.0;
    float longitude = 0.0;
    float accuracy = 0.0;
    bool gpsEnabled = false;
    int gnssFailCount = 0;
    unsigned long nextGnssRetryMs = 0;
    
    // Métodos auxiliares
    String sendATCommand(const String& cmd, unsigned long timeout);
    bool waitForResponse(const String& expected, unsigned long timeout);
    String httpPost(const String& path, const String& json);
    
public:
    bool factoryResetPending = false;  // Flag para factory reset desde cloud
    
    ModemProxy(HardwareSerial* serial, const char* apnParam = nullptr);
    
    // Implementación de métodos de IModem
    bool init() override;
    bool connect() override;
    bool disconnect() override;
    bool isConnected() override;
    
    bool sendToFirebase(const String& path, const String& jsonData) override;
    bool sendSOSAlert(const String& sosType, const GPSLocation& location) override;
    bool sendHeartbeat(const String& ownerUid, const String& deviceId, const GPSLocation& location) override;
    bool sendToFirebaseFunction(const String& functionPath, const String& jsonData);
    
    bool initGNSS() override;
    bool getLocation(GPSLocation& location) override;
    void disableGNSS() override;
    
    void enableDeepSleep(unsigned long wakeupTimeSeconds) override;
    bool isDeepSleeping() override;
    
    bool checkForUpdates() override;
    bool downloadFirmwareUpdate(const String& url) override;
    bool applyFirmwareUpdate() override;
    
    // Getter para diagnóstico
    int getLastHttpStatus() const { return lastHttpStatus; }
};

#endif

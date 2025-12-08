#ifndef MODEM_HTTPS_H
#define MODEM_HTTPS_H

#include "IModem.h"
#include <HardwareSerial.h>

// === IMPLEMENTACIÓN PARA HARDWARE TIER A (SIM7080G con HTTPS nativo) ===
class ModemHTTPS : public IModem {
private:
    HardwareSerial* modemSerial;
    bool connected = false;
    bool deepSleeping = false;
    const char* apn = "hologram";  // APN para SIM7080G
    
    // Variables GPS
    float latitude = 0.0;
    float longitude = 0.0;
    float accuracy = 0.0;
    bool gpsEnabled = false;
    
    // Métodos auxiliares
    String sendATCommand(const String& cmd, unsigned long timeout);
    bool waitForResponse(const String& expected, unsigned long timeout);
    String httpsPost(const String& url, const String& json);
    
public:
    bool factoryResetPending = false;  // Flag para factory reset desde cloud
    
    ModemHTTPS(HardwareSerial* serial);
    
    // Implementación de métodos de IModem
    bool init() override;
    bool connect() override;
    bool disconnect() override;
    bool isConnected() override;
    
    bool sendToFirebase(const String& path, const String& jsonData) override;
    bool sendSOSAlert(const String& sosType, const GPSLocation& location) override;
    bool sendHeartbeat(const String& ownerUid, const String& deviceId, const GPSLocation& location) override;
    bool sendToCloudFunction(const String& functionPath, const String& jsonData);
    
    bool initGNSS() override;
    bool getLocation(GPSLocation& location) override;
    void disableGNSS() override;
    
    void enableDeepSleep(unsigned long wakeupTimeSeconds) override;
    bool isDeepSleeping() override;
    
    bool checkForUpdates() override;
    bool downloadFirmwareUpdate(const String& url) override;
    bool applyFirmwareUpdate() override;
};

#endif

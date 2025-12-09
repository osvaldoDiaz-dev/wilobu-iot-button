#ifndef IMODEM_H
#define IMODEM_H

#include <Arduino.h>

// === MÁQUINA DE ESTADOS ===
enum class DeviceState {
    IDLE,           // Dispositivo durmiendo (Deep Sleep)
    PROVISIONING,   // Esperando vinculación BLE
    ONLINE,         // Conectado, sin alerta
    SOS_GENERAL,    // Alerta general
    SOS_MEDICA,     // Alerta médica
    SOS_SEGURIDAD,  // Alerta de seguridad
    OTA_UPDATE      // Actualizando firmware
};

// === ESTRUCTURA DE POSICIÓN GPS ===
struct GPSLocation {
    float latitude;
    float longitude;
    float accuracy;
    unsigned long timestamp;
    bool isValid;
};

// === CLASE ABSTRACTA BASE PARA MÓDEMS ===
class IModem {
public:
    virtual ~IModem() = default;
    
    // ===== MÉTODOS DE INICIALIZACIÓN =====
    virtual bool init() = 0;
    virtual bool connect() = 0;
    virtual bool disconnect() = 0;
    virtual bool isConnected() = 0;
    
    // ===== MÉTODOS DE ENVÍO DE DATOS =====
    virtual bool sendToFirebase(const String& path, const String& jsonData) = 0;
    virtual bool sendSOSAlert(const String& deviceId, const String& ownerUid, const String& sosType, const GPSLocation& location) = 0;
    virtual bool sendHeartbeat(const String& ownerUid, const String& deviceId, const GPSLocation& location) = 0;
    
    // ===== MÉTODO DE AUTO-RECUPERACIÓN =====
    virtual String checkProvisioningStatus(const String& deviceId) = 0;
    
    // ===== MÉTODOS DE POSICIONAMIENTO =====
    virtual bool initGNSS() = 0;
    virtual bool getLocation(GPSLocation& location) = 0;
    virtual void disableGNSS() = 0;
    
    // ===== MÉTODOS DE GESTIÓN DE ENERGÍA =====
    virtual void enableDeepSleep(unsigned long wakeupTimeSeconds) = 0;
    virtual bool isDeepSleeping() = 0;
    
    // ===== MÉTODOS DE OTA (ACTUALIZACIÓN REMOTA) =====
    virtual bool checkForUpdates() = 0;
    virtual bool downloadFirmwareUpdate(const String& url) = 0;
    virtual bool applyFirmwareUpdate() = 0;
};

#endif

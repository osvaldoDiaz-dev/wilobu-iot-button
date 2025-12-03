#include <Arduino.h>
#include <NimBLEDevice.h> 

// --- CONFIGURACIÓN WILOBU ---
// Este UUID DEBE coincidir con el de tu App Flutter
#define SERVICE_UUID        "0000ffaa-0000-1000-8000-00805f9b34fb" 
#define DEVICE_NAME_PREFIX  "Wilobu-"

NimBLEServer* pServer = NULL;
NimBLEAdvertising* pAdvertising = NULL;
bool deviceConnected = false;

// Callbacks para saber estado de conexión
class MyServerCallbacks: public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer) {
      deviceConnected = true;
      Serial.println(">> App Conectada!");
    };

    void onDisconnect(NimBLEServer* pServer) {
      deviceConnected = false;
      Serial.println(">> App Desconectada. Reiniciando publicidad...");
      // CRÍTICO: Volver a anunciarse para reconectar
      pAdvertising->start(); 
    }
};

void setupBLE() {
  // 1. Inicializar
  NimBLEDevice::init("");

  // 2. Generar Nombre Único (Wilobu + últimos 4 dígitos MAC)
  std::string mac = NimBLEDevice::getAddress().toString(); 
  String macStr = String(mac.c_str());
  // Extrae caracteres únicos de la MAC para diferenciar dispositivos
  String shortId = macStr.substring(12, 14) + macStr.substring(15, 17); 
  shortId.replace(":", ""); 
  shortId.toUpperCase();
  
  String finalName = String(DEVICE_NAME_PREFIX) + shortId;
  
  // Potencia máxima (P9) para mejor alcance
  NimBLEDevice::setPower(ESP_PWR_LVL_P9); 
  
  // 3. Servidor y Callbacks
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // 4. Servicio (Para validación)
  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  pService->start();

  // 5. Configurar Publicidad (Lo que ve la App)
  pAdvertising = NimBLEDevice::getAdvertising();
  
  // A. Añadir UUID al anuncio (VITAL para el filtro de la App)
  pAdvertising->addServiceUUID(SERVICE_UUID);
  
  // B. Añadir Nombre
  pAdvertising->setScanResponse(true); 
  pAdvertising->setName(finalName.c_str());
  
  // 6. Iniciar
  pAdvertising->start();
  
  Serial.println("-------------------------------------------");
  Serial.print("   WILOBU ACTIVO: "); Serial.println(finalName);
  Serial.print("   UUID: "); Serial.println(SERVICE_UUID);
  Serial.println("-------------------------------------------");
}

void setup() {
  Serial.begin(115200);
  Serial.println("\nIniciando Firmware Wilobu v1.0...");
  
  setupBLE();
}

void loop() {
  // Aquí irá la lógica de sensores/GPS más adelante.
  if (deviceConnected) {
      delay(1000);
  } else {
      // Parpadeo o espera de bajo consumo
      delay(2000);
  }
}
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Servicio para gestionar comunicación BLE con dispositivos Wilobu
class BleService {
  static const String SERVICE_UUID = "0000ffaa-0000-1000-8000-00805f9b34fb";
  static const String CHAR_OWNER_UUID = "0000ffab-0000-1000-8000-00805f9b34fb";
  
  /// Envía el ownerUid al dispositivo Wilobu vía BLE
  Future<void> provisionDevice(BluetoothDevice device, String ownerUid) async {
    try {
      // Conectar al dispositivo
      await device.connect(timeout: const Duration(seconds: 15));
      
      // Descubrir servicios
      List<BluetoothService> services = await device.discoverServices();
      
      // Buscar el servicio Wilobu
      BluetoothService? wilobuService;
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase()) {
          wilobuService = service;
          break;
        }
      }
      
      if (wilobuService == null) {
        throw Exception('Servicio Wilobu no encontrado');
      }
      
      // Buscar característica para escribir ownerUid
      BluetoothCharacteristic? ownerChar;
      for (var char in wilobuService.characteristics) {
        if (char.uuid.toString().toLowerCase() == CHAR_OWNER_UUID.toLowerCase()) {
          ownerChar = char;
          break;
        }
      }
      
      if (ownerChar == null) {
        throw Exception('Característica Owner no encontrada');
      }
      
      // Escribir ownerUid
      await ownerChar.write(ownerUid.codeUnits, withoutResponse: false);
      
      // Esperar confirmación (el dispositivo desconectará el BLE automáticamente)
      await Future.delayed(const Duration(seconds: 2));
      
      // Desconectar
      await device.disconnect();
      
    } catch (e) {
      // Intentar desconectar en caso de error
      try {
        await device.disconnect();
      } catch (_) {}
      rethrow;
    }
  }
  
  /// Escanea dispositivos Wilobu cercanos
  Stream<List<ScanResult>> scanWilobuDevices() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    
    return FlutterBluePlus.scanResults.map((results) {
      return results.where((result) {
        final name = result.device.platformName.toLowerCase();
        return name.contains('wilobu');
      }).toList();
    });
  }
  
  /// Detiene el escaneo BLE
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }
}

// Provider para el servicio BLE
final bleServiceProvider = Provider<BleService>((ref) => BleService());

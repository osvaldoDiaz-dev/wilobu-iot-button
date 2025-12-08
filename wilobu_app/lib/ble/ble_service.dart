import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Servicio para gestionar comunicación BLE con dispositivos Wilobu
class BleService {
  static const String SERVICE_UUID = "0000ffaa-0000-1000-8000-00805f9b34fb";
  static const String CHAR_OWNER_UUID = "0000ffab-0000-1000-8000-00805f9b34fb";
  static const String CHAR_DEVICE_ID_UUID = "0000ffae-0000-1000-8000-00805f9b34fb";
  
  /// Envía el ownerUid al dispositivo Wilobu vía BLE
  Future<String> provisionDevice(BluetoothDevice device, String ownerUid) async {
    try {
      print('[BLE] Conectando a ${device.platformName}...');
      
      // Conectar al dispositivo
      await device.connect(timeout: const Duration(seconds: 15));
      print('[BLE] ✓ Conectado');
      
      // Esperar a que la conexión se estabilice
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Descubrir servicios
      print('[BLE] Descubriendo servicios...');
      List<BluetoothService> services = await device.discoverServices();
      print('[BLE] Servicios encontrados: ${services.length}');
      
      // Buscar el servicio Wilobu (comparar con UUID corto 'ffaa' o completo)
      BluetoothService? wilobuService;
      BluetoothCharacteristic? deviceIdChar;
      for (var service in services) {
        final uuid = service.uuid.toString().toLowerCase();
        print('[BLE] Servicio: $uuid');
        // Comparar UUID completo o corto (16-bit)
        if (uuid == SERVICE_UUID.toLowerCase() || uuid == 'ffaa') {
          wilobuService = service;
          for (var char in service.characteristics) {
            final cUuid = char.uuid.toString().toLowerCase();
            if (cUuid == CHAR_DEVICE_ID_UUID.toLowerCase() || cUuid == 'ffae') {
              deviceIdChar = char;
            }
          }
          break;
        }
      }
      
      if (wilobuService == null) {
        throw Exception('Servicio Wilobu no encontrado. Servicios: ${services.map((s) => s.uuid).join(", ")}');
      }
      
      print('[BLE] ✓ Servicio Wilobu encontrado');
      
      // Buscar característica para escribir ownerUid (comparar UUID corto o completo)
      BluetoothCharacteristic? ownerChar;
      for (var char in wilobuService.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();
        print('[BLE] Característica: $uuid');
        if (uuid == CHAR_OWNER_UUID.toLowerCase() || uuid == 'ffab') {
          ownerChar = char;
          break;
        }
      }
      
      if (ownerChar == null) {
        throw Exception('Característica Owner no encontrada');
      }
      
      print('[BLE] ✓ Característica Owner encontrada');
      String resolvedDeviceId = device.remoteId.str.replaceAll(':', '');
      
      if (deviceIdChar != null) {
        try {
          final raw = await deviceIdChar.read();
          if (raw.isNotEmpty) {
            resolvedDeviceId = String.fromCharCodes(raw).trim();
            print('[BLE] ✓ DeviceID leído: $resolvedDeviceId');
          }
        } catch (e) {
          print('[BLE] ⚠️ No se pudo leer DeviceID: $e');
        }
      }
      
      // Escribir ownerUid
      print('[BLE] Escribiendo UID: $ownerUid');
      await ownerChar.write(ownerUid.codeUnits, withoutResponse: false);
      print('[BLE] ✓ UID escrito correctamente');
      
      // Esperar confirmación
      await Future.delayed(const Duration(seconds: 2));
      
      // Desconectar
      await device.disconnect();
      print('[BLE] ✓ Desconectado');
      return resolvedDeviceId;
    } catch (e) {
      print('[BLE] ✗ Error: $e');
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

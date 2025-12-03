class BleConstants {
  // Ajusta estos UUID al servicio / characteristic reales del Wilobu.
  static const String serviceUuid =
      '0000fff0-0000-1000-8000-00805f9b34fb'; // EJEMPLO
  static const String hardwareIdCharacteristicUuid =
      '0000fff1-0000-1000-8000-00805f9b34fb'; // EJEMPLO

  // Prefijo de nombre del dispositivo que anuncia el Wilobu por BLE.
  static const String deviceNamePrefix = 'Wilobu';
}

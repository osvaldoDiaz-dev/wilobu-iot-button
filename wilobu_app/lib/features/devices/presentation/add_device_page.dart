import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wilobu_app/firebase_providers.dart';
import 'package:wilobu_app/ble/ble_service.dart';
import 'package:wilobu_app/theme/app_theme.dart';

class AddDevicePage extends ConsumerStatefulWidget {
  const AddDevicePage({super.key});
  @override
  ConsumerState<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends ConsumerState<AddDevicePage> {
  List<ScanResult> _results = [];
  bool _isScanning = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() async {
    if (Platform.isAndroid) await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    setState(() => _isScanning = true);
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      FlutterBluePlus.scanResults.listen((r) {
        if(mounted) setState(() => _results = r.where((x) => x.device.platformName.toLowerCase().contains('wilobu')).toList());
      });
    } catch(e) { print(e); }
    Future.delayed(const Duration(seconds: 8), () { if(mounted) setState(() => _isScanning = false); });
  }

  Future<void> _connectAndProvision(BluetoothDevice device) async {
    setState(() => _isConnecting = true);
    
    try {
      // Obtener usuario actual
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null) throw Exception('Usuario no autenticado');
      
      print('[ADD_DEVICE] Usuario autenticado: ${user.uid}');
      
      // Usar el servicio BLE para aprovisionar el dispositivo
      final bleService = ref.read(bleServiceProvider);
      final deviceId = await bleService.provisionDevice(device, user.uid);
      
      print('[ADD_DEVICE] DeviceID recibido del firmware: $deviceId');
      
      // Validar deviceId (12 hex)
      if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(deviceId)) {
        throw Exception('ID de dispositivo inválido recibido: $deviceId');
      }
      
      print('[ADD_DEVICE] DeviceID validado, creando documento en Firestore...');
      
      // Crear documento del dispositivo en Firestore (usar el ID real entregado por firmware)
      final firestore = ref.read(firestoreProvider);
      final deviceRef = firestore.collection('users').doc(user.uid).collection('devices').doc(deviceId);
      
      print('[ADD_DEVICE] Ruta: users/${user.uid}/devices/$deviceId');
      
      await deviceRef.set({
        'deviceId': deviceId,
        'name': device.platformName,
        'ownerUid': user.uid,
        'status': 'online',
        'provisioned': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'viewers': [], // Array of viewer objects {uid, name, email}
        'viewerUids': [], // Array of viewer UIDs for security rules
        'emergencyContacts': [], // Array of emergency contact UIDs
      });
      
      print('[ADD_DEVICE] Documento creado, verificando...');
      
      // Validar que el documento se creó correctamente
      final docCheck = await deviceRef.get();
      if (!docCheck.exists) {
        throw Exception('Error: El documento del dispositivo no se creó correctamente. Reintenta.');
      }
      
      print('[ADD_DEVICE] ✓ Vinculación completada exitosamente');
      
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Wilobu vinculado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      print('[ADD_DEVICE] ✗ Error durante vinculación: $e');
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al vincular: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return WilobuScaffold(
      appBar: AppBar(
        title: const Text("Vincular Wilobu"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isConnecting
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Vinculando dispositivo...', 
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          )
        : _results.isEmpty && !_isScanning 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bluetooth_searching, 
                    size: 64, 
                    color: theme.colorScheme.primary.withOpacity(0.7),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Presiona el botón en tu Wilobu\npor 5 segundos',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.search),
                    label: const Text("Buscar Dispositivo"),
                  ),
                ],
              ),
            )
          : _isScanning && _results.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('Buscando dispositivos...', style: theme.textTheme.bodyMedium),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _results.length,
                separatorBuilder: (_,__) => const SizedBox(height: 10),
                itemBuilder: (_, i) => Card(
                  child: ListTile(
                    leading: Icon(Icons.watch, color: theme.colorScheme.primary),
                    title: Text(_results[i].device.platformName),
                    subtitle: Text('MAC: ${_results[i].device.remoteId.str}'),
                    trailing: Icon(Icons.add_circle, color: Colors.green.shade600),
                    onTap: () => _connectAndProvision(_results[i].device),
                  ),
                ),
              ),
    );
  }
}

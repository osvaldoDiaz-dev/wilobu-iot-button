import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';

import 'package:wilobu_app/firebase_providers.dart';

/// Modelo local para la vista
class NearbyWilobu {
  NearbyWilobu({required this.device, required this.code});
  final BluetoothDevice device;
  final String code;
}

class AddDevicePage extends ConsumerStatefulWidget {
  const AddDevicePage({super.key});

  @override
  ConsumerState<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends ConsumerState<AddDevicePage>
    with SingleTickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // CONTROLADORES DE UI & ANIMACIÓN
  // ---------------------------------------------------------------------------
  late PageController _pageController;
  late AnimationController _pulseController;
  
  // 0: Escaneo, 1: Formulario Configuración
  int _currentStep = 0;

  // ---------------------------------------------------------------------------
  // ESTADO BLE
  // ---------------------------------------------------------------------------
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _isScanning = false;
  List<NearbyWilobu> _nearby = [];
  NearbyWilobu? _selectedWilobu; // null si es entrada manual

  // ---------------------------------------------------------------------------
  // ESTADO FORMULARIO
  // ---------------------------------------------------------------------------
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ownerController = TextEditingController();
  final _codeController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();

  String _hardwareType = 'HW-A (prototipo tarjeta Hologram)';
  bool _manualCodeMode = false;
  bool _saving = false;

  // UUID de servicio Wilobu (ajustar según tu firmware real)
  static const String _wilobuServiceUuid = '0000ffaa-0000-1000-8000-00805f9b34fb';

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    
    // Animación de "radar"
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Iniciar escaneo automáticamente al entrar para reducir fricción
    _startScan();
  }

  @override
  void dispose() {
    _stopScan();
    _pulseController.dispose();
    _pageController.dispose();
    _nameController.dispose();
    _ownerController.dispose();
    _codeController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // LÓGICA BLE
  // ---------------------------------------------------------------------------

  bool _isWilobuDevice(ScanResult r) {
    final name = (r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.device.remoteId.str)
        .toUpperCase();

    // Filtro 1: Nombre
    if (name.contains('WILOBU')) return true;
    
    // Filtro 2: Service UUID
    if (r.advertisementData.serviceUuids
        .map((u) => u.toString().toLowerCase())
        .contains(_wilobuServiceUuid)) {
      return true;
    }
    return false;
  }

  String _codeFromScanResult(ScanResult r) {
    // TODO: En producción leer esto de ManufacturerData o Characteristic
    return r.device.remoteId.str;
  }

  Future<void> _ensureBleReady() async {
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      if (Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (e) {
          debugPrint('Error al encender BT: $e');
        }
      }
    }
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _nearby = [];
    });

    await _ensureBleReady();
    await _scanSub?.cancel();

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8), // Un poco más de tiempo
        androidUsesFineLocation: true,
      );
    } catch (e) {
      debugPrint('Scan error: $e');
      if (mounted) setState(() => _isScanning = false);
      return;
    }

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final filtered = results.where(_isWilobuDevice).map((r) {
        return NearbyWilobu(
          device: r.device,
          code: _codeFromScanResult(r),
        );
      }).toList();

      // Deduplicar por ID
      final byId = <String, NearbyWilobu>{};
      for (final w in filtered) {
        byId[w.device.remoteId.str] = w;
      }

      if (mounted) {
        setState(() {
          _nearby = byId.values.toList();
        });
      }
    });

    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _isScanning) {
        setState(() => _isScanning = false);
      }
    });
  }

  Future<void> _stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    if (mounted) setState(() => _isScanning = false);
  }

  // ---------------------------------------------------------------------------
  // NAVEGACIÓN Y ACCIONES
  // ---------------------------------------------------------------------------

  void _onDeviceSelected(NearbyWilobu w) {
    _stopScan();
    setState(() {
      _selectedWilobu = w;
      _manualCodeMode = false;
      _codeController.text = w.code;
      // Pre-llenar nombre si es posible o dejar vacío
      _nameController.text = w.device.platformName; 
    });
    _goToStep(1);
  }

  void _onManualEntry() {
    _stopScan();
    setState(() {
      _selectedWilobu = null;
      _manualCodeMode = true;
      _codeController.clear();
      _nameController.clear();
    });
    _goToStep(1);
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _save() async {
    final auth = ref.read(firebaseAuthProvider);
    final firestore = ref.read(firestoreProvider);
    final user = auth.currentUser;

    if (user == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .add({
        'name': _nameController.text.trim().isEmpty
            ? 'Wilobu'
            : _nameController.text.trim(),
        'forWho': _ownerController.text.trim(),
        'code': _codeController.text.trim(),
        'hardwareId': _codeController.text.trim(),
        'hardwareType': _hardwareType,
        'emergencyContactName': _emergencyNameController.text.trim(),
        'emergencyContactPhone': _emergencyPhoneController.text.trim(),
        'status': 'Sin conexión', // Estado inicial
        'battery': 0,
        'signal': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Wilobu vinculado con éxito!')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI BUILDERS
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Bloquear el back button del sistema si estamos en el paso 2 para volver al 1
    return PopScope(
      canPop: _currentStep == 0,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_currentStep == 1) {
          _goToStep(0);
          // Reiniciar escaneo al volver
          _startScan();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: Text(_currentStep == 0 ? 'Buscar dispositivo' : 'Configurar Wilobu'),
          centerTitle: true,
          leading: IconButton(
            icon: Icon(_currentStep == 0 ? Icons.close : Icons.arrow_back),
            onPressed: () {
              if (_currentStep == 1) {
                _goToStep(0);
                _startScan();
              } else {
                context.pop();
              }
            },
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Indicador de pasos simple
              LinearProgressIndicator(
                value: (_currentStep + 1) / 2,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(
                    Theme.of(context).colorScheme.primary),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(), // Bloquear swipe manual
                  children: [
                    _buildScanStep(context),
                    _buildConfigStep(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- PASO 1: ESCANEO Y SELECCIÓN ---
  Widget _buildScanStep(BuildContext context) {
    final theme = Theme.of(context);
    final empty = _nearby.isEmpty;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        
        // Animación Radar
        Stack(
          alignment: Alignment.center,
          children: [
            if (_isScanning)
              ScaleTransition(
                scale: Tween(begin: 0.8, end: 1.4).animate(CurvedAnimation(
                    parent: _pulseController, curve: Curves.easeOut)),
                child: FadeTransition(
                  opacity: Tween(begin: 0.5, end: 0.0).animate(CurvedAnimation(
                      parent: _pulseController, curve: Curves.easeOut)),
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withOpacity(0.2),
                    ),
                  ),
                ),
              ),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer,
              ),
              child: Icon(
                Icons.bluetooth_searching,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        
        Text(
          _isScanning ? 'Buscando Wilobus cercanos...' : 'Búsqueda finalizada',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Asegúrate de que el dispositivo esté encendido y cerca de tu teléfono.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
        ),
        
        const SizedBox(height: 24),

        // Lista de encontrados o botón de reintentar
        if (empty && !_isScanning)
          FilledButton.tonalIcon(
            onPressed: _startScan,
            icon: const Icon(Icons.refresh),
            label: const Text('Volver a buscar'),
          )
        else if (!empty)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _nearby.length,
              itemBuilder: (context, index) {
                final w = _nearby[index];
                return Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.watch)),
                    title: Text(
                      w.device.platformName.isNotEmpty
                          ? w.device.platformName
                          : 'Wilobu Desconocido',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('ID: ${w.code}'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _onDeviceSelected(w),
                  ),
                );
              },
            ),
          )
        else
          const Spacer(), // Relleno si está escaneando pero vacío aún

        // Opción manual siempre visible al fondo
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: TextButton(
            onPressed: _onManualEntry,
            child: const Text('¿No lo encuentras? Ingresar código manualmente'),
          ),
        ),
      ],
    );
  }

  // --- PASO 2: CONFIGURACIÓN ---
  Widget _buildConfigStep(BuildContext context) {
    final theme = Theme.of(context);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera del dispositivo seleccionado
            Center(
              child: Column(
                children: [
                  Icon(
                    _manualCodeMode ? Icons.qr_code : Icons.check_circle_outline,
                    size: 64,
                    color: _manualCodeMode ? Colors.grey : Colors.green,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _manualCodeMode ? 'Registro Manual' : '¡Dispositivo encontrado!',
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (!_manualCodeMode)
                    Chip(label: Text('ID: ${_selectedWilobu?.code}')),
                ],
              ),
            ),
            const SizedBox(height: 32),

            Text('Información General', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre del dispositivo',
                hintText: 'Ej. Reloj de Ana',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit_outlined),
              ),
              validator: (v) => v!.isEmpty ? 'El nombre es obligatorio' : null,
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _ownerController,
              decoration: const InputDecoration(
                labelText: '¿Quién lo usará?',
                hintText: 'Ej. Ana',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),

            if (_manualCodeMode) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Código Wilobu (ID)',
                  hintText: 'Ubicado en la parte trasera',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.qr_code_2),
                ),
                validator: (v) => v!.isEmpty ? 'El código es obligatorio' : null,
              ),
            ],

            const SizedBox(height: 24),
            Text('Contacto de Emergencia', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _emergencyNameController,
              decoration: const InputDecoration(
                labelText: 'Nombre contacto',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.contact_phone_outlined),
              ),
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _emergencyPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Vincular Dispositivo', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wilobu_app/firebase_providers.dart';
import 'package:wilobu_app/theme/app_theme.dart';

/// Vista para configurar un dispositivo Wilobu
class DeviceSettingsView extends ConsumerStatefulWidget {
  final String deviceId;
  
  const DeviceSettingsView({super.key, required this.deviceId});

  @override
  ConsumerState<DeviceSettingsView> createState() => _DeviceSettingsViewState();
}

class _DeviceSettingsViewState extends ConsumerState<DeviceSettingsView> {
  final _generalMessageController = TextEditingController();
  final _medicaMessageController = TextEditingController();
  final _seguridadMessageController = TextEditingController();
  
  bool _isLoading = false;
  bool _isSaving = false;
  Map<String, dynamic>? _deviceData;

  @override
  void initState() {
    super.initState();
    _loadDeviceData();
  }

  @override
  void dispose() {
    _generalMessageController.dispose();
    _medicaMessageController.dispose();
    _seguridadMessageController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceData() async {
    setState(() => _isLoading = true);
    
    try {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null) return;
      
      final doc = await ref.read(firestoreProvider)
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(widget.deviceId)
          .get();
      
      if (doc.exists) {
        _deviceData = doc.data();
        
        // Cargar mensajes SOS
        final sosMessages = _deviceData?['sosMessages'] as Map<String, dynamic>?;
        _generalMessageController.text = sosMessages?['general'] ?? '';
        _medicaMessageController.text = sosMessages?['medica'] ?? '';
        _seguridadMessageController.text = sosMessages?['seguridad'] ?? '';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar configuración: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveMessages() async {
    setState(() => _isSaving = true);
    
    try {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null) return;
      
      await ref.read(firestoreProvider)
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(widget.deviceId)
          .update({
        'sosMessages': {
          'general': _generalMessageController.text,
          'medica': _medicaMessageController.text,
          'seguridad': _seguridadMessageController.text,
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Mensajes guardados'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _unlinkDevice() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desvincular Wilobu'),
        content: const Text(
          '¿Estás seguro de que deseas desvincular este dispositivo?\n\n'
          'El dispositivo se reiniciará a configuración de fábrica y deberás '
          'vincularlo nuevamente mediante Bluetooth.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    setState(() => _isLoading = true);
    try {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null) return;

      // Marcar cmd_reset antes de eliminar
      await ref.read(firestoreProvider)
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(widget.deviceId)
          .update({'cmd_reset': true});

      // Esperar 2 segundos para que el firmware reciba el reset
      await Future.delayed(const Duration(seconds: 2));

      // Eliminar documento del dispositivo
      await ref.read(firestoreProvider)
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(widget.deviceId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Dispositivo desvinculado'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al desvincular: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    return WilobuScaffold(
      appBar: AppBar(
        title: const Text('Configuración del Wilobu'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Información del dispositivo
          Card(
            child: ListTile(
              leading: const Icon(Icons.watch),
              title: const Text('ID del Dispositivo'),
              subtitle: Text(widget.deviceId),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Mensajes SOS personalizados
          const Text(
            'Mensajes de Alerta Personalizados',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Estos mensajes se enviarán a tus contactos de emergencia cuando actives una alerta.',
            style: TextStyle(color: Colors.grey),
          ),
          
          const SizedBox(height: 16),
          
          TextField(
            controller: _generalMessageController,
            decoration: const InputDecoration(
              labelText: 'Mensaje Alerta General',
              hintText: 'Ej: Necesito ayuda urgente',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          
          const SizedBox(height: 16),
          
          TextField(
            controller: _medicaMessageController,
            decoration: const InputDecoration(
              labelText: 'Mensaje Alerta Médica',
              hintText: 'Ej: Emergencia médica, requiero asistencia inmediata',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          
          const SizedBox(height: 16),
          
          TextField(
            controller: _seguridadMessageController,
            decoration: const InputDecoration(
              labelText: 'Mensaje Alerta Seguridad',
              hintText: 'Ej: Situación de peligro, contactar autoridades',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          
          const SizedBox(height: 24),
          
          ElevatedButton(
            onPressed: _isSaving ? null : _saveMessages,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar Mensajes'),
          ),
          
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          
          // Zona de peligro
          const Text(
            'Zona de Peligro',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          
          const SizedBox(height: 16),
          
          OutlinedButton.icon(
            onPressed: _unlinkDevice,
            icon: const Icon(Icons.link_off, color: Colors.red),
            label: const Text('Desvincular Dispositivo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

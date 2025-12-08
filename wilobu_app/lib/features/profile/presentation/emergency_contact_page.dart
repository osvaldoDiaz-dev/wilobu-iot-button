import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../infrastructure/profile_providers.dart';

/// Página para gestionar el contacto de emergencia
class EmergencyContactPage extends ConsumerStatefulWidget {
  const EmergencyContactPage({Key? key}) : super(key: key);

  @override
  ConsumerState<EmergencyContactPage> createState() =>
      _EmergencyContactPageState();
}

class _EmergencyContactPageState extends ConsumerState<EmergencyContactPage> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  bool _enabled = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  /// Carga los datos del perfil
  Future<void> _loadData() async {
    try {
      final profile =
          await ref.read(currentUserProfileProvider.future);
      _enabled = profile.emergencyContactEnabled;
      _nameController.text = profile.emergencyContactName ?? '';
      _phoneController.text = profile.emergencyContactPhone ?? '';
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar los datos: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Valida que los datos sean correctos
  bool _validateForm() {
    if (!_enabled) return true;

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre no puede estar vacío')),
      );
      return false;
    }

    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El teléfono no puede estar vacío')),
      );
      return false;
    }

    return true;
  }

  /// Guarda los cambios
  Future<void> _saveChanges() async {
    if (!_validateForm()) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(profileUpdateProvider.notifier).updateEmergencyContact(
            enabled: _enabled,
            contactName: _nameController.text.trim(),
            contactPhone: _phoneController.text.trim(),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contacto de emergencia actualizado exitosamente'),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacto de Emergencia'),
      ),
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stackTrace) => Center(
          child: Text('Error: $error'),
        ),
        data: (profile) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Card de información sobre contacto de emergencia
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Un contacto de emergencia será notificado cuando active la alerta SOS.',
                              style:
                                  Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Toggle para habilitar/deshabilitar
              SwitchListTile(
                title: const Text('Habilitar Contacto de Emergencia'),
                value: _enabled,
                onChanged: (value) {
                  setState(() => _enabled = value);
                },
              ),

              if (_enabled) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Nombre del Contacto',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Teléfono',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: '+1234567890',
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Botón de guardar
              if (_isLoading)
                const CircularProgressIndicator()
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveChanges,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Guardar Cambios'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

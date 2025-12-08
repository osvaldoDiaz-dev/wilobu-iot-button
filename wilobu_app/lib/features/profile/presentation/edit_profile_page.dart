import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../infrastructure/profile_providers.dart';

/// Página para editar la información del perfil
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({Key? key}) : super(key: key);

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late TextEditingController _displayNameController;
  late TextEditingController _phoneController;
  late TextEditingController _bioController;
  late TextEditingController _addressController;
  late TextEditingController _cityController;
  late TextEditingController _countryController;
  DateTime? _selectedDate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _phoneController = TextEditingController();
    _bioController = TextEditingController();
    _addressController = TextEditingController();
    _cityController = TextEditingController();
    _countryController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadProfileData();
  }

  /// Carga los datos del perfil actual en los campos
  Future<void> _loadProfileData() async {
    try {
      final profile =
          await ref.read(currentUserProfileProvider.future);
      _displayNameController.text = profile.displayName ?? '';
      _phoneController.text = profile.phoneNumber ?? '';
      _bioController.text = profile.bio ?? '';
      _addressController.text = profile.address ?? '';
      _cityController.text = profile.city ?? '';
      _countryController.text = profile.country ?? '';
      _selectedDate = profile.dateOfBirth;
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar el perfil: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  /// Guarda los cambios del perfil
  Future<void> _saveProfile() async {
    if (!_validateForm()) return;

    setState(() => _isLoading = true);

    try {
      final currentProfile =
          await ref.read(currentUserProfileProvider.future);

      final updatedProfile = currentProfile.copyWith(
        displayName: _displayNameController.text.trim(),
        phoneNumber: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        address:
            _addressController.text.trim().isEmpty
                ? null
                : _addressController.text.trim(),
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        country: _countryController.text.trim().isEmpty
            ? null
            : _countryController.text.trim(),
        dateOfBirth: _selectedDate,
      );

      await ref.read(profileUpdateProvider.notifier).updateProfile(
            updatedProfile,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil actualizado exitosamente')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Valida el formulario
  bool _validateForm() {
    if (_displayNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre no puede estar vacío')),
      );
      return false;
    }
    return true;
  }

  /// Abre un selector de fecha
  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final updateState = ref.watch(profileUpdateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Perfil'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTextField(
              controller: _displayNameController,
              label: 'Nombre Completo',
              icon: Icons.person,
              hint: 'Tu nombre',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _phoneController,
              label: 'Teléfono',
              icon: Icons.phone,
              hint: '+1234567890',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _bioController,
              label: 'Biografía',
              icon: Icons.info,
              hint: 'Cuéntanos sobre ti',
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _addressController,
              label: 'Dirección',
              icon: Icons.location_on,
              hint: 'Tu dirección',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _cityController,
              label: 'Ciudad',
              icon: Icons.location_city,
              hint: 'Ciudad',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _countryController,
              label: 'País',
              icon: Icons.public,
              hint: 'País',
            ),
            const SizedBox(height: 16),
            _buildDateSelector(context),
            const SizedBox(height: 24),
            updateState.maybeWhen(
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              orElse: () => SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Guardar Cambios'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Construye un campo de texto personalizado
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Construye el selector de fecha
  Widget _buildDateSelector(BuildContext context) {
    return InkWell(
      onTap: () => _selectDate(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Fecha de Nacimiento',
          prefixIcon: const Icon(Icons.cake),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          _selectedDate != null
              ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
              : 'Seleccionar fecha',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/contacts_provider.dart';

class ManageContactsPage extends ConsumerStatefulWidget {
  final String deviceId;

  const ManageContactsPage({super.key, required this.deviceId});

  @override
  ConsumerState<ManageContactsPage> createState() => _ManageContactsPageState();
}

class _ManageContactsPageState extends ConsumerState<ManageContactsPage> {
  final _emailController = TextEditingController();
  final _relationController = TextEditingController();
  
  String? _searchError;
  Map<String, dynamic>? _foundUser;
  bool _isAdding = false;

  @override
  void dispose() {
    _emailController.dispose();
    _relationController.dispose();
    super.dispose();
  }

  Future<void> _searchUser() async {
    setState(() {
      _searchError = null;
      _foundUser = null;
    });

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _searchError = 'Ingresa un email');
      return;
    }

    // Validación básica de email
    if (!email.contains('@')) {
      setState(() => _searchError = 'Email inválido');
      return;
    }

    try {
      final result = await ref.read(searchUserByEmailProvider(email).future);
      
      if (result == null) {
        setState(() => _searchError = 'Usuario no encontrado en Wilobu');
      } else {
        setState(() => _foundUser = result);
      }
    } catch (e) {
      setState(() => _searchError = 'Error al buscar: $e');
    }
  }

  Future<void> _addContact() async {
    if (_foundUser == null) return;
    
    final relation = _relationController.text.trim();
    if (relation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa la relación con el contacto')),
      );
      return;
    }

    setState(() => _isAdding = true);

    try {
      final addFn = ref.read(addEmergencyContactProvider);
      await addFn(
        deviceId: widget.deviceId,
        contactUid: _foundUser!['uid'] as String,
        contactEmail: _foundUser!['email'] as String,
        contactName: _foundUser!['name'] as String,
        relation: relation,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud enviada. El usuario debe aceptarla.'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Limpiar formulario
        _emailController.clear();
        _relationController.clear();
        setState(() {
          _foundUser = null;
          _searchError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al agregar contacto: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  Future<void> _removeContact(EmergencyContact contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Eliminar a ${contact.name} de los contactos de emergencia?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final removeFn = ref.read(removeEmergencyContactProvider);
      await removeFn(
        deviceId: widget.deviceId,
        contact: contact.toJson()..['email'] = contact.email,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contacto eliminado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(deviceContactsProvider(widget.deviceId));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        title: const Text('Contactos de Emergencia', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sección de búsqueda minimalista
            Card(
              elevation: isDark ? 4 : 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person_add, color: theme.colorScheme.primary, size: 28),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Agregar Contacto',
                            style: TextStyle(
                              fontSize: 20, 
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email del contacto',
                        hintText: 'ejemplo@correo.com',
                        prefixIcon: Icon(Icons.email_outlined, color: theme.colorScheme.primary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _searchUser(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _searchUser,
                        icon: const Icon(Icons.search, size: 22),
                        label: const Text('Buscar Usuario', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    
                    // Mensaje de error
                    if (_searchError != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade300, width: 1),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade700, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _searchError!, 
                                style: TextStyle(
                                  color: Colors.red.shade900, 
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    // Usuario encontrado
                    if (_foundUser != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade300, width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green.shade700, size: 24),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Usuario Encontrado',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                                child: Icon(Icons.person, color: theme.colorScheme.primary),
                              ),
                              title: Text(
                                _foundUser!['name'] as String,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                _foundUser!['email'] as String,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _relationController,
                              decoration: InputDecoration(
                                labelText: 'Relación',
                                hintText: 'Ej: Familiar, Amigo, Vecino',
                                prefixIcon: const Icon(Icons.people),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _isAdding ? null : _addContact,
                                icon: _isAdding 
                                  ? const SizedBox(
                                      width: 20, 
                                      height: 20, 
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.person_add, size: 20),
                                label: Text(
                                  _isAdding ? 'Agregando...' : 'Agregar Contacto',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Título de lista de contactos
            const Text(
              'Contactos Actuales',
              style: TextStyle(
                fontSize: 18, 
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            contactsAsync.when(
              data: (contacts) {
                if (contacts.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.people_outline, 
                            size: 64, 
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No hay contactos de emergencia',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Busca y agrega contactos arriba',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                
                return Column(
                  children: contacts.map((contact) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                          child: Icon(Icons.person, color: theme.colorScheme.primary),
                        ),
                        title: Text(
                          contact.name, 
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              contact.email,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              contact.relation,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.red.shade600),
                          onPressed: () => _removeContact(contact),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, stack) => Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Error al cargar contactos: $error',
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../domain/user_profile.dart';

/// Widget que muestra información del perfil en modo lectura
class ProfileInfoCard extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback? onEdit;

  const ProfileInfoCard({
    Key? key,
    required this.profile,
    this.onEdit,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Foto de perfil
            Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: profile.profilePhotoUrl != null
                      ? NetworkImage(profile.profilePhotoUrl!)
                      : null,
                  child: profile.profilePhotoUrl == null
                      ? const Icon(Icons.person, size: 50)
                      : null,
                ),
                if (onEdit != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: onEdit,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Nombre
            Text(
              profile.displayName ?? 'Sin nombre',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // Email
            Text(
              profile.email,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
              textAlign: TextAlign.center,
            ),
            if (profile.bio != null && profile.bio!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                profile.bio!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (profile.phoneNumber != null && profile.phoneNumber!.isNotEmpty)
              ...[
              const SizedBox(height: 12),
              Text(
                'Teléfono: ${profile.phoneNumber}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Widget para mostrar una sección de información del perfil
class ProfileInfoSection extends StatelessWidget {
  final String title;
  final String? value;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isEditable;

  const ProfileInfoSection({
    Key? key,
    required this.title,
    this.value,
    required this.icon,
    this.onTap,
    this.isEditable = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).primaryColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  value ?? 'No configurado',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (isEditable && onTap != null)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: onTap,
            ),
        ],
      ),
    );
  }
}

/// Widget para la sección de preferencias (toggles)
class PreferenceToggleTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  const PreferenceToggleTile({
    Key? key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(icon),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Widget para mostrar información de contacto de emergencia
class EmergencyContactCard extends StatelessWidget {
  final bool enabled;
  final String? name;
  final String? phone;
  final VoidCallback? onEdit;

  const EmergencyContactCard({
    Key? key,
    required this.enabled,
    this.name,
    this.phone,
    this.onEdit,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      color: enabled ? Colors.green.shade50 : Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.emergency,
                      color: enabled ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Contacto de Emergencia',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: onEdit,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (enabled && name != null && phone != null) ...[
              Text('Nombre: $name', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text('Teléfono: $phone',
                  style: Theme.of(context).textTheme.bodyMedium),
            ] else
              Text(
                enabled ? 'Sin información de contacto' : 'Deshabilitado',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}

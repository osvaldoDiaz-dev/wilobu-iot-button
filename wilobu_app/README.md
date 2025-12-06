# Wilobu App

Aplicación móvil Flutter para el sistema Wilobu de alertas IoT.

## Características

- 🔐 Autenticación con Firebase Auth
- 📱 Gestión de dispositivos Wilobu
- 👥 Contactos de emergencia con búsqueda por email
- 🚨 Alertas SOS en tiempo real
- 🗺️ Visualización de ubicación de emergencias
- 🔵 Provisioning Bluetooth para nuevos dispositivos

## Requisitos

- Flutter SDK 3.10+
- Android SDK 21+
- iOS 12+
- Firebase configurado (google-services.json)

## Instalación

```bash
flutter pub get
flutter run
```

## Arquitectura

Proyecto organizado por features siguiendo Clean Architecture:

```
lib/
├── features/
│   ├── auth/          # Login y registro
│   ├── contacts/      # Gestión de contactos
│   ├── devices/       # CRUD de dispositivos
│   ├── home/          # Dashboard principal
│   └── sos/           # Sistema de alertas
├── ble/               # Bluetooth Low Energy
├── theme/             # Temas y estilos
├── router.dart        # Navegación con GoRouter
└── main.dart          # Entry point
```

## Providers (Riverpod)

- `authProvider`: Estado de autenticación
- `userDevicesStreamProvider`: Stream de dispositivos del usuario
- `deviceContactsProvider`: Contactos de emergencia por dispositivo
- `searchUserByEmailProvider`: Búsqueda de usuarios

## Firebase

- **Auth**: Autenticación email/password
- **Firestore**: 
  - `users/{uid}` - Perfiles de usuario
  - `users/{uid}/devices/{deviceId}` - Dispositivos vinculados
- **Cloud Functions**: Notificaciones FCM

## Paquetes Principales

- `flutter_riverpod` - State management
- `go_router` - Navigation
- `cloud_firestore` - Database
- `firebase_auth` - Authentication
- `flutter_blue_plus` - Bluetooth
- `url_launcher` - External links

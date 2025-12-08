# 🔘 Wilobu - IoT Emergency Button System

**Wilobu** es un sistema de botón IoT de emergencia con monitoreo en tiempo real, integración con contactos de emergencia, y provisioning por Bluetooth.

## 📱 Stack Tecnológico

### App Móvil (Flutter)
- **Framework**: Flutter 3.10+
- **State Management**: Riverpod 2.5.1
- **Navigation**: GoRouter 14.x
- **Backend**: Firebase Auth, Cloud Firestore, Cloud Functions
- **Hardware**: BLE provisioning, location tracking
- **Maps**: FlutterMap + OpenStreetMap

### Hardware (ESP32)
- **Microcontroller**: ESP32 con módulo A7670SA (variantes A/B/C)
- **Protocolos**: BLE (provisioning), HTTP/HTTPS (reporting)
- **Almacenamiento**: NVRAM (configuración persistente)
- **Características**: Botón físico para SOS, monitoreo de batería, heartbeat cada 5 min

### Backend (Firebase)
- **Autenticación**: Firebase Auth
- **Base de datos**: Cloud Firestore con reglas de seguridad
- **Serverless**: Cloud Functions (Node.js)
- **Proxy**: Cloudflare Worker para HTTPS

---

## 🚀 Quick Start

### Requisitos
- Flutter 3.10+, Dart 3.0+
- Node.js 16+
- Firebase CLI
- PlatformIO (para firmware)

### Setup Inicial

**App Móvil:**
```bash
cd wilobu_app
flutter pub get
flutter run
```

**Firebase:**
```bash
firebase login
firebase deploy --only firestore:rules,functions
```

**Firmware:**
```bash
cd wilobu_firmware
platformio run --target upload
```

## 📋 Características Principales

### 👤 Gestión de Perfil
- Editar nombre, email, teléfono
- Contacto de emergencia
- Preferencias de notificación
- Sincronización en tiempo real

### 🔌 Gestión de Dispositivos
- Vincular/desvincular por BLE
- Apodo personalizado
- Monitoreo de batería
- Ubicación en tiempo real

### 👥 Contactos de Emergencia
- Agregar contactos
- Compartir acceso como "viewer"
- Recibir alertas SOS
- Ver ubicación en mapa

### 🆘 Sistema SOS
- 3 tipos de alertas: General, Médica, Seguridad
- Notificaciones en tiempo real
- Ubicación automática

## 🔄 Flujos Principales

### Provisioning
1. Usuario vincula dispositivo por BLE
2. Ingresa PIN (1234)
3. App envía credenciales Firebase
4. Dispositivo se sincroniza

### SOS Activation
1. Usuario presiona botón 3 seg
2. Dispositivo envía alerta a Firebase
3. Cloud Function notifica contactos
4. Contactos ven ubicación en mapa

## 📚 Documentación

- **App Mobile**: `wilobu_app/lib/` - Comentarios en código
- **Firestore Rules**: `firestore.rules`
- **Cloud Functions**: `functions/index.js`
- **Firmware**: `wilobu_firmware/src/` - Comentarios en código
- **Cloudflare Worker**: `cloudflare-worker/worker.js`

## 🛠️ Desarrollo

### Estructura Proyecto

```
wilobu_app/
├── lib/features/        # Features por módulo
├── lib/theme/           # Temas
└── lib/router.dart      # Rutas

wilobu_firmware/
├── src/                 # Código fuente C++
└── platformio.ini       # Configuración
```

### Crear Feature Nueva
```
lib/features/{nombre}/
├── domain/              # Models
├── infrastructure/      # Services
└── presentation/        # UI
```

### Build
```bash
# Android APK
flutter build apk --release

# iOS
flutter build ios --release
```

## 🐛 Troubleshooting

| Problema | Solución |
|----------|----------|
| BLE no conecta | Permisos Bluetooth + reiniciar |
| Ubicación no actualiza | Permisos de localización |
| Alertas no llegan | Notificaciones habilitadas |
| Worker 401 | Verificar secrets en Cloudflare |

## 📱 Platforms

- ✅ Android (minSdk 24)
- ✅ iOS (minTarget 11.0)
- ⏳ Web (experimental)

## 📄 License

Propietario - Todos los derechos reservados

---

**Última actualización**: 8 de Diciembre, 2025  
**Versión**: 2.0.1  
**Estado**: ✅ Producción


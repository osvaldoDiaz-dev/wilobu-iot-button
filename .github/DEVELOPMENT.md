# Instrucciones de Desarrollo - Wilobu

## Flujo de Trabajo

### 1. Desarrollo de App (Flutter)
```powershell
cd wilobu_app
flutter pub get
flutter run -d ZY22KQD8XM
```

### 2. Hot Reload
Presiona `r` en terminal para hot reload después de cambios en UI.

### 3. Deployment Firebase
```powershell
cd ..  # Desde raíz del proyecto
firebase deploy --only firestore:rules --project wilobu-d21b2
firebase deploy --only functions --project wilobu-d21b2
```

### 4. Firmware ESP32
```powershell
cd wilobu_firmware
pio run -t upload
pio device monitor  # Ver logs serial
```

## Comandos Útiles

### Flutter
```bash
flutter clean                    # Limpiar build
flutter pub get                  # Instalar dependencias
flutter doctor                   # Diagnosticar instalación
flutter devices                  # Listar dispositivos
```

### Firebase
```bash
firebase login                   # Login
firebase projects:list           # Ver proyectos
firebase use wilobu-d21b2       # Seleccionar proyecto
```

### PlatformIO
```bash
pio run                         # Compilar
pio run -t upload               # Flashear
pio run -t clean                # Limpiar build
pio device list                 # Listar puertos COM
```

## Estructura de Branches

- `master` - Producción estable
- `develop` - Integración de features
- `feature/*` - Features individuales
- `hotfix/*` - Correcciones urgentes

## Testing

### App
```bash
cd wilobu_app
flutter test
```

### Functions
```bash
cd functions
npm test
```

## Troubleshooting Común

### "No pubspec.yaml found"
```bash
cd wilobu_app  # Asegúrate de estar en la carpeta correcta
```

### "Firebase project not found"
```bash
firebase use --add  # Agregar proyecto
```

### "Port already in use"
```bash
# Matar proceso en puerto
Get-Process -Id (Get-NetTCPConnection -LocalPort XXXX).OwningProcess | Stop-Process -Force
```

### "Device offline"
```bash
adb kill-server
adb start-server
adb devices
```

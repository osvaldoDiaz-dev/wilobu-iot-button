## 🔧 Guía de Troubleshooting - WILOBU

### ❌ Error: "No devices found"

**Solución:**
```bash
# Conecta tu dispositivo Android/iOS con USB
# Verifica que esté habilitado el "Debugging USB" (Android)
# O Trust en la notificación de iOS

flutter devices  # Debe mostrar tu dispositivo
```

---

### ❌ Error: "Flutter pub get" falla

**Solución:**
```bash
# Limpiar caché
flutter clean
flutter pub cache clean

# Intentar de nuevo
flutter pub get
```

---

### ❌ Error: "Firebase not initialized"

**Solución:**
- La app está configurada para capturar este error
- Continuará funcionando sin Firebase (solo con UI)
- Para usar Firebase completamente:
  1. Ve a Firebase Console
  2. Crea un proyecto
  3. Descarga `google-services.json`
  4. Coloca en: `android/app/google-services.json`

---

### ❌ Error: "Cannot find any assets"

**Solución:**
```bash
cd wilobu_app

# Verifica que exista
ls assets/images/

# Ejecuta nuevamente
flutter pub get
flutter run
```

---

### ❌ Error: "Module not found" o imports incorrectos

**Solución:**
```bash
flutter clean
flutter pub get
flutter run
```

---

### ⚠️ App lenta en primera ejecución

- **Normal**: Primera compilación puede tardar 2-5 minutos
- Espera a que termine
- Las siguientes serán más rápidas

---

### 📱 App no responde a toques

**Solución:**
```bash
# Ejecuta con verbose para ver qué está pasando
flutter run -v

# Revisa los logs buscando "error" o "exception"
```

---

### 🔄 Reinicar completamente

```bash
cd wilobu_app

# Nuclear option
flutter clean
rm -rf .dart_tool
rm pubspec.lock
rm -rf build

# Comenzar de nuevo
flutter pub get
flutter run -v
```

---

### ✅ Si todo falla

Verifica que cumples requisitos mínimos:
- [ ] Flutter 3.38+ instalado: `flutter --version`
- [ ] Dispositivo conectado: `flutter devices`
- [ ] Conexión a Internet
- [ ] Android 21+ o iOS 12+
- [ ] Gradle 7.0+ (Android)

Luego abre un issue en: https://github.com/osvaldoDiaz-dev/wilobu/issues

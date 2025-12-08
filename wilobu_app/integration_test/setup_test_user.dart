// ============================================================================
// SCRIPT DE CONFIGURACIÓN - USUARIO DE PRUEBA PERMANENTE
// ============================================================================
// 
// Este script crea un usuario de prueba permanente en Firebase para
// ejecutar las pruebas de aceptación.
//
// Ejecutar con:
//   flutter test integration_test/setup_test_user.dart -d <device_id>
//
// Solo necesita ejecutarse UNA VEZ para configurar el usuario de prueba.
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:wilobu_app/firebase_options.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  // ═══════════════════════════════════════════════════════════════════════════
  // DATOS DEL USUARIO DE PRUEBA PERMANENTE
  // ═══════════════════════════════════════════════════════════════════════════
  const testUserEmail = 'wilobu.test@gmail.com';
  const testUserPassword = 'WilobuTest2025!';
  const testUserName = 'Usuario Wilobu Test';
  
  test('Configurar Usuario de Prueba Permanente', () async {
    debugPrint('');
    debugPrint('══════════════════════════════════════════════════════════════');
    debugPrint('  CONFIGURACIÓN DE USUARIO DE PRUEBA - WILOBU');
    debugPrint('══════════════════════════════════════════════════════════════');
    debugPrint('');
    
    // Inicializar Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;
    
    String uid;
    
    try {
      // Intentar crear nuevo usuario
      debugPrint('[1/4] Creando usuario en Firebase Auth...');
      final userCredential = await auth.createUserWithEmailAndPassword(
        email: testUserEmail,
        password: testUserPassword,
      );
      uid = userCredential.user!.uid;
      debugPrint('      ✅ Usuario CREADO: $uid');
      
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // Usuario ya existe, hacer login
        debugPrint('[1/4] Usuario ya existe, iniciando sesión...');
        final userCredential = await auth.signInWithEmailAndPassword(
          email: testUserEmail,
          password: testUserPassword,
        );
        uid = userCredential.user!.uid;
        debugPrint('      ✅ Sesión iniciada: $uid');
      } else {
        rethrow;
      }
    }
    
    // Crear/actualizar perfil en Firestore
    debugPrint('[2/4] Creando perfil en Firestore...');
    await firestore.collection('users').doc(uid).set({
      'email': testUserEmail.toLowerCase().trim(),
      'name': testUserName,
      'displayName': testUserName,
      'fcmTokens': [],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('      ✅ Perfil creado/actualizado');
    
    // Crear dispositivo con contactos de emergencia
    debugPrint('[3/4] Creando dispositivo con contactos de emergencia...');
    final deviceId = 'WILOBU-TEST-001';
    await firestore.collection('users').doc(uid).collection('devices').doc(deviceId).set({
      'ownerUid': uid,
      'deviceId': deviceId,
      'name': 'Wilobu Test Device',
      'status': 'online',
      'lastLocation': {
        'geopoint': const GeoPoint(-33.4489, -70.6693), // Santiago, Chile
        'timestamp': FieldValue.serverTimestamp(),
      },
      'emergencyContacts': [
        {
          'uid': 'contact_madre_001',
          'name': 'Madre',
          'relation': 'Familiar',
          'phone': '+56912345678',
        },
        {
          'uid': 'contact_tutor_002',
          'name': 'Tutor Legal',
          'relation': 'Tutor',
          'phone': '+56923456789',
        },
        {
          'uid': 'contact_profesor_003',
          'name': 'Profesor',
          'relation': 'Educador',
          'phone': '+56934567890',
        },
      ],
      'sosMessages': {
        'general': '¡ALERTA! El usuario ha activado una alerta de emergencia general.',
        'medica': '¡ALERTA MÉDICA! El usuario requiere asistencia médica urgente.',
        'seguridad': '¡ALERTA DE SEGURIDAD! El usuario se encuentra en una situación de peligro.',
      },
      'otaProgress': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('      ✅ Dispositivo creado con 3 contactos de emergencia');
    
    // Verificar datos
    debugPrint('[4/4] Verificando configuración...');
    final userDoc = await firestore.collection('users').doc(uid).get();
    final deviceDoc = await firestore.collection('users').doc(uid).collection('devices').doc(deviceId).get();
    
    expect(userDoc.exists, isTrue);
    expect(deviceDoc.exists, isTrue);
    
    final contacts = deviceDoc.data()?['emergencyContacts'] as List<dynamic>;
    expect(contacts.length, equals(3));
    
    debugPrint('');
    debugPrint('══════════════════════════════════════════════════════════════');
    debugPrint('  ✅ USUARIO DE PRUEBA CONFIGURADO EXITOSAMENTE');
    debugPrint('══════════════════════════════════════════════════════════════');
    debugPrint('');
    debugPrint('  📧 Email:     $testUserEmail');
    debugPrint('  🔑 Password:  $testUserPassword');
    debugPrint('  🆔 UID:       $uid');
    debugPrint('  📱 Device:    $deviceId');
    debugPrint('  👥 Contactos: ${contacts.length}');
    debugPrint('');
    debugPrint('  CONTACTOS DE EMERGENCIA:');
    for (final contact in contacts) {
      debugPrint('    - ${contact['name']} (${contact['relation']})');
    }
    debugPrint('');
    debugPrint('══════════════════════════════════════════════════════════════');
    debugPrint('  Ahora puede ejecutar las pruebas de aceptación:');
    debugPrint('  flutter test integration_test/wilobu_acceptance_tests.dart -d <device>');
    debugPrint('══════════════════════════════════════════════════════════════');
    debugPrint('');
    
    await auth.signOut();
  });
}

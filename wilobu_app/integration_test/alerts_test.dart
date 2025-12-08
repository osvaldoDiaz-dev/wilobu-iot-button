// ============================================================================
// TESTS DE ALERTAS SOS - WILOBU
// ============================================================================
// 
// Ejecutar con:
//   flutter test integration_test/alerts_test.dart -d <device_id>
//
// Usa el usuario de prueba: wilobu.test@gmail.com
// Ubicación hardcodeada: Antofagasta, Chile (-23.6509, -70.3975)
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

  // ===== CONSTANTES DE PRUEBA =====
  const testUserEmail = 'wilobu.test@gmail.com';
  const testUserPassword = 'WilobuTest2025!';
  const testDeviceId = '781C3CB994FC'; // Dispositivo real
  const hardcodedLat = -23.6509;
  const hardcodedLng = -70.3975;

  late FirebaseAuth auth;
  late FirebaseFirestore firestore;
  late String testUserUid;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    auth = FirebaseAuth.instance;
    firestore = FirebaseFirestore.instance;
    
    // Cerrar sesión previa
    await auth.signOut();
    
    // Autenticarse con usuario de prueba
    debugPrint('\n🔐 Autenticando con $testUserEmail...');
    
    try {
      // Intentar login
      final credential = await auth.signInWithEmailAndPassword(
        email: testUserEmail,
        password: testUserPassword,
      );
      testUserUid = credential.user!.uid;
      debugPrint('✓ Autenticado como $testUserUid\n');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential' || e.code == 'wrong-password') {
        // Crear usuario de prueba si no existe
        debugPrint('⚠️ Usuario no encontrado, creando nuevo usuario de prueba...');
        final credential = await auth.createUserWithEmailAndPassword(
          email: testUserEmail,
          password: testUserPassword,
        );
        testUserUid = credential.user!.uid;
        
        // Crear documento del usuario
        await firestore.collection('users').doc(testUserUid).set({
          'email': testUserEmail,
          'name': 'Usuario de Prueba',
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        debugPrint('✓ Usuario de prueba creado: $testUserUid\n');
      } else {
        rethrow;
      }
    }
  });

  tearDownAll(() async {
    await auth.signOut();
    debugPrint('\n🔓 Sesión cerrada\n');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GRUPO 1: ENVÍO DE ALERTAS SOS
  // ═══════════════════════════════════════════════════════════════════════════
  group('Envío de Alertas SOS', () {
    test('Enviar alerta SOS general con ubicación', () async {
      debugPrint('📍 TEST: Enviar alerta SOS general');
      
      final deviceRef = firestore
          .collection('users').doc(testUserUid)
          .collection('devices').doc(testDeviceId);

      await deviceRef.set({
        'status': 'sos_general',
        'ownerUid': testUserUid,
        'lastLocation': {
          'geopoint': GeoPoint(hardcodedLat, hardcodedLng),
          'timestamp': FieldValue.serverTimestamp(),
        },
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final doc = await deviceRef.get();
      expect(doc.exists, true);
      expect(doc.data()?['status'], 'sos_general');
      
      final loc = doc.data()?['lastLocation'] as Map<String, dynamic>?;
      final geopoint = loc?['geopoint'] as GeoPoint?;
      expect(geopoint?.latitude, hardcodedLat);
      expect(geopoint?.longitude, hardcodedLng);
      
      debugPrint('   ✓ Alerta SOS general enviada con ubicación $hardcodedLat, $hardcodedLng');
    });

    test('Enviar alerta SOS médica', () async {
      debugPrint('📍 TEST: Enviar alerta SOS médica');
      
      final deviceRef = firestore
          .collection('users').doc(testUserUid)
          .collection('devices').doc(testDeviceId);

      await deviceRef.update({'status': 'sos_medica'});

      final doc = await deviceRef.get();
      expect(doc.data()?['status'], 'sos_medica');
      debugPrint('   ✓ Alerta SOS médica enviada');
    });

    test('Enviar alerta SOS seguridad', () async {
      debugPrint('📍 TEST: Enviar alerta SOS seguridad');
      
      final deviceRef = firestore
          .collection('users').doc(testUserUid)
          .collection('devices').doc(testDeviceId);

      await deviceRef.update({'status': 'sos_seguridad'});

      final doc = await deviceRef.get();
      expect(doc.data()?['status'], 'sos_seguridad');
      debugPrint('   ✓ Alerta SOS seguridad enviada');
    });

    test('Cancelar alerta (volver a online)', () async {
      debugPrint('📍 TEST: Cancelar alerta');
      
      final deviceRef = firestore
          .collection('users').doc(testUserUid)
          .collection('devices').doc(testDeviceId);

      await deviceRef.update({'status': 'online'});

      final doc = await deviceRef.get();
      expect(doc.data()?['status'], 'online');
      debugPrint('   ✓ Estado restaurado a online');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GRUPO 2: HISTORIAL DE ALERTAS ENVIADAS
  // ═══════════════════════════════════════════════════════════════════════════
  group('Historial de Alertas Enviadas', () {
    test('Registrar alerta en historial del dispositivo', () async {
      debugPrint('📍 TEST: Registrar en historial');
      
      final historyRef = firestore
          .collection('users').doc(testUserUid)
          .collection('devices').doc(testDeviceId)
          .collection('alertHistory');

      final alertData = {
        'type': 'sos_general',
        'timestamp': FieldValue.serverTimestamp(),
        'location': GeoPoint(hardcodedLat, hardcodedLng),
        'resolved': false,
      };

      final docRef = await historyRef.add(alertData);
      expect(docRef.id, isNotEmpty);

      final doc = await docRef.get();
      expect(doc.exists, true);
      expect(doc.data()?['type'], 'sos_general');
      debugPrint('   ✓ Alerta registrada en historial: ${docRef.id}');
    });

    test('Obtener historial de alertas enviadas', () async {
      debugPrint('📍 TEST: Obtener historial');
      
      final historyRef = firestore
          .collection('users').doc(testUserUid)
          .collection('devices').doc(testDeviceId)
          .collection('alertHistory')
          .orderBy('timestamp', descending: true)
          .limit(10);

      final snapshot = await historyRef.get();
      expect(snapshot.docs, isNotEmpty);
      debugPrint('   ✓ Historial obtenido: ${snapshot.docs.length} alertas');
    });

    test('Marcar alerta como resuelta', () async {
      debugPrint('📍 TEST: Marcar como resuelta');
      
      final historyRef = firestore
          .collection('users').doc(testUserUid)
          .collection('devices').doc(testDeviceId)
          .collection('alertHistory')
          .orderBy('timestamp', descending: true)
          .limit(1);

      final snapshot = await historyRef.get();
      if (snapshot.docs.isNotEmpty) {
        await snapshot.docs.first.reference.update({
          'resolved': true,
          'resolvedAt': FieldValue.serverTimestamp(),
        });

        final updated = await snapshot.docs.first.reference.get();
        expect(updated.data()?['resolved'], true);
        debugPrint('   ✓ Alerta marcada como resuelta');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GRUPO 3: HISTORIAL DE ALERTAS RECIBIDAS
  // ═══════════════════════════════════════════════════════════════════════════
  group('Historial de Alertas Recibidas', () {
    test('Registrar alerta recibida de usuario real', () async {
      debugPrint('📍 TEST: Registrar alerta recibida de usuario real');
      
      // Buscar un usuario real (Osvaldo) para usarlo como remitente
      String senderName = 'Osvaldo';
      String senderDeviceId = '781C3CB994FC';
      String? senderUid;
      
      // Buscar usuarios que contengan "osvaldo" en el email o nombre
      final usersSnapshot = await firestore.collection('users').get();
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final email = (data['email'] ?? '').toString().toLowerCase();
        final name = (data['name'] ?? '').toString().toLowerCase();
        if (email.contains('osvaldo') || name.contains('osvaldo')) {
          senderUid = doc.id;
          senderName = data['name'] ?? 'Osvaldo';
          debugPrint('   Encontrado usuario remitente: $senderName ($senderUid)');
          break;
        }
      }
      
      final receivedRef = firestore
          .collection('users').doc(testUserUid)
          .collection('receivedAlerts');

      final alertData = {
        'fromDeviceId': senderDeviceId,
        'fromUserName': senderName,
        'fromUserId': senderUid,
        'type': 'sos_general',
        'timestamp': FieldValue.serverTimestamp(),
        'location': GeoPoint(hardcodedLat, hardcodedLng),
        'acknowledged': false,
      };

      final docRef = await receivedRef.add(alertData);
      expect(docRef.id, isNotEmpty);
      debugPrint('   ✓ Alerta recibida de $senderName registrada: ${docRef.id}');
    });

    test('Obtener alertas recibidas', () async {
      debugPrint('📍 TEST: Obtener alertas recibidas');
      
      final receivedRef = firestore
          .collection('users').doc(testUserUid)
          .collection('receivedAlerts')
          .orderBy('timestamp', descending: true)
          .limit(10);

      final snapshot = await receivedRef.get();
      expect(snapshot.docs, isNotEmpty);
      debugPrint('   ✓ Alertas recibidas: ${snapshot.docs.length}');
    });

    test('Marcar alerta como reconocida', () async {
      debugPrint('📍 TEST: Marcar como reconocida');
      
      final receivedRef = firestore
          .collection('users').doc(testUserUid)
          .collection('receivedAlerts')
          .orderBy('timestamp', descending: true)
          .limit(1);

      final snapshot = await receivedRef.get();
      if (snapshot.docs.isNotEmpty) {
        await snapshot.docs.first.reference.update({
          'acknowledged': true,
          'acknowledgedAt': FieldValue.serverTimestamp(),
        });

        final updated = await snapshot.docs.first.reference.get();
        expect(updated.data()?['acknowledged'], true);
        debugPrint('   ✓ Alerta marcada como reconocida');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GRUPO 4: FLUJO COMPLETO
  // ═══════════════════════════════════════════════════════════════════════════
  group('Flujo Completo de Alerta', () {
    test('Simular flujo: envío → historial → resolución', () async {
      debugPrint('📍 TEST: Flujo completo de alerta');
      
      final deviceRef = firestore
          .collection('users').doc(testUserUid)
          .collection('devices').doc(testDeviceId);

      // 1. Dispositivo entra en estado SOS
      debugPrint('   1. Enviando alerta SOS...');
      await deviceRef.update({
        'status': 'sos_general',
        'lastLocation': {
          'geopoint': GeoPoint(hardcodedLat, hardcodedLng),
          'timestamp': FieldValue.serverTimestamp(),
        },
      });

      // 2. Registrar en historial
      debugPrint('   2. Registrando en historial...');
      final historyRef = deviceRef.collection('alertHistory');
      final alertDoc = await historyRef.add({
        'type': 'sos_general',
        'timestamp': FieldValue.serverTimestamp(),
        'location': GeoPoint(hardcodedLat, hardcodedLng),
        'resolved': false,
      });

      // 3. Resolver alerta
      debugPrint('   3. Resolviendo alerta...');
      await deviceRef.update({'status': 'online'});
      await alertDoc.update({
        'resolved': true,
        'resolvedAt': FieldValue.serverTimestamp(),
      });

      // Verificar estado final
      final finalDoc = await deviceRef.get();
      expect(finalDoc.data()?['status'], 'online');

      final resolvedAlert = await alertDoc.get();
      expect(resolvedAlert.data()?['resolved'], true);
      
      debugPrint('   ✓ Flujo completo ejecutado correctamente');
    });
  });
}

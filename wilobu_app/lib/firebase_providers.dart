import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'services/fcm_service.dart';

/// Proveedor global de FirebaseAuth
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

/// Proveedor global de Firestore
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

/// Proveedor global de FCM Service
final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService();
});

/// Proveedor para ejecutar la función de migración de dispositivos
final migrateDevicesFunctionProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final functions = FirebaseFunctions.instance;
  final callable = functions.httpsCallable('migrateDevicesFields');
  final result = await callable.call();
  return Map<String, dynamic>.from(result.data);
});

/// Proveedor para ejecutar migración de monitored_devices
final migrateMonitoredDevicesFunctionProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final functions = FirebaseFunctions.instance;
  final callable = functions.httpsCallable('migrateMonitoredDevices');
  final result = await callable.call();
  return Map<String, dynamic>.from(result.data);
});

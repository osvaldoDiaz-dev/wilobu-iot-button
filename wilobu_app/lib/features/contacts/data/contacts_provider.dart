import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wilobu_app/firebase_providers.dart';

/// Modelo simple de contacto de emergencia
class EmergencyContact {
  final String uid;
  final String name;
  final String relation;
  final String email;

  EmergencyContact({
    required this.uid,
    required this.name,
    required this.relation,
    required this.email,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json, String email) {
    return EmergencyContact(
      uid: json['uid'] as String,
      name: json['name'] as String,
      relation: json['relation'] as String,
      email: email,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'relation': relation,
    };
  }
}

/// Provider para buscar usuario por email en Firestore
final searchUserByEmailProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, email) async {
  if (email.trim().isEmpty) return null;
  
  final firestore = ref.watch(firestoreProvider);
  final query = await firestore
      .collection('users')
      .where('email', isEqualTo: email.trim().toLowerCase())
      .limit(1)
      .get();

  if (query.docs.isEmpty) return null;
  
  final doc = query.docs.first;
  return {
    'uid': doc.id,
    'email': doc.data()['email'] as String,
    'name': doc.data()['name'] as String? ?? 'Usuario',
  };
});

/// Provider para obtener los contactos de emergencia de un dispositivo específico
final deviceContactsProvider = StreamProvider.family<List<EmergencyContact>, String>((ref, deviceId) {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) return const Stream.empty();

  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('users')
      .doc(user.uid)
      .collection('devices')
      .doc(deviceId)
      .snapshots()
      .map((snapshot) {
    if (!snapshot.exists) return <EmergencyContact>[];
    
    final data = snapshot.data();
    if (data == null) return <EmergencyContact>[];
    
    final contactsData = data['emergencyContacts'] as List<dynamic>?;
    if (contactsData == null) return <EmergencyContact>[];

    return contactsData
        .map((c) => EmergencyContact.fromJson(c as Map<String, dynamic>, c['email'] as String? ?? ''))
        .toList();
  });
});

/// Provider para agregar un contacto de emergencia a un dispositivo
/// Ahora crea una solicitud que el contacto debe aceptar
final addEmergencyContactProvider = Provider((ref) {
  return ({
    required String deviceId,
    required String contactUid,
    required String contactEmail,
    required String contactName,
    required String relation,
  }) async {
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user == null) throw Exception('Usuario no autenticado');

    final firestore = ref.read(firestoreProvider);
    
    // Obtener el nombre del dispositivo
    final deviceDoc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .get();
    
    final deviceName = deviceDoc.data()?['name'] as String? ?? 'Wilobu';

    // Crear solicitud en la colección del usuario receptor
    await firestore
        .collection('users')
        .doc(contactUid)
        .collection('contactRequests')
        .add({
      'fromUid': user.uid,
      'fromName': user.displayName ?? user.email?.split('@')[0] ?? 'Usuario',
      'fromEmail': user.email ?? '',
      'deviceId': deviceId,
      'deviceName': deviceName,
      'relation': relation,
      'timestamp': FieldValue.serverTimestamp(),
    });
  };
});

/// Provider para eliminar un contacto de emergencia de un dispositivo
final removeEmergencyContactProvider = Provider((ref) {
  return ({
    required String deviceId,
    required Map<String, dynamic> contact,
  }) async {
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user == null) throw Exception('Usuario no autenticado');

    final firestore = ref.read(firestoreProvider);
    final deviceRef = firestore.collection('users').doc(user.uid).collection('devices').doc(deviceId);

    await deviceRef.update({
      'emergencyContacts': FieldValue.arrayRemove([contact])
    });
  };
});

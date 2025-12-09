import 'package:cloud_firestore/cloud_firestore.dart';
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

/// Provider para obtener viewers de un dispositivo
final deviceViewersProvider = StreamProvider.family<List<String>, String>((ref, deviceId) {
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
    if (!snapshot.exists) return <String>[];
    
    final data = snapshot.data();
    if (data == null) return <String>[];
    
    final viewers = data['viewerUids'] as List<dynamic>?;
    if (viewers == null) return <String>[];

    return viewers.cast<String>();
  });
});

/// Provider para enviar solicitud de contacto
final sendContactRequestProvider = FutureProvider.autoDispose
    .family<void, Map<String, dynamic>>((ref, params) async {
  final user = ref.read(firebaseAuthProvider).currentUser;
  if (user == null) throw Exception('Usuario no autenticado');

  final firestore = ref.read(firestoreProvider);
  final contactUid = params['contactUid'] as String;
  final deviceId = params['deviceId'] as String;

  // Obtener nombre del dispositivo
  final deviceDoc = await firestore
      .collection('users/${user.uid}/devices')
      .doc(deviceId)
      .get();

  final deviceName = deviceDoc.data()?['nickname'] ?? 'Wilobu';

  // Crear solicitud en contactRequests del receptor
  await firestore
      .collection('users/$contactUid/contactRequests')
      .add({
    'fromUid': user.uid,
    'fromName': user.displayName ?? user.email?.split('@')[0] ?? 'Usuario',
    'fromEmail': user.email ?? '',
    'deviceId': deviceId,
    'deviceName': deviceName,
    'timestamp': FieldValue.serverTimestamp(),
  });
});

/// Provider para remover viewer de dispositivo
final removeViewerProvider = FutureProvider.autoDispose
    .family<void, Map<String, dynamic>>((ref, params) async {
  final user = ref.read(firebaseAuthProvider).currentUser;
  if (user == null) throw Exception('Usuario no autenticado');

  final firestore = ref.read(firestoreProvider);
  final viewerUid = params['viewerUid'] as String;
  final deviceId = params['deviceId'] as String;

  final deviceRef = firestore
      .collection('users/${user.uid}/devices')
      .doc(deviceId);

  // Remover viewer
  await deviceRef.update({
    'viewerUids': FieldValue.arrayRemove([viewerUid]),
  });

  // También remover dispositivo de monitored_devices del viewer
  await firestore.collection('users').doc(viewerUid).update({
    'monitored_devices': FieldValue.arrayRemove([deviceId]),
  });
});

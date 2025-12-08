import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/user_profile.dart';
import '../domain/profile_exception.dart';

/// Servicio para gestionar los perfiles de usuario en Firestore
class ProfileService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const String _profilesCollection = 'users';

  ProfileService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Obtiene el perfil del usuario actual
  Future<UserProfile> getCurrentUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw ProfileException(message: 'No hay usuario autenticado');
    }
    return getUserProfile(user.uid);
  }

  /// Obtiene el perfil de un usuario por su UID
  Future<UserProfile> getUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection(_profilesCollection).doc(uid).get();
      
      if (!doc.exists) {
        throw ProfileNotFound();
      }

      return UserProfile.fromFirestore(doc);
    } catch (e) {
      if (e is ProfileException) rethrow;
      throw ProfileException(
        message: 'Error al obtener el perfil: $e',
      );
    }
  }

  /// Crea un nuevo perfil de usuario (generalmente después del registro)
  Future<UserProfile> createProfile(String uid, String email) async {
    try {
      final profile = UserProfile.initial(uid, email);
      
      await _firestore
          .collection(_profilesCollection)
          .doc(uid)
          .set(profile.toMap());

      return profile;
    } catch (e) {
      throw ProfileUpdateFailed(
        message: 'Error al crear el perfil: $e',
      );
    }
  }

  /// Actualiza el perfil del usuario
  Future<UserProfile> updateProfile(UserProfile profile) async {
    try {
      final updatedProfile = profile.copyWith(
        updatedAt: DateTime.now(),
      );

      await _firestore
          .collection(_profilesCollection)
          .doc(profile.uid)
          .update({
            ...updatedProfile.toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      return updatedProfile;
    } catch (e) {
      throw ProfileUpdateFailed(
        message: 'Error al actualizar el perfil: $e',
      );
    }
  }

  /// Actualiza solo campos específicos del perfil
  Future<void> updateProfileFields(
    String uid,
    Map<String, dynamic> fields,
  ) async {
    try {
      fields['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore
          .collection(_profilesCollection)
          .doc(uid)
          .update(fields);
    } catch (e) {
      throw ProfileUpdateFailed(
        message: 'Error al actualizar los campos del perfil: $e',
      );
    }
  }

  /// Obtiene un stream del perfil del usuario actual
  /// Útil para actualizaciones en tiempo real
  Stream<UserProfile> getCurrentUserProfileStream() {
    final user = _auth.currentUser;
    if (user == null) {
      throw ProfileException(message: 'No hay usuario autenticado');
    }
    return getUserProfileStream(user.uid);
  }

  /// Obtiene un stream del perfil de un usuario
  Stream<UserProfile> getUserProfileStream(String uid) {
    return _firestore
        .collection(_profilesCollection)
        .doc(uid)
        .snapshots()
        .map((doc) {
          if (!doc.exists) {
            throw ProfileNotFound();
          }
          return UserProfile.fromFirestore(doc);
        })
        .handleError((e) {
          throw e is ProfileException
              ? e
              : ProfileException(message: 'Error en el stream del perfil: $e');
        });
  }

  /// Actualiza la URL de la foto de perfil
  Future<void> updateProfilePhoto(String uid, String photoUrl) async {
    await updateProfileFields(uid, {'profilePhotoUrl': photoUrl});
  }

  /// Actualiza el nombre mostrado
  Future<void> updateDisplayName(String uid, String displayName) async {
    await updateProfileFields(uid, {'displayName': displayName});
  }

  /// Actualiza el teléfono de emergencia
  Future<void> updateEmergencyContact({
    required String uid,
    required bool enabled,
    required String contactName,
    required String contactPhone,
  }) async {
    await updateProfileFields(uid, {
      'emergencyContactEnabled': enabled,
      'emergencyContactName': contactName,
      'emergencyContactPhone': contactPhone,
    });
  }

  /// Actualiza las preferencias de notificaciones
  Future<void> updateNotificationPreferences(
    String uid,
    bool enabled,
  ) async {
    await updateProfileFields(uid, {'notificationsEnabled': enabled});
  }

  /// Actualiza las preferencias de compartir ubicación
  Future<void> updateLocationSharingPreference(
    String uid,
    bool enabled,
  ) async {
    await updateProfileFields(uid, {'locationSharingEnabled': enabled});
  }

  /// Elimina el perfil del usuario (generalmente cuando se elimina la cuenta)
  Future<void> deleteProfile(String uid) async {
    try {
      await _firestore.collection(_profilesCollection).doc(uid).delete();
    } catch (e) {
      throw ProfileUpdateFailed(
        message: 'Error al eliminar el perfil: $e',
      );
    }
  }
}

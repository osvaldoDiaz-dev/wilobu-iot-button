import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/user_profile.dart';
import '../infrastructure/profile_service.dart';

/// Provider del servicio de perfil
final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService();
});

/// Provider del perfil del usuario actual
final currentUserProfileProvider = FutureProvider<UserProfile>((ref) async {
  final profileService = ref.watch(profileServiceProvider);
  return profileService.getCurrentUserProfile();
});

/// Provider en tiempo real del perfil del usuario actual
/// Se actualiza automáticamente cuando cambian los datos en Firestore
final currentUserProfileStreamProvider =
    StreamProvider<UserProfile>((ref) {
  final profileService = ref.watch(profileServiceProvider);
  return profileService.getCurrentUserProfileStream();
});

/// Provider para el perfil de un usuario específico
final userProfileProvider = FutureProvider.family<UserProfile, String>((ref, uid) async {
  final profileService = ref.watch(profileServiceProvider);
  return profileService.getUserProfile(uid);
});

/// Provider en tiempo real para el perfil de un usuario específico
final userProfileStreamProvider =
    StreamProvider.family<UserProfile, String>((ref, uid) {
  final profileService = ref.watch(profileServiceProvider);
  return profileService.getUserProfileStream(uid);
});

/// Provider para gestionar la actualización del perfil
final profileUpdateProvider =
    StateNotifierProvider<ProfileUpdateNotifier, AsyncValue<void>>((ref) {
  final profileService = ref.watch(profileServiceProvider);
  return ProfileUpdateNotifier(profileService, ref);
});

/// Notifier para manejar las actualizaciones del perfil
class ProfileUpdateNotifier extends StateNotifier<AsyncValue<void>> {
  final ProfileService _profileService;
  final Ref _ref;

  ProfileUpdateNotifier(this._profileService, this._ref)
      : super(const AsyncValue.data(null));

  /// Actualiza el perfil completo
  Future<void> updateProfile(UserProfile profile) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _profileService.updateProfile(profile);
      // Invalida el provider para refrescar los datos
      _ref.invalidate(currentUserProfileProvider);
      _ref.invalidate(currentUserProfileStreamProvider);
    });
  }

  /// Actualiza el nombre mostrado
  Future<void> updateDisplayName(String displayName) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final profile = await _profileService.getCurrentUserProfile();
      await _profileService.updateDisplayName(profile.uid, displayName);
      _ref.invalidate(currentUserProfileProvider);
      _ref.invalidate(currentUserProfileStreamProvider);
    });
  }

  /// Actualiza la foto de perfil
  Future<void> updateProfilePhoto(String photoUrl) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final profile = await _profileService.getCurrentUserProfile();
      await _profileService.updateProfilePhoto(profile.uid, photoUrl);
      _ref.invalidate(currentUserProfileProvider);
      _ref.invalidate(currentUserProfileStreamProvider);
    });
  }

  /// Actualiza el contacto de emergencia
  Future<void> updateEmergencyContact({
    required bool enabled,
    required String contactName,
    required String contactPhone,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final profile = await _profileService.getCurrentUserProfile();
      await _profileService.updateEmergencyContact(
        uid: profile.uid,
        enabled: enabled,
        contactName: contactName,
        contactPhone: contactPhone,
      );
      _ref.invalidate(currentUserProfileProvider);
      _ref.invalidate(currentUserProfileStreamProvider);
    });
  }

  /// Actualiza las preferencias de notificaciones
  Future<void> updateNotificationPreferences(bool enabled) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final profile = await _profileService.getCurrentUserProfile();
      await _profileService.updateNotificationPreferences(profile.uid, enabled);
      _ref.invalidate(currentUserProfileProvider);
      _ref.invalidate(currentUserProfileStreamProvider);
    });
  }

  /// Actualiza las preferencias de compartir ubicación
  Future<void> updateLocationSharingPreference(bool enabled) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final profile = await _profileService.getCurrentUserProfile();
      await _profileService.updateLocationSharingPreference(profile.uid, enabled);
      _ref.invalidate(currentUserProfileProvider);
      _ref.invalidate(currentUserProfileStreamProvider);
    });
  }
}

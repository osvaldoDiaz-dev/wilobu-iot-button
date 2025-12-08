import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo de perfil de usuario
class UserProfile {
  final String uid;
  final String email;
  final String? displayName;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final String? bio;
  final String? address;
  final String? city;
  final String? country;
  final DateTime? dateOfBirth;
  final bool emergencyContactEnabled;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final bool notificationsEnabled;
  final bool locationSharingEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.uid,
    required this.email,
    this.displayName,
    this.phoneNumber,
    this.profilePhotoUrl,
    this.bio,
    this.address,
    this.city,
    this.country,
    this.dateOfBirth,
    this.emergencyContactEnabled = false,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.notificationsEnabled = true,
    this.locationSharingEnabled = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Crea una copia con cambios específicos
  UserProfile copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? phoneNumber,
    String? profilePhotoUrl,
    String? bio,
    String? address,
    String? city,
    String? country,
    DateTime? dateOfBirth,
    bool? emergencyContactEnabled,
    String? emergencyContactName,
    String? emergencyContactPhone,
    bool? notificationsEnabled,
    bool? locationSharingEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      bio: bio ?? this.bio,
      address: address ?? this.address,
      city: city ?? this.city,
      country: country ?? this.country,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      emergencyContactEnabled: emergencyContactEnabled ?? this.emergencyContactEnabled,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone: emergencyContactPhone ?? this.emergencyContactPhone,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      locationSharingEnabled: locationSharingEnabled ?? this.locationSharingEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Convierte el modelo a un mapa para Firestore
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'phoneNumber': phoneNumber,
      'profilePhotoUrl': profilePhotoUrl,
      'bio': bio,
      'address': address,
      'city': city,
      'country': country,
      'dateOfBirth': dateOfBirth,
      'emergencyContactEnabled': emergencyContactEnabled,
      'emergencyContactName': emergencyContactName,
      'emergencyContactPhone': emergencyContactPhone,
      'notificationsEnabled': notificationsEnabled,
      'locationSharingEnabled': locationSharingEnabled,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  /// Crea un modelo desde un DocumentSnapshot de Firestore
  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfile(
      uid: data['uid'] ?? '',
      email: data['email'] ?? '',
      displayName: data['displayName'],
      phoneNumber: data['phoneNumber'],
      profilePhotoUrl: data['profilePhotoUrl'],
      bio: data['bio'],
      address: data['address'],
      city: data['city'],
      country: data['country'],
      dateOfBirth: data['dateOfBirth'] is Timestamp
          ? (data['dateOfBirth'] as Timestamp).toDate()
          : null,
      emergencyContactEnabled: data['emergencyContactEnabled'] ?? false,
      emergencyContactName: data['emergencyContactName'],
      emergencyContactPhone: data['emergencyContactPhone'],
      notificationsEnabled: data['notificationsEnabled'] ?? true,
      locationSharingEnabled: data['locationSharingEnabled'] ?? false,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  /// Crea un perfil inicial para un nuevo usuario
  factory UserProfile.initial(String uid, String email) {
    return UserProfile(
      uid: uid,
      email: email,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'UserProfile(uid: $uid, email: $email, displayName: $displayName)';
  }
}

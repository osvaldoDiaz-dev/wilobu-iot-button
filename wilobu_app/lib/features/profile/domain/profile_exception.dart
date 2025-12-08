/// Excepciones para operaciones de perfil
class ProfileException implements Exception {
  final String message;
  final String? code;

  ProfileException({
    required this.message,
    this.code,
  });

  @override
  String toString() => 'ProfileException: $message ${code != null ? '($code)' : ''}';
}

class ProfileNotFound extends ProfileException {
  ProfileNotFound({String? code})
      : super(
          message: 'El perfil de usuario no fue encontrado',
          code: code,
        );
}

class ProfileUpdateFailed extends ProfileException {
  ProfileUpdateFailed({
    required String message,
    String? code,
  }) : super(
    message: message,
    code: code,
  );
}

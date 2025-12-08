import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> initialize() async {
    await _requestPermission();
    final token = await _messaging.getToken();
    if (token != null) {
      await _registerToken(token);
    }
    _messaging.onTokenRefresh.listen(_registerToken);
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  Future<void> _requestPermission() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );
  }

  Future<void> _registerToken(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _functions.httpsCallable('registerFcmToken').call({'token': token});
    } catch (_) {}
  }

  Future<void> unregisterToken() async {
    final token = await _messaging.getToken();
    if (token == null) return;
    try {
      await _functions.httpsCallable('unregisterFcmToken').call({'token': token});
    } catch (_) {}
  }

  void _handleForegroundMessage(RemoteMessage message) {
    // Implementar UI para mostrar notificaciones en foreground si es necesario
  }
}

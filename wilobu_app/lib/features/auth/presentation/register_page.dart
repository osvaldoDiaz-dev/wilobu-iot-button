import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import 'package:wilobu_app/firebase_providers.dart';
import 'package:wilobu_app/router.dart';

// Flag para indicar que es un nuevo registro (mostrar bienvenida en Home)
final justRegisteredProvider = StateProvider<bool>((ref) => false);

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/fondo_wilobu.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Logo Wilobu con sombra
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(40),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/wilobu_logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Título Wilobu
                      Text(
                        'Únete a Wilobu',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                          shadows: [
                            Shadow(
                              color: Colors.white,
                              blurRadius: 15,
                              offset: const Offset(0, 0),
                            ),
                            Shadow(
                              color: Colors.white,
                              blurRadius: 30,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(180),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Crea tu cuenta y protege a quienes amas',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade800,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Card con formulario
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(230),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purple.withAlpha(30),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Crear Cuenta',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: Colors.indigo.shade600,
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _emailController,
                              style: TextStyle(color: Colors.grey.shade900, fontSize: 16),
                              decoration: InputDecoration(
                                labelText: 'Correo electrónico',
                                labelStyle: TextStyle(color: Colors.grey.shade700),
                                hintStyle: TextStyle(color: Colors.grey.shade500),
                                prefixIcon: Icon(Icons.email_outlined, color: Colors.indigo.shade600),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey.shade400),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey.shade400),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.indigo.shade600, width: 2),
                                ),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Ingresa tu correo';
                                }
                                if (!value.contains('@')) {
                                  return 'Correo no válido';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              style: TextStyle(color: Colors.grey.shade900, fontSize: 16),
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                labelStyle: TextStyle(color: Colors.grey.shade700),
                                hintStyle: TextStyle(color: Colors.grey.shade500),
                                prefixIcon: Icon(Icons.lock_outline, color: Colors.indigo.shade600),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                    color: Colors.grey.shade600,
                                  ),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey.shade400),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey.shade400),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.indigo.shade600, width: 2),
                                ),
                              ),
                              obscureText: _obscurePassword,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Ingresa tu contraseña';
                                }
                                if (value.length < 6) {
                                  return 'Mínimo 6 caracteres';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                onPressed: _isLoading ? null : _submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.teal.shade500,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Registrarse',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(color: Colors.grey.shade700),
                            children: [
                              const TextSpan(text: '¿Ya tienes cuenta? '),
                              TextSpan(
                                text: 'Inicia sesión',
                                style: TextStyle(
                                  color: Colors.indigo.shade600,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final form = _formKey.currentState!;
    if (!form.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);

    final auth = ref.read(firebaseAuthProvider);
    final firestore = ref.read(firestoreProvider);

    try {
      // Suspender redirección automática del router
      ref.read(suspendRedirectProvider.notifier).state = true;
      
      // Crear usuario en Firebase Auth
      final userCredential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Crear documento del usuario en Firestore con modelo completo
      final defaultName = email.split('@')[0];
      await firestore.collection('users').doc(userCredential.user!.uid).set({
        'email': email.toLowerCase(),
        'name': defaultName,
        'displayName': defaultName, // Usado como fallback en Functions
        'fcmTokens': [], // Array vacío para tokens de notificaciones push
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      setState(() => _isLoading = false);
      
      if (!mounted) return;
      
      // Mostrar diálogo de éxito (para captura de pantalla)
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 64),
          title: const Text('¡Registro Exitoso!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tu cuenta ha sido creada correctamente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              Text(
                email,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  // Reactivar redirección y navegar
                  ref.read(suspendRedirectProvider.notifier).state = false;
                  Navigator.of(ctx).pop();
                  context.go('/home');
                },
                child: const Text('Continuar'),
              ),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      ref.read(suspendRedirectProvider.notifier).state = false;
      setState(() => _isLoading = false);
      final message = e.message ?? e.code;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade400,
        ),
      );
    } catch (e) {
      ref.read(suspendRedirectProvider.notifier).state = false;
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade400,
        ),
      );
    }
  }
}

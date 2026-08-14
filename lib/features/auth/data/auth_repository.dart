import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:saldo_claro/core/network/supabase_client.dart';

/// Repositorio de autenticación (Supabase Auth).
class AuthRepository {
  final SupabaseClient _client = supabase;

  Stream<AuthState> get authState => _client.auth.onAuthStateChange;

  bool get isLoggedIn => _client.auth.currentUser != null;

  User? get currentUser => _client.auth.currentUser;

  String? get userId => _client.auth.currentUser?.id;

  /// Registra un nuevo usuario y crea su perfil + datos por defecto.
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );

    final user = res.user;
    if (user == null) {
      throw AuthException('No se pudo crear la cuenta.');
    }

    // Perfil del usuario (el trigger de la BD también lo puede crear).
    await _client.from('profiles').upsert({
      'id': user.id,
      'email': email,
      'full_name': fullName,
    });
  }

  /// Inicia sesión con email y contraseña.
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Cierra la sesión actual.
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Actualiza el perfil del usuario.
  Future<void> updateProfile({String? fullName}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.auth.updateUser(
      UserAttributes(data: {'full_name': fullName}),
    );
    await _client.from('profiles').upsert({
      'id': user.id,
      'email': user.email,
      'full_name': fullName,
    });
  }
}

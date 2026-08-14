import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:saldo_claro/core/network/supabase_client.dart';
import 'package:saldo_claro/features/auth/data/auth_repository.dart';

/// Repositorio de autenticación compartido.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// Estado de la sesión de autenticación.
class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.error,
  });

  const AuthState.unknown()
      : status = AuthStatus.unknown,
        user = null,
        error = null;

  const AuthState.authenticated(this.user)
      : status = AuthStatus.authenticated,
        error = null;

  const AuthState.unauthenticated()
      : status = AuthStatus.unauthenticated,
        user = null,
        error = null;

  const AuthState.failure(this.error)
      : status = AuthStatus.failure,
        user = null;

  final AuthStatus status;
  final User? user;
  final Object? error;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isLoading => status == AuthStatus.unknown || status == AuthStatus.loading;

  AuthState copyWithLoading() => AuthState(
        status: AuthStatus.loading,
        user: user,
      );
}

enum AuthStatus { unknown, loading, authenticated, unauthenticated, failure }

/// Controlador de autenticación basado en Riverpod Notifier.
class AuthController extends Notifier<AuthState> {
  AuthController();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  AuthState build() {
    final user = SupabaseService.instance.currentUser;
    _startListening();
    if (user != null) return AuthState.authenticated(user);
    return const AuthState.unauthenticated();
  }

  void _startListening() {
    final sub = _repo.authState.listen((authState) {
      final session = authState.session;
      if (session != null) {
        state = AuthState.authenticated(session.user);
      } else {
        state = const AuthState.unauthenticated();
      }
    });
    ref.onDispose(sub.cancel);
  }

  Future<bool> signIn(String email, String password) async {
    state = state.copyWithLoading();
    try {
      await _repo.signIn(email: email, password: password);
      return true;
    } catch (e) {
      state = AuthState.failure(e);
      return false;
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    state = state.copyWithLoading();
    try {
      await _repo.signUp(email: email, password: password, fullName: fullName);
      return true;
    } catch (e) {
      state = AuthState.failure(e);
      return false;
    }
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AuthState.unauthenticated();
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

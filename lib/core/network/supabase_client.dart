import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Cliente singleton de Supabase (Auth + Base de datos).
///
/// Se inicializa una única vez en `main()` y se expone a toda la app.
class SupabaseService {
  SupabaseService._();

  static final SupabaseService instance = SupabaseService._();

  bool _initialized = false;

  /// Inicializa el cliente de Supabase (idempotente).
  Future<void> init() async {
    if (_initialized) return;
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    _initialized = true;
  }

  SupabaseClient get client {
    if (!_initialized) {
      throw StateError(
        'SupabaseService no inicializado. Llama a init() antes de usarlo.',
      );
    }
    return Supabase.instance.client;
  }

  User? get currentUser => client.auth.currentUser;

  bool get isLoggedIn => currentUser != null;
}

/// Acceso abreviado al cliente.
SupabaseClient get supabase => SupabaseService.instance.client;

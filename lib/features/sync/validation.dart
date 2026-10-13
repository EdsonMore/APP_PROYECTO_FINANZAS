/// Validaciones de los formularios de cuenta (Fase 3B). null = válido.
library;

final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
final _code = RegExp(r'^\d{6}$');

/// Mínimo de la contraseña: el mismo que se configura en Supabase.
const minPasswordLength = 6;

String? emailError(String value) => _email.hasMatch(value.trim()) ? null : 'Escribe un correo válido.';

String? passwordError(String value) =>
    value.length >= minPasswordLength ? null : 'Mínimo $minPasswordLength caracteres.';

String? repeatError(String password, String repeat) => password == repeat ? null : 'Las contraseñas no coinciden.';

String? codeError(String value) => _code.hasMatch(value.trim()) ? null : 'El código tiene 6 dígitos.';

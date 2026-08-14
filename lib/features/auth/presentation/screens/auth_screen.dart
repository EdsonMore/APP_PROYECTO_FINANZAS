import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/features/auth/presentation/providers/auth_provider.dart';
import 'package:saldo_claro/features/legal/presentation/screens/legal_screen.dart';

/// Pantalla de inicio de sesión / registro.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();

  bool _isRegistering = false;
  bool _obscurePassword = true;
  bool _acceptedLegal = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Al registrarse, el consentimiento a los documentos legales es obligatorio
    // (Ley N.º 29733). Si no lo aceptó, mostramos el aviso.
    if (_isRegistering && !_acceptedLegal) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Para crear tu cuenta debes aceptar los Términos y '
              'Condiciones y la Política de Privacidad.',
            ),
          ),
        );
      }
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final auth = ref.read(authControllerProvider.notifier);

    final bool ok;
    if (_isRegistering) {
      ok = await auth.signUp(
        email: email,
        password: password,
        fullName: _fullNameController.text.trim(),
      );
    } else {
      ok = await auth.signIn(email, password);
    }

    if (!ok && mounted) {
      final error = ref.read(authControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is Object ? 'Error: ${error.toString()}' : 'No se pudo continuar.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildLogo(),
                    const SizedBox(height: 32),
                    Text(
                      'Bienvenido a ${AppConfig.appName}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: const Color(ColorConfig.textPrimary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Captura automática de tus movimientos\nen Yape, BCP, Agora y Lemon Cash.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: const Color(ColorConfig.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_isRegistering) ...[
                      TextFormField(
                        controller: _fullNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nombre completo',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Ingresa tu nombre' : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Ingresa tu correo';
                        if (!v.contains('@')) return 'Correo inválido';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'Mínimo 6 caracteres'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    if (_isRegistering) ...[
                      _buildLegalConsentCheck(),
                      const SizedBox(height: 16),
                    ],
                    if (authState.isLoading)
                      const Center(
                        child: CircularProgressIndicator(),
                      )
                    else ...[
                      ElevatedButton(
                        onPressed: _submit,
                        child: Text(_isRegistering ? 'Crear cuenta' : 'Iniciar sesión'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => setState(() {
                          _isRegistering = !_isRegistering;
                        }),
                        child: Text(
                          _isRegistering
                              ? '¿Ya tienes cuenta? Inicia sesión'
                              : '¿Eres nuevo? Crea tu cuenta',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegalConsentCheck() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: _acceptedLegal,
          onChanged: (v) => setState(() => _acceptedLegal = v ?? false),
          activeColor: const Color(ColorConfig.accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: RichText(
              textAlign: TextAlign.left,
              text: TextSpan(
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.4,
                  color: const Color(ColorConfig.textSecondary),
                ),
                children: [
                  TextSpan(
                    text: 'Acepto los ',
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const LegalScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Términos y Condiciones',
                        style: TextStyle(
                          color: Color(ColorConfig.accent),
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationColor: Color(ColorConfig.accent),
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: ' y la '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const LegalScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Política de Privacidad',
                        style: TextStyle(
                          color: Color(ColorConfig.accent),
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationColor: Color(ColorConfig.accent),
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(
                    text:
                        ' de ${AppConfig.appName} para poder usar la captura '
                        'automática de movimientos.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B1FA2), Color(0xFF002A8F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 40),
    );
  }
}

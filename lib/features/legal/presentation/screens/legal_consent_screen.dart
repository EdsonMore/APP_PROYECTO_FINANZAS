import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/legal/legal_acceptance_store.dart';
import 'package:saldo_claro/features/legal/presentation/screens/legal_screen.dart';

/// Pantalla de consentimiento legal que se muestra tras iniciar sesión si el
/// usuario aún no aceptó los Términos y Condiciones y la Política de Privacidad.
///
/// Cumple el requisito de consentimiento previo, libre, expreso e informado
/// (Ley N.º 29733) antes de capturar notificaciones de apps financieras.
class LegalConsentScreen extends StatefulWidget {
  const LegalConsentScreen({
    super.key,
    required this.onAccepted,
    required this.onSignOut,
  });

  /// Se invoca cuando el usuario acepta y persiste su consentimiento.
  final VoidCallback onAccepted;

  /// Permite cerrar la sesión si el usuario no acepta.
  final VoidCallback onSignOut;

  @override
  State<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends State<LegalConsentScreen> {
  bool _accepting = false;

  Future<void> _accept() async {
    setState(() => _accepting = true);
    await LegalAcceptanceStore.instance.accept();
    if (mounted) widget.onAccepted();
  }

  void _openDocuments() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LegalScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7B1FA2), Color(0xFF002A8F)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(Icons.gavel,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Antes de empezar',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: const Color(ColorConfig.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Para capturar tus movimientos, ${AppConfig.appName} '
                        'necesita tu consentimiento. Estos son los puntos '
                        'clave:',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.5,
                      color: const Color(ColorConfig.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _PointCard(
                    icon: Icons.notifications_active_outlined,
                    text:
                        'Leerá solo las notificaciones de las apps financieras '
                        'que configures (Yape, BCP, Agora/Sip, Lemon Cash y otras).',
                  ),
                  const SizedBox(height: 12),
                  const _PointCard(
                    icon: Icons.view_sidebar_outlined,
                    text:
                        'Registrará compras e ingresos (monto, contra parte '
                        'y fecha). Tus datos son solo tuyos y tu cuenta está '
                        'protegida.',
                  ),
                  const SizedBox(height: 12),
                  const _PointCard(
                    icon: Icons.lock_outline,
                    text:
                        'NUNCA guarda contraseñas, códigos de seguridad (OTP) '
                        'ni números de tarjeta.',
                  ),
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: _openDocuments,
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Leer Términos y Política de Privacidad'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _accepting ? null : _accept,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Acepto y continuo'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(ColorConfig.accent),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _accepting ? null : widget.onSignOut,
                    child: const Text('No estoy de acuerdo. Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PointCard extends StatelessWidget {
  const _PointCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(ColorConfig.surface),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: const Color(ColorConfig.textPrimary)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.4,
                color: const Color(ColorConfig.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
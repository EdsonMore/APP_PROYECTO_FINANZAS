import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/providers/service_providers.dart';
import 'package:saldo_claro/features/legal/presentation/screens/legal_screen.dart';

/// Pantalla que verifica el permiso de acceso a notificaciones y, si no está
/// concedido, abre los ajustes del sistema Android.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  bool _granted = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final granted =
        await ref.read(notificationPermissionServiceProvider).isGranted();
    if (mounted) {
      setState(() {
        _granted = granted;
        _checking = false;
      });
    }
  }

  Future<void> _openSettings() async {
    await ref.read(notificationPermissionServiceProvider).openSettings();
    // Esperamos un poco para que el usuario pueda volver.
    Future.delayed(const Duration(milliseconds: 500), _check);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permiso de notificaciones')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                _granted ? Icons.verified : Icons.notifications_off_outlined,
                size: 84,
                color: Color(
                  _granted ? ColorConfig.success : ColorConfig.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _checking
                    ? 'Verificando acceso...'
                    : (_granted
                        ? '¡Permiso concedido! 🎉'
                        : 'Activá el acceso a notificaciones'),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(ColorConfig.textPrimary),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _granted
                    ? 'SaldoClaro ahora podrá capturar automáticamente tus '
                        'movimientos de Yape, BCP, Agora y Lemon Cash.'
                    : 'Para que ${AppConfig.appName} capture automáticamente tus '
                        'movimientos, es necesario que le permitas leer las '
                        'notificaciones de tu teléfono. Te llevaremos a los '
                        'ajustes del sistema.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.4,
                  color: const Color(ColorConfig.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tu información se mantiene encriptada y solo se procesa '
                'localmente para clasificar tus gastos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Color(ColorConfig.textSecondary),
                ),
              ),
              const Spacer(),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const LegalScreen()),
                  );
                },
                child: const Text('Términos y Condiciones y Privacidad'),
              ),
              const SizedBox(height: 12),
              if (_checking)
                const Center(child: CircularProgressIndicator())
              else if (!_granted)
                ElevatedButton.icon(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('Abrir ajustes'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

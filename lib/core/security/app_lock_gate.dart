import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_config.dart';
import 'lock_store.dart';
import 'security_providers.dart';

/// Puerta de seguridad que protege la interfaz con biometría/PIN del sistema.
///
/// - Al entrar (arranque tras autenticarse) pide autenticación si el bloqueo
///   biométrico está activo en los ajustes.
/// - Al volver a la app (`AppLifecycleState.resumed`) vuelve a bloquear.
/// - Si la biometría falla o no está inscrita, el sistema permite el
///   PIN/patrón/contraseña del dispositivo (`biometricOnly: false`).
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _unlocked = false;
  bool _biometricEnabled = false;
  bool _needsRelock = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initialize() async {
    final enabled = await LockStore.instance.isBiometricLockEnabled();
    if (!mounted) return;

    final supported = await ref.read(biometricServiceProvider).canAuthenticate();
    if (!mounted) return;

    setState(() {
      _biometricEnabled = enabled;
      _checking = false;
    });

    if (enabled && supported) {
      await _unlock();
    } else {
      setState(() => _unlocked = true);
    }
  }

  Future<void> _unlock() async {
    final granted = await ref
        .read(biometricServiceProvider)
        .authenticate(reason: 'Desbloquea ${AppConfig.appName}');
    if (!mounted) return;
    setState(() {
      _unlocked = granted;
      _needsRelock = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_biometricEnabled) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _needsRelock = true;
    } else if (state == AppLifecycleState.resumed && _needsRelock) {
      _needsRelock = false;
      _unlock();
    }
  }

  Future<void> _retry() async {
    setState(() => _checking = true);
    await _unlock();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_unlocked) return widget.child;
    return _LockScreen(onUnlock: _retry);
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(ColorConfig.accent).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.lock_outline, size: 44, color: Colors.white),
              ),
              const SizedBox(height: 24),
              Text(
                '${AppConfig.appName} bloqueado',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(ColorConfig.textPrimary),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Desbloquea con tu huella, FaceID o el PIN/patrón de tu '
                'dispositivo para ver tus finanzas.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(ColorConfig.textSecondary),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Desbloquear'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(ColorConfig.accent),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
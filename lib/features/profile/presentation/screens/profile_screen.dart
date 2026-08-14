import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/network/supabase_client.dart';
import 'package:saldo_claro/core/providers/service_providers.dart';
import 'package:saldo_claro/core/security/lock_store.dart';
import 'package:saldo_claro/core/security/security_providers.dart';
import 'package:saldo_claro/features/auth/presentation/providers/auth_provider.dart';
import 'package:saldo_claro/features/legal/presentation/screens/legal_screen.dart';

/// Pantalla de Perfil y Ajustes.
///
/// Muestra la sesión de Supabase (email), el estado del permiso de acceso a
/// notificaciones (con acceso directo a los ajustes del sistema) y las
/// acciones de sesión (cerrar sesión).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _notificationGranted = false;
  bool _checkingPermission = true;
  bool _biometricLockEnabled = false;
  bool _biometricSupported = false;
  bool _checkingBiometric = true;

  @override
  void initState() {
    super.initState();
    _refreshPermission();
    _loadSecuritySettings();
  }

  Future<void> _loadSecuritySettings() async {
    final enabled = await LockStore.instance.isBiometricLockEnabled();
    final supported = await ref.read(biometricServiceProvider).canAuthenticate();
    if (mounted) {
      setState(() {
        _biometricLockEnabled = enabled;
        _biometricSupported = supported;
        _checkingBiometric = false;
      });
    }
  }

  Future<void> _toggleBiometricLock(bool value) async {
    if (value && !_biometricSupported) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tu dispositivo no tiene biometría o credencial de bloqueo '
              'configurada (huella, FaceID o PIN).',
            ),
          ),
        );
      }
      return;
    }
    setState(() => _biometricLockEnabled = value);
    await LockStore.instance.setBiometricLockEnabled(value);
    if (value) {
      // Verifica que la autenticación funcione antes de volver a bloquear.
      final ok = await ref
          .read(biometricServiceProvider)
          .authenticate(reason: 'Configura el bloqueo de ${AppConfig.appName}');
      if (!ok && mounted) {
        setState(() => _biometricLockEnabled = false);
        await LockStore.instance.setBiometricLockEnabled(false);
      }
    }
  }

  Future<void> _refreshPermission() async {
    setState(() => _checkingPermission = true);
    final granted =
        await ref.read(notificationPermissionServiceProvider).isGranted();
    if (mounted) {
      setState(() {
        _notificationGranted = granted;
        _checkingPermission = false;
      });
    }
  }

  Future<void> _openNotificationSettings() async {
    await ref.read(notificationPermissionServiceProvider).openSettings();
    // Pequeña espera para que el usuario pueda volver de los ajustes.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) _refreshPermission();
  }

  Future<void> _signOut() async {
    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final email = user?.email ?? 'sesión@saldoclaro.app';
    final fullName =
        (user?.userMetadata?['full_name'] as String?)?.trim();
    final emailInitial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recomprobar permisos',
            onPressed: _refreshPermission,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(emailInitial: emailInitial, fullName: fullName, email: email),
          const SizedBox(height: 20),
          _buildPrivacyCard(),
          const SizedBox(height: 20),
          _buildNotificationsCard(),
          const SizedBox(height: 20),
          _buildSessionCard(),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '${AppConfig.appName} v1.0.0',
              style: const TextStyle(
                fontSize: 12,
                color: Color(ColorConfig.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader({
    required String emailInitial,
    required String? fullName,
    required String email,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(ColorConfig.surface),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: const Color(ColorConfig.accent).withValues(alpha: 0.25),
            child: Text(
              emailInitial,
              style: GoogleFonts.inter(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: const Color(ColorConfig.textPrimary),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            fullName ?? 'Mi cuenta',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: const Color(ColorConfig.textPrimary),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(ColorConfig.textSecondary),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(ColorConfig.success).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, size: 14, color: Color(ColorConfig.success)),
                SizedBox(width: 6),
                Text(
                  'Sesión activa en Supabase',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(ColorConfig.success),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyCard() {
    final isHidden = ref.watch(balanceHiddenProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(ColorConfig.surface),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.security_outlined,
                  size: 20, color: Color(ColorConfig.textPrimary)),
              SizedBox(width: 8),
              Text(
                'Seguridad y privacidad',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(ColorConfig.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _biometricLockEnabled,
            onChanged: _checkingBiometric ? null : _toggleBiometricLock,
            title: const Text(
              'Bloqueo biométrico',
              style: TextStyle(fontSize: 14, color: Color(ColorConfig.textPrimary)),
            ),
            subtitle: const Text(
              'Pide huella, FaceID o PIN al abrir SaldoClaro.',
              style: TextStyle(fontSize: 12, color: Color(ColorConfig.textSecondary)),
            ),
            secondary: const Icon(Icons.fingerprint),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: isHidden,
            onChanged: (value) =>
                ref.read(balanceHiddenProvider.notifier).setHidden(value),
            title: const Text(
              'Ocultar saldos (modo incógnito)',
              style: TextStyle(fontSize: 14, color: Color(ColorConfig.textPrimary)),
            ),
            subtitle: const Text(
              'Muestra "S/ ****" en el dashboard y los movimientos.',
              style: TextStyle(fontSize: 12, color: Color(ColorConfig.textSecondary)),
            ),
            secondary: const Icon(Icons.visibility_off_outlined),
          ),
          const Divider(color: Color(ColorConfig.surfaceAlt), height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LegalScreen()),
              );
            },
            title: const Text(
              'Información legal',
              style: TextStyle(fontSize: 14, color: Color(ColorConfig.textPrimary)),
            ),
            subtitle: const Text(
              'Términos y Condiciones y Política de Privacidad.',
              style: TextStyle(fontSize: 12, color: Color(ColorConfig.textSecondary)),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: Color(ColorConfig.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsCard() {
    final active = _notificationGranted && !_checkingPermission;
    final statusColor = active
        ? const Color(ColorConfig.success)
        : const Color(0xFFF39C12);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(ColorConfig.surface),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  size: 20, color: Color(ColorConfig.textPrimary)),
              const SizedBox(width: 8),
              Text(
                'Captura automática',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(ColorConfig.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _checkingPermission
                      ? 'Verificando acceso a notificaciones…'
                      : (active
                          ? 'Acceso a notificaciones: ACTIVO'
                          : 'Acceso a notificaciones: INACTIVO'),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(ColorConfig.textPrimary),
                  ),
                ),
              ),
            ],
          ),
          if (!active && !_checkingPermission) ...[
            const SizedBox(height: 8),
            const Text(
              'Permite que SaldoClaro lea tus notificaciones para capturar '
              'automáticamente los movimientos de Yape, BCP, Agora/Sip y Lemon.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(ColorConfig.textSecondary),
              ),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _openNotificationSettings,
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: Text(active ? 'Reabrir ajustes' : 'Conceder acceso'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(ColorConfig.textPrimary),
              side: const BorderSide(color: Color(ColorConfig.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(ColorConfig.surface),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_outline, size: 20, color: Color(ColorConfig.textPrimary)),
              SizedBox(width: 8),
              Text(
                'Sesión',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(ColorConfig.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(ColorConfig.danger),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
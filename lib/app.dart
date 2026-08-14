import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/legal/legal_acceptance_store.dart';
import 'core/permissions/notification_permission_service.dart';
import 'core/security/app_lock_gate.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/screens/auth_screen.dart';
import 'features/dashboard/data/account_repository.dart';
import 'features/dashboard/data/category_repository.dart';
import 'features/dashboard/presentation/screens/dashboard_screen.dart';
import 'features/legal/presentation/screens/legal_consent_screen.dart';
import 'features/permissions/presentation/screens/permissions_screen.dart';

/// Widget raíz de la aplicación.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const _RootFlow(),
    );
  }
}

/// Decide qué pantalla mostrar según el estado de autenticación.
class _RootFlow extends ConsumerWidget {
  const _RootFlow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    switch (authState.status) {
      case AuthStatus.unknown:
      case AuthStatus.loading:
        return const _SplashScreen();
      case AuthStatus.authenticated:
        return const _AuthenticatedGate();
      case AuthStatus.unauthenticated:
      case AuthStatus.failure:
        return const AuthScreen();
    }
  }
}

/// Tras autenticarse: inicializa datos por defecto y valida el permiso
/// de notificaciones antes de mostrar el dashboard.
class _AuthenticatedGate extends ConsumerStatefulWidget {
  const _AuthenticatedGate();

  @override
  ConsumerState<_AuthenticatedGate> createState() => _AuthenticatedGateState();
}

class _AuthenticatedGateState extends ConsumerState<_AuthenticatedGate> {
  bool _legalAccepted = false;
  bool _permissionGranted = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _checkLegalAcceptance();
    if (mounted && !_legalAccepted) return;
    await _ensureDefaults();
    await _requestNotificationPermission();
    await _checkPermission();
  }

  /// Verifica si el usuario ya aceptó los Términos y Condiciones y la
  /// Política de Privacidad (consentimiento exigido antes de capturar datos).
  Future<void> _checkLegalAcceptance() async {
    final accepted = await LegalAcceptanceStore.instance.hasAccepted();
    if (mounted) {
      setState(() {
        _legalAccepted = accepted;
        _checking = false;
      });
    }
  }

  /// Solicita el runtime permission de notificaciones (POST_NOTIFICATIONS,
  /// Android 13+). Evita que el interruptor del sistema quede bloqueado en gris
  /// y es la puerta para que el NotificationListenerService funcione.
  Future<void> _requestNotificationPermission() async {
    await NotificationPermissionService.instance.requestSystemNotifications();
  }

  Future<void> _ensureDefaults() async {
    try {
      await AccountRepository().ensureDefaults();
      await CategoryRepository().ensureDefaults();
    } catch (_) {
      // Si falla, el dashboard mostrará el estado de error correspondiente.
    }
  }

  Future<void> _checkPermission() async {
    final granted = await NotificationPermissionService.instance.isGranted();
    if (!granted) {
      _permissionGranted = false;
    } else {
      _permissionGranted = true;
      // Re-enlaza el NotificationListenerService con el sistema por si quedó
      // desvinculado tras un force-stop/ahorro de batería.
      await NotificationPermissionService.instance.requestRebind();
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const _SplashScreen();

    if (!_legalAccepted) {
      return LegalConsentScreen(
        onAccepted: () {
          setState(() => _legalAccepted = true);
          // Continúa el flujo pendiente tras aceptar.
          _continueOnboarding();
        },
        onSignOut: () {
          ref.read(authControllerProvider.notifier).signOut();
        },
      );
    }

    if (!_permissionGranted) {
      return const PermissionsScreen();
    }
    // El bloqueo biométrico envuelve el dashboard: se pide autenticación al
    // arrancar y cada vez que la app vuelve de segundo plano.
    return AppLockGate(child: const DashboardScreen());
  }

  /// Retoma el flujo de inicio tras el consentimiento legal: datos por
  /// defecto, runtime permission y chequeo de acceso a notificaciones.
  Future<void> _continueOnboarding() async {
    await _ensureDefaults();
    await _requestNotificationPermission();
    await _checkPermission();
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

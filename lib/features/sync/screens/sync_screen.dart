import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/text_link.dart';
import '../../../data/providers.dart';
import '../../settings/settings_screen.dart';
import '../auth_gateway.dart';
import '../providers.dart';
import 'account_form.dart';
import 'credentials_screens.dart';
import 'delete_account_screen.dart';

/// C1: con cuenta conectada, hasta que llegue la sincronización (3C).
const connectedNote = 'Tu cuenta está conectada. Mientras tanto, puedes seguir usando la app con tus datos '
    'locales. La sincronización completa llega en la próxima versión.';

/// "Sincronizar con la nube" (Fase 3B). Sin cuenta: crear o entrar. Con
/// cuenta: correo, aviso C1, cerrar sesión y borrar cuenta.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  /// Nombre de la ruta: los flujos de cuenta vuelven aquí al terminar.
  static const routeName = 'sync';

  static Route<void> route() =>
      MaterialPageRoute<void>(settings: const RouteSettings(name: routeName), builder: (_) => const SyncScreen());

  /// Vuelve a esta pantalla (o a la raíz) y muestra [message].
  static void finish(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).popUntil((r) => r.settings.name == routeName || r.isFirst);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final email = ref.watch(accountEmailProvider).value;
    return AccountScaffold(
      title: 'Sincronizar con la nube',
      children: email == null
          ? [
              Text(
                'Guarda una copia de tus datos en tu cuenta y úsalos en otro teléfono. '
                'Sin cuenta, todo sigue funcionando en este teléfono.',
                style: AppType.body.copyWith(color: p.ink),
              ),
              const SizedBox(height: Space.xl),
              AccountButton(
                label: 'Crear cuenta',
                busy: false,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SignUpScreen())),
              ),
              const SizedBox(height: Space.sm),
              Center(
                child: TextLink(
                  key: const Key('sync.signIn'),
                  label: 'Ya tengo cuenta',
                  semanticsLabel: 'Ya tengo cuenta',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SignInScreen())),
                ),
              ),
            ]
          : [
              Text('Conectado como $email', key: const Key('sync.email'), style: AppType.label.copyWith(color: p.ink)),
              const SizedBox(height: Space.md),
              Text(connectedNote, key: const Key('sync.note'), style: AppType.body.copyWith(color: p.inkMuted)),
              Divider(color: p.border, height: Space.xxl),
              SettingsRow(
                key: const Key('sync.signOut'),
                label: 'Cerrar sesión',
                value: 'Tus datos se quedan en este teléfono',
                chevron: true,
                onTap: () => _signOut(context, ref),
              ),
              SettingsRow(
                key: const Key('sync.delete'),
                label: 'Borrar cuenta',
                value: 'Borra tu cuenta y tus datos en la nube',
                chevron: true,
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DeleteAccountScreen())),
              ),
            ],
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Tus datos se quedan en este teléfono.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancelar')),
          TextButton(
              key: const Key('sync.signOut.confirm'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authGatewayProvider).signOut();
    } on AuthFailure {
      // Sin red igual se cierra la sesión local (supabase la borra igual).
    }
    // Todo vuelve a quedar pendiente: otra cuenta recibirá todos los datos.
    await ref.read(databaseProvider).detachSync();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('Sesión cerrada. Tus datos siguen en este teléfono.'), behavior: SnackBarBehavior.floating));
  }
}

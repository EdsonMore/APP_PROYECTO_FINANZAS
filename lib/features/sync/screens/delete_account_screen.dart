import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/providers.dart';
import '../../settings/legal_screen.dart';
import '../auth_gateway.dart';
import '../providers.dart';
import 'account_form.dart';
import 'sync_screen.dart';

/// Palabra que hay que escribir para habilitar el borrado (exacta).
const deleteWord = 'BORRAR';

/// Borrar cuenta (lo exige Play): cuenta y datos en la nube. Los datos del
/// teléfono se quedan.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authGatewayProvider).deleteAccount();
      // Todo vuelve a quedar pendiente (la cuenta ya no existe).
      await ref.read(databaseProvider).detachSync();
      if (mounted) SyncScreen.finish(context, 'Cuenta borrada. Tus datos siguen en este teléfono.');
    } on AuthFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AccountScaffold(title: 'Borrar cuenta', children: [
      Text(
        'Se borran tu cuenta y todos tus datos en la nube. Los de este teléfono se quedan. '
        'No se puede deshacer.',
        style: AppType.body.copyWith(color: p.ink),
      ),
      const SizedBox(height: Space.lg),
      AccountField(key: const Key('delete.field'), label: 'Escribe $deleteWord para confirmar', controller: _confirm),
      AccountButton(
        label: 'Borrar cuenta',
        busy: _busy,
        danger: true,
        onPressed: _confirm.text == deleteWord ? _delete : null,
      ),
      AccountError(_error),
      const SizedBox(height: Space.lg),
      SelectableText(
        'También puedes pedirlo escribiendo a $contactEmail.',
        key: const Key('delete.web'),
        style: AppType.caption.copyWith(color: p.inkMuted),
      ),
    ]);
  }
}

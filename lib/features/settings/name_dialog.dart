import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/providers.dart';
import '../onboarding/onboarding_screen.dart' show emojiRegex, validateSpaceName;

/// Diálogo chico para el nombre del espacio. Mismas reglas que el Onboarding.
Future<void> showNameDialog(BuildContext context, String? current) =>
    showDialog<void>(context: context, builder: (_) => _NameDialog(current: current));

class _NameDialog extends ConsumerStatefulWidget {
  const _NameDialog({required this.current});
  final String? current;

  @override
  ConsumerState<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends ConsumerState<_NameDialog> {
  late final _name = TextEditingController(text: widget.current ?? '')
    ..selection = TextSelection(baseOffset: 0, extentOffset: (widget.current ?? '').length);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final r = validateSpaceName(_name.text);
    if (r.error != null) return setState(() => _error = r.error);
    await ref.read(databaseProvider).setSpaceName(r.value); // vacío → null → "Mis cuentas"
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      title: const Text('Nombre del espacio'),
      content: TextField(
        key: const Key('name.field'),
        controller: _name,
        autofocus: true,
        style: AppType.body.copyWith(color: p.ink),
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        inputFormatters: [FilteringTextInputFormatter.deny(emojiRegex)],
        decoration: InputDecoration(hintText: 'Mis cuentas', errorText: _error),
        onChanged: (v) {
          final e = validateSpaceName(v).error;
          if (e != _error) setState(() => _error = e);
        },
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: p.inkMuted),
          child: const Text('Cancelar'),
        ),
        TextButton(key: const Key('name.save'), onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}

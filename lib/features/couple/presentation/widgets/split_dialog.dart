import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/utils/formatters.dart';
import 'package:saldo_claro/features/dashboard/providers/repository_providers.dart';

/// Diálogo para dividir un gasto (Split):
/// marca un porcentaje (p. ej. 50%) como "cuenta por cobrar" a la pareja.
Future<bool?> showSplitDialog(
  BuildContext context,
  WidgetRef ref,
  Transaction transaction,
) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _SplitDialog(transaction: transaction),
  );
}

class _SplitDialog extends ConsumerStatefulWidget {
  const _SplitDialog({required this.transaction});

  final Transaction transaction;

  @override
  ConsumerState<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends ConsumerState<_SplitDialog> {
  final _debtorController = TextEditingController(text: 'Mi pareja');
  double _pct = 0.5;
  bool _saving = false;

  double get _amount => widget.transaction.amount * _pct;

  @override
  void dispose() {
    _debtorController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _debtorController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(splitRepositoryProvider).create(
            transactionId: widget.transaction.id,
            debtorName: name,
            amount: _amount,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al dividir: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dividir este gasto 💛'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.transaction.merchantOrPerson ?? 'Movimiento'} · '
            '${Formatters.currency(widget.transaction.amount)}',
            style: const TextStyle(
              color: Color(ColorConfig.textSecondary),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          const Text('¿Qué porcentaje le cobras a tu pareja?'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final pct in const [0.5, 0.25, 1.0])
                ChoiceChip(
                  label: Text(
                    pct == 1.0
                        ? 'Todo (100%)'
                        : '${(pct * 100).toStringAsFixed(0)}%',
                  ),
                  selected: _pct == pct,
                  onSelected: (_) => setState(() => _pct = pct),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _debtorController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: '¿Quién debe?'),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Cuenta por cobrar',
                  style: TextStyle(color: Color(ColorConfig.textSecondary))),
              Text(
                Formatters.currency(_amount),
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(ColorConfig.success),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Crear cuenta por cobrar'),
        ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saldo_claro/features/dashboard/providers/dashboard_providers.dart';
import 'package:saldo_claro/features/dashboard/providers/repository_providers.dart';

/// Diálogo para editar el presupuesto mensual global del usuario.
Future<void> showBudgetDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(monthlyBudgetProvider).value;
  final controller = TextEditingController(
    text: current != null ? current.toStringAsFixed(0) : '',
  );

  final value = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Presupuesto mensual'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Presupuesto del mes',
          prefixText: 'S/ ',
          hintText: 'Ej: 1200',
          helperText:
              'Úsalo para la alerta de ritmo de gasto (70% antes de mitad de mes).',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, null),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            ctx,
            double.tryParse(controller.text.replaceAll(',', '.')),
          ),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );

  if (value == null || !context.mounted) return;
  await ref.read(settingsRepositoryProvider).setMonthlyBudget(
        value > 0 ? value : null,
      );
  ref.invalidate(monthlyBudgetProvider);
  ref.invalidate(insightsProvider);
}
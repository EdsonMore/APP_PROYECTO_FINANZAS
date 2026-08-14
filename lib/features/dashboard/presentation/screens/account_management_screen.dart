import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/models/account.dart';
import 'package:saldo_claro/core/utils/formatters.dart';
import 'package:saldo_claro/features/dashboard/providers/dashboard_providers.dart';
import 'package:saldo_claro/features/dashboard/providers/repository_providers.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/account_editor_panel.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/icon_catalog.dart';
import 'package:saldo_claro/core/security/security_providers.dart';

/// Pantalla de Gestión de Cuentas (añadir, editar, eliminar).
class AccountManagementScreen extends ConsumerStatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  ConsumerState<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends ConsumerState<AccountManagementScreen> {
  Future<void> _openEditor({Account? account}) async {
    final result = await showModalBottomSheet<AccountEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(ColorConfig.surface),
      builder: (_) => AccountEditorPanel(existing: account),
    );
    if (result == null) return;
    refreshDashboard(ref);

    // Tarea 1: si se creó una cuenta con saldo 0.00, un modal de bienvenida
    // invita a ingresar el saldo actual para empezar con precisión.
    if (result.isNew &&
        result.accountId != null &&
        result.balance <= 0) {
      await _promptInitialBalance(
        result.accountId!,
        result.accountName,
      );
      refreshDashboard(ref);
    }
  }

  /// Modal de bienvenida para fijar el saldo inicial cuando quedó en 0.00.
  Future<void> _promptInitialBalance(String accountId, String accountName) async {
    final controller = TextEditingController();
    final entered = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¡Bienvenido a SaldoClaro! 👋'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Para empezar con precisión, ingresa tu saldo actual de ',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 4),
            Text(
              accountName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(ColorConfig.accent),
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Saldo actual',
                prefixText: 'S/ ',
                hintText: 'Ej: 120.50',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );
              Navigator.pop(ctx, value != null && value > 0 ? value : -1);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (entered == null || !mounted) return;

    if (entered < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un monto válido.')),
      );
      return;
    }

    if (entered == 0) return; // "Ahora no": el usuario lo dejó para después.

    try {
      await ref
          .read(accountRepositoryProvider)
          .registerInitialBalance(accountId: accountId, amount: entered);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Saldo inicial de S/ ${Formatters.currency(entered)} '
              'registrado en $accountName',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _delete(Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar cuenta?'),
        content: Text(
          'Se eliminará "${account.name}" y todos sus movimientos asociados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(accountRepositoryProvider).delete(account.id);
      refreshDashboard(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final isHidden = ref.watch(balanceHiddenProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de Cuentas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva cuenta'),
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (accounts) {
          if (accounts.isEmpty) {
            return const Center(
              child: Text(
                'Aún no tienes cuentas.\nToca el botón para agregar una.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: accounts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final account = accounts[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(account.resolvedColor),
                        child: Icon(
                          IconCatalog.iconFor(account.resolvedIcon),
                          color: Colors.white,
                        ),
                      ),
                      title: Text(account.name),
                      subtitle: Text(
                        '${account.bank ?? ''} · ${isHidden ? 'S/ ****' : Formatters.currency(account.balance)}'
                            .trim(),
                      ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openEditor(account: account),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Color(ColorConfig.danger)),
                        onPressed: () => _delete(account),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

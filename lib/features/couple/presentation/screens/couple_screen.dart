import 'package:flutter/material.dart' hide Split;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/models/couple.dart';
import 'package:saldo_claro/core/models/split.dart';
import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/utils/formatters.dart';
import 'package:saldo_claro/features/couple/providers/couple_providers.dart';
import 'package:saldo_claro/features/couple/presentation/widgets/split_dialog.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/icon_catalog.dart';
import 'package:saldo_claro/features/dashboard/providers/dashboard_providers.dart';
import 'package:saldo_claro/features/dashboard/providers/repository_providers.dart';

/// Pantalla dedicada "Especial Pareja 💖": métricas en tiempo real,
/// presupuesto vs gasto, historial filtrado y división de gastos.
class CoupleScreen extends ConsumerStatefulWidget {
  const CoupleScreen({super.key});

  @override
  ConsumerState<CoupleScreen> createState() => _CoupleScreenState();
}

class _CoupleScreenState extends ConsumerState<CoupleScreen> {
  Future<void> _split(Transaction tx) async {
    final ok = await showSplitDialog(context, ref, tx);
    if (ok == true) refreshCouple(ref);
  }

  Future<void> _setPaid(Split split, bool value) async {
    await ref.read(splitRepositoryProvider).setPaid(split.id, value);
    refreshCouple(ref);
  }

  Future<void> _deleteSplit(Split split) async {
    await ref.read(splitRepositoryProvider).delete(split.id);
    refreshCouple(ref);
  }

  Future<void> _editBudget(CoupleStats stats) async {
    final controller = TextEditingController(
      text: stats.budget?.toStringAsFixed(0) ?? '',
    );
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Presupuesto mensual de pareja'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Presupuesto',
            prefixText: 'S/ ',
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
    if (value == null || !mounted) return;
    final category = (ref.read(allCategoriesProvider).value ?? const [])
        .firstWhere((c) => c.name == stats.categoryName);
    final updated = category.copyWith(
      budget: value > 0 ? value : null,
    );
    await ref.read(categoryRepositoryProvider).update(updated);
    refreshDashboard(ref);
    refreshCouple(ref);
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(coupleStatsProvider);
    final splitsAsync = ref.watch(splitsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Especial Pareja 💖'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Presupuesto mensual',
            onPressed: () {
              final stats = statsAsync.value;
              if (stats != null && stats.categoryName.isNotEmpty) {
                _editBudget(stats);
              }
            },
          ),
        ],
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (stats) {
          if (stats.categoryName.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Crea o edita la categoría "Enamorada / Pareja" en '
                  '"Gestión de Categorías" para activar este módulo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(ColorConfig.textSecondary)),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(stats: stats, onEditBudget: () => _editBudget(stats)),
              const SizedBox(height: 16),
              if (stats.breakdown.isNotEmpty) ...[
                Text(
                  'Desglose del mes',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(ColorConfig.textPrimary),
                  ),
                ),
                const SizedBox(height: 8),
                _Breakdown(breakdown: stats.breakdown),
                const SizedBox(height: 16),
              ],
              if (stats.pendingSplits > 0) ...[
                const Text(
                  'Cuentas por cobrar pendientes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(ColorConfig.textPrimary),
                  ),
                ),
                const SizedBox(height: 8),
                splitsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (splits) {
                    final pending =
                        splits.where((s) => !s.isPaid).toList();
                    return Column(
                      children: [
                        for (final s in pending)
                          _PendingSplitTile(
                            split: s,
                            onPaid: (v) => _setPaid(s, v),
                            onDelete: () => _deleteSplit(s),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
              Text(
                'Movimientos de ${stats.categoryName}',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(ColorConfig.textPrimary),
                ),
              ),
              const SizedBox(height: 8),
              if (stats.transactions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Aún no hay gastos de pareja este mes.',
                      style: TextStyle(color: Color(ColorConfig.textSecondary)),
                    ),
                  ),
                )
              else
                for (final tx in stats.transactions)
                  _CoupleTransactionCard(
                    transaction: tx,
                    onSplit: () => _split(tx),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.stats, required this.onEditBudget});

  final CoupleStats stats;
  final VoidCallback onEditBudget;

  @override
  Widget build(BuildContext context) {
    final progress = stats.budget != null && stats.budget! > 0
        ? (stats.monthTotal / stats.budget!).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE91E63), Color(0xFFC2185B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gasto en ${stats.categoryName} este mes',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.tune, color: Colors.white, size: 20),
                tooltip: 'Presupuesto',
                onPressed: onEditBudget,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            Formatters.currency(stats.monthTotal),
            style: GoogleFonts.inter(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            '${stats.monthCount} movimiento(s)',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (stats.budget != null && stats.budget! > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Presupuesto: ${Formatters.currency(stats.budget!)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '${stats.budgetProgress}% usado',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ] else
            const SizedBox(height: 8),
          if (stats.pendingSplits > 0) ...[
            const SizedBox(height: 8),
            Text(
              '💰 Por cobrar: ${Formatters.currency(stats.pendingSplits)}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.breakdown});

  final Map<CoupleSubcategory, double> breakdown;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in breakdown.entries)
          if (entry.value > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE91E63).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFE91E63).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    IconCatalog.iconFor(entry.key.icon),
                    size: 16,
                    color: const Color(0xFFE91E63),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${entry.key.label}: ${Formatters.compact(entry.value)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _CoupleTransactionCard extends StatelessWidget {
  const _CoupleTransactionCard({
    required this.transaction,
    required this.onSplit,
  });

  final Transaction transaction;
  final VoidCallback onSplit;

  @override
  Widget build(BuildContext context) {
    final sub = CoupleSubcategory.classify(transaction);
    final color = Color(transaction.isIncome
        ? ColorConfig.success
        : ColorConfig.danger);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE91E63).withValues(alpha: 0.15),
          child: Icon(
            IconCatalog.iconFor(sub.icon),
            color: const Color(0xFFE91E63),
          ),
        ),
        title: Text(transaction.merchantOrPerson ?? 'Movimiento'),
        subtitle: Text(
          '${sub.label} · ${transaction.sourceApp} · '
          '${Formatters.date(transaction.createdAt)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.call_split, color: Color(0xFFF39C12)),
              tooltip: 'Dividir gasto',
              onPressed: onSplit,
            ),
            Text(
              Formatters.currencySigned(
                transaction.isIncome
                    ? transaction.amount
                    : -transaction.amount,
              ),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingSplitTile extends StatelessWidget {
  const _PendingSplitTile({
    required this.split,
    required this.onPaid,
    required this.onDelete,
  });

  final Split split;
  final ValueChanged<bool> onPaid;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFF39C12).withValues(alpha: 0.08),
      child: ListTile(
        leading: const Icon(Icons.payments_outlined,
            color: Color(0xFFF39C12)),
        title: Text('${split.debtorName} te debe'),
        subtitle: Text(
          '${Formatters.currency(split.amount)} · '
          '${Formatters.date(split.createdAt ?? DateTime.now())}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check_circle_outline,
                  color: Color(ColorConfig.success)),
              tooltip: 'Marcar pagado',
              onPressed: () => onPaid(true),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Color(ColorConfig.danger)),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
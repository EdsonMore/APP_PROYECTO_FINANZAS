import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/utils/formatters.dart';
import 'package:saldo_claro/features/billing_cycles/models/billing_cycle_model.dart';
import 'package:saldo_claro/features/billing_cycles/providers/billing_cycles_provider.dart';
import 'package:saldo_claro/features/billing_cycles/views/billing_cycles_screen.dart';

/// Widget destacado del Dashboard: alerta de servicios próximos a vencer.
///
/// Muestra un carrusel horizontal con los ciclos activos pendientes que
/// vencen en los próximos 5 días (o ya vencidos) con contador regresivo.
class DashboardUpcomingBillsWidget extends ConsumerWidget {
  const DashboardUpcomingBillsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cyclesAsync = ref.watch(billingCyclesProvider);
    final cycles = cyclesAsync.value ?? const <BillingCycle>[];

    final upcoming = _upcoming(cycles);
    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Próximos vencimientos',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(ColorConfig.textPrimary),
              ),
            ),
            TextButton(
              onPressed: () => _openBillingCycles(context),
              child: const Text('Ver todos'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: upcoming.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) =>
                _UpcomingBillCard(cycle: upcoming[index]),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Ciclos activos no pagados que vencen en ≤5 días o ya vencidos.
  List<BillingCycle> _upcoming(List<BillingCycle> cycles) {
    final list = cycles
        .where((c) => c.isActive && c.status != BillingStatus.paid)
        .where((c) => c.daysUntilDue <= 5)
        .toList()
      ..sort((a, b) {
        // Primero los vencidos, luego por cercanía de fecha.
        final aOverdue = a.daysUntilDue < 0 ? 0 : 1;
        final bOverdue = b.daysUntilDue < 0 ? 0 : 1;
        if (aOverdue != bOverdue) return aOverdue.compareTo(bOverdue);
        return a.daysUntilDue.compareTo(b.daysUntilDue);
      });
    return list.take(6).toList();
  }

  void _openBillingCycles(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BillingCyclesScreen()),
    );
  }
}

class _UpcomingBillCard extends StatelessWidget {
  const _UpcomingBillCard({required this.cycle});

  final BillingCycle cycle;

  @override
  Widget build(BuildContext context) {
    final days = cycle.daysUntilDue;
    final overdue = days < 0;
    final isUrgent = overdue || days <= 1;

    final (color, title, message) = overdue
        ? (
            const Color(ColorConfig.danger),
            '🚨 Vencido hace ${-days} día${-days == 1 ? '' : 's'}',
            'Paga ${cycle.title} hoy',
          )
        : days == 0
            ? (
                const Color(ColorConfig.danger),
                '🚨 ¡Vence hoy!',
                'Paga ${cycle.title} hoy',
              )
            : days == 1
                ? (
                    const Color(ColorConfig.danger),
                    '🚨 Te queda 1 día',
                    'Paga ${cycle.title}',
                  )
                : (
                    const Color(0xFFF39C12),
                    '🚨 Te quedan $days días',
                    'Paga ${cycle.title}',
                  );

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BillingCyclesScreen()),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUrgent
              ? color.withValues(alpha: 0.14)
              : const Color(ColorConfig.surface),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Text(cycle.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cycle.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(ColorConfig.textPrimary),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$message (${Formatters.currency(cycle.amount)})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Vence el ${Formatters.date(cycle.dueDate)}',
              style: const TextStyle(
                fontSize: 11,
                color: Color(ColorConfig.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

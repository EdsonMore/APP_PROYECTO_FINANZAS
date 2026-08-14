import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/models/couple.dart';
import 'package:saldo_claro/core/utils/formatters.dart';
import 'package:saldo_claro/features/couple/presentation/screens/couple_screen.dart';
import 'package:saldo_claro/features/couple/providers/couple_providers.dart';

/// Widget VIP "Especial Pareja 💖" destacado en el Dashboard.
class CoupleDashboardCard extends ConsumerWidget {
  const CoupleDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(coupleStatsProvider);

    return statsAsync.when(
      loading: () => const _CardSkeleton(),
      error: (e, _) => const SizedBox.shrink(),
      data: (stats) {
        if (stats.categoryName.isEmpty) return const SizedBox.shrink();
        return _buildCard(context, ref, stats);
      },
    );
  }

  Widget _buildCard(BuildContext context, WidgetRef ref, CoupleStats stats) {
    final progress =
        stats.budget != null && stats.budget! > 0
            ? (stats.monthTotal / stats.budget!).clamp(0.0, 1.0).toDouble()
            : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE91E63), Color(0xFFC2185B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text(
                'Especial Pareja 💖',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            Formatters.currency(stats.monthTotal),
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'gastado este mes en ${stats.categoryName} (${stats.monthCount} mov.)',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (stats.budget != null && stats.budget! > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${stats.budgetProgress}% del presupuesto de '
              '${Formatters.currency(stats.budget!)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          if (stats.pendingSplits > 0) ...[
            const SizedBox(height: 8),
            Text(
              '💰 Tienes ${Formatters.currency(stats.pendingSplits)} de cuentas '
              'por cobrar pendientes',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CoupleScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
              label: const Text(
                'Ver módulo completo',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 170,
      decoration: BoxDecoration(
        color: pink.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

const pink = Color(0xFFE91E63);
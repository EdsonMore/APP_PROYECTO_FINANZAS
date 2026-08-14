import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/models/transaction.dart';
import '../../../../core/security/security_providers.dart';
import '../../../../core/utils/formatters.dart';

/// Fila de una transacción reciente con badge de origen.
///
/// Respeta el modo incógnito: si `isBalanceHidden`, el monto se muestra como
/// "S/ **.**".
class TransactionTile extends ConsumerWidget {
  const TransactionTile({super.key, required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHidden = ref.watch(balanceHiddenProvider);
    final isIncome = transaction.isIncome;
    final arrow = isIncome
        ? Icons.south_west
        : Icons.north_east;
    final color = Color(isIncome ? ColorConfig.success : ColorConfig.danger);

    final amountLabel = isHidden
        ? 'S/ **.**'
        : Formatters.currencySigned(
            isIncome ? transaction.amount : -transaction.amount,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.14),
            child: Icon(arrow, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.merchantOrPerson ?? 'Movimiento',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(ColorConfig.textPrimary),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${transaction.sourceApp} · ${Formatters.date(transaction.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(ColorConfig.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _SourceBadge(source: transaction.source),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amountLabel,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final TransactionSource source;

  @override
  Widget build(BuildContext context) {
    final isAuto = source == TransactionSource.auto;
    final background = isAuto
        ? const Color(0xFF00A859).withValues(alpha: 0.16)
        : const Color(0xFF9AA3B2).withValues(alpha: 0.16);
    final foreground =
        isAuto ? const Color(0xFF00A859) : const Color(0xFF9AA3B2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        source.badge,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
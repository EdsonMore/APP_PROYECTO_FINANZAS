import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/account.dart';
import '../../../../core/security/security_providers.dart';
import '../../../../core/utils/formatters.dart';

/// Tarjeta individual de una cuenta financiera.
///
/// Respeta el modo incógnito: si `isBalanceHidden`, el saldo se muestra como
/// "S/ ****".
class AccountCard extends ConsumerWidget {
  const AccountCard({
    super.key,
    required this.account,
    this.onTap,
  });

  final Account account;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHidden = ref.watch(balanceHiddenProvider);
    final color = Color(account.resolvedColor);
    final initial = account.name.isNotEmpty ? account.name[0] : '?';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    account.name,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFF5F7FA),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              isHidden ? 'S/ ****' : Formatters.currency(account.balance),
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFF5F7FA),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
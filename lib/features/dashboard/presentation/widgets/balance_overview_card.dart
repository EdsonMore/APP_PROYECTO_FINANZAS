import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/account.dart';
import '../../../../core/security/security_providers.dart';
import '../../../../core/utils/formatters.dart';

/// Tarjeta de balance total (suma de todas las cuentas).
///
/// Incluye el botón de modo incógnito (ojo): si `isBalanceHidden` está activo,
/// el total se muestra enmascarado y la preferencia se persiste en disco.
class BalanceOverviewCard extends ConsumerWidget {
  const BalanceOverviewCard({super.key, required this.accounts});

  final List<Account> accounts;

  double get totalBalance =>
      accounts.fold(0, (sum, a) => sum + a.balance);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHidden = ref.watch(balanceHiddenProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B1FA2), Color(0xFF002A8F)],
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
              const Icon(Icons.account_balance_wallet, color: Colors.white70),
              const SizedBox(width: 8),
              const Text(
                'Saldo total',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => ref
                    .read(balanceHiddenProvider.notifier)
                    .setHidden(!isHidden),
                tooltip: isHidden
                    ? 'Mostrar saldos'
                    : 'Ocultar saldos (modo incógnito)',
                icon: Icon(
                  isHidden ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white70,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isHidden ? 'S/ ****' : Formatters.currency(totalBalance),
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Actualizado automáticamente con cada movimiento capturado',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
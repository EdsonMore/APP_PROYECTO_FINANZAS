import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/models/account.dart';
import '../screens/account_management_screen.dart';

/// Banner de bienvenida: aparece la primera vez (cuentas en 0.00 y sin
/// movimientos) invitando a ingresar el saldo actual para empezar con precisión.
///
/// Muestra los nombres de las cuentas que aún están en S/ 0.00.
class InitialBalanceBanner extends ConsumerWidget {
  const InitialBalanceBanner({
    super.key,
    required this.accounts,
    required this.hasTransactions,
  });

  final List<Account> accounts;
  final bool hasTransactions;

  bool get _shouldShow =>
      accounts.isNotEmpty &&
      accounts.every((a) => a.balance <= 0) &&
      !hasTransactions;

  String get _accountNames {
    final names = accounts.map((a) => a.name).toList();
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} y ${names[1]}';
    return '${names.take(2).join(', ')} y más';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_shouldShow) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B4332), Color(0xFF0F1115)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(ColorConfig.accent).withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(ColorConfig.accent).withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emoji_emotions_outlined,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Empieza con precisión',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(ColorConfig.textPrimary),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Para empezar con precisión, ingresa tu saldo actual de '
                  '$_accountNames.',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Color(ColorConfig.textSecondary),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AccountManagementScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.savings_outlined, size: 17),
                    label: const Text('Configurar saldo inicial'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(ColorConfig.textPrimary),
                      side: const BorderSide(
                          color: Color(ColorConfig.textSecondary)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
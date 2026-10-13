import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/icon_catalog.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../home/providers.dart';
import '../settings/settings_screen.dart' show SubpageHeader;
import 'account_editor.dart';
import 'providers.dart';
import 'transfer_sheet.dart';

/// Ajustes → Cuentas (4A): activas con su saldo, archivadas aparte. Se puede
/// quedar sin cuentas activas (a diferencia de categorías y fuentes).
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final data = ref.watch(accountsDataProvider);
    final entries = ref.watch(entriesStreamProvider).value;
    final settings = ref.watch(settingsProvider).value;
    final today = ref.watch(todayProvider);
    if (data == null || entries == null) return const Scaffold(body: SizedBox());
    final balances = balancesByAccount(
      entries: entries,
      accounts: data.accounts,
      transfers: data.transfers,
      unassignedOpening: settings?.opening,
      today: today,
    );
    final active = [for (final a in data.accounts) if (!a.archived) a];
    final archived = [for (final a in data.accounts) if (a.archived) a];

    Widget row(Account a, {bool muted = false}) => AccountRow(
          key: Key('accounts.${a.id}'),
          icon: a.icon,
          name: a.name,
          balance: balances[a.id] ?? 0,
          muted: muted,
          onTap: () => showAccountEditor(context, all: data.accounts, existing: a),
        );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const Key('accounts.scroll'),
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
          children: [
            const SubpageHeader(title: 'Cuentas'),
            const SizedBox(height: Space.lg),
            for (final a in active) row(a),
            const SizedBox(height: Space.md),
            OutlinedButton(
              key: const Key('accounts.add'),
              onPressed: () => showAccountEditor(context, all: data.accounts),
              child: const Text('Nueva cuenta'),
            ),
            if (data.accounts.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              OutlinedButton(
                key: const Key('accounts.transfer'),
                onPressed: () => showTransferSheet(context),
                child: const Text('Transferir entre cuentas'),
              ),
            ],
            if (archived.isNotEmpty) ...[
              Divider(color: p.border, height: Space.xxl),
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Semantics(
                  header: true,
                  child: Text('Archivadas', style: AppType.heading.copyWith(color: p.ink)),
                ),
              ),
              for (final a in archived) row(a, muted: true),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ícono, nombre y saldo (negativo en expenseFg). La usan Cuentas y el Home.
class AccountRow extends StatelessWidget {
  const AccountRow({
    super.key,
    required this.icon,
    required this.name,
    required this.balance,
    this.onTap,
    this.muted = false,
  });
  final String icon;
  final String name;
  final int balance;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final amount = balance < 0 ? '−${Formatters.soles(-balance)}' : Formatters.soles(balance);
    return Semantics(
      button: onTap != null,
      label: '$name, saldo $amount',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.button),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              Icon(IconCatalog.iconFor(icon), size: 20, color: p.inkMuted),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label.copyWith(color: muted ? p.inkMuted : p.ink),
                ),
              ),
              Text(amount, style: AppType.amount.copyWith(color: balance < 0 ? p.expenseFg : p.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

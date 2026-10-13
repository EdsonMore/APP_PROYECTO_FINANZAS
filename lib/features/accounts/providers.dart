import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';

/// Multi-cuenta (Fase 4A).

final accountsStreamProvider = StreamProvider<List<Account>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.accounts)..orderBy([(a) => OrderingTerm(expression: a.sortOrder)])).watch();
});

final transfersStreamProvider = StreamProvider<List<TransferRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.transfers).watch();
});

/// La cuenta de los movimientos sin cuenta (account_id NULL). No es una fila.
const unassignedName = 'Sin asignar';

/// Transferencias y saldos iniciales por cuenta, para el saldo global (R1).
AccountBook accountBookOf(List<Account> accounts, List<TransferRow> transfers) => AccountBook(
      transfers: [for (final t in transfers) t.toTransfer()],
      openings: {
        for (final a in accounts) a.id: ?a.opening,
      },
    );

/// Saldo de cada cuenta (archivadas incluidas) y de "Sin asignar" (clave null).
Map<String?, int> balancesByAccount({
  required List<Entry> entries,
  required List<Account> accounts,
  required List<TransferRow> transfers,
  required Opening? unassignedOpening,
  required DateTime today,
}) {
  final movements = [for (final e in entries) e.toMovement()];
  final ts = [for (final t in transfers) t.toTransfer()];
  return {
    for (final a in accounts) a.id: accountBalance(a.id, movements, ts, today: today, opening: a.opening),
    null: accountBalance(null, movements, ts, today: today, opening: unassignedOpening),
  };
}

/// "Sin asignar" se muestra (Home, Insights) solo si tiene saldo o algo que
/// le pertenezca: un movimiento sin cuenta o una transferencia desde/hacia ahí.
bool showUnassigned(int balance, List<Entry> entries, List<TransferRow> transfers) =>
    balance != 0 ||
    entries.any((e) => e.accountId == null) ||
    transfers.any((t) => t.fromAccountId == null || t.toAccountId == null);

/// Todo lo de cuentas junto, ya cargado (null mientras algún stream carga).
final accountsDataProvider = Provider<({List<Account> accounts, List<TransferRow> transfers})?>((ref) {
  final accounts = ref.watch(accountsStreamProvider).value;
  final transfers = ref.watch(transfersStreamProvider).value;
  return accounts == null || transfers == null ? null : (accounts: accounts, transfers: transfers);
});

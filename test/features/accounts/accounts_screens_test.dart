import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/core/theme/app_theme.dart';
import 'package:saldo_claro/core/theme/tokens.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/accounts/accounts_screen.dart';
import 'package:saldo_claro/features/entry/draft_store.dart';
import 'package:saldo_claro/features/history/history_screen.dart';
import 'package:saldo_claro/features/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import '../home/home_screen_test.dart' as h;

Finder key(String k) => find.byKey(Key(k));

Future<void> tap(WidgetTester tester, String k) async {
  await tester.ensureVisible(key(k));
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(key('key.$d'));
    await tester.pump();
  }
}

/// Yape (saldo inicial S/ 500 el 1 oct) y Efectivo; un gasto de S/ 20 en
/// Yape y otro de S/ 5 sin cuenta.
Future<void> twoAccounts(h.Seed s) async {
  await s.db.insertAccount(id: 'yape', name: 'Yape', icon: 'phone_android');
  await s.db.setAccountOpening('yape', cents: 50000, at: DateTime(2026, 10, 1, 9));
  await s.db.insertAccount(id: 'efectivo', name: 'Efectivo', icon: 'payments');
  await s.db.insertManualEntry(
      id: 'g1', kind: EntryKind.expense, amountCents: 2000, day: h.ago(1), pickId: 'comida',
      now: DateTime(2026, 10, 7, 12), accountId: 'yape');
  await s.db.insertManualEntry(
      id: 'g2', kind: EntryKind.expense, amountCents: 500, day: h.ago(2), pickId: 'comida', now: DateTime(2026, 10, 6, 12));
}

Future<h.Seed> home(WidgetTester tester, [Future<void> Function(h.Seed)? fill, Size size = const Size(411, 914)]) async {
  final seed = await h.seeded(Mode.variable, fill);
  await h.pumpHome(tester, seed, size: size);
  return seed;
}

Future<void> openAccounts(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ajustes'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(key('settings.accounts'), 200, scrollable: find.byType(Scrollable).last);
  await tester.tap(key('settings.accounts'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  group('Ajustes → Cuentas', () {
    testWidgets('sin cuentas: "Sin cuentas"; crear una con saldo inicial; sin Transferir hasta tener cuentas', (tester) async {
      final seed = await home(tester);
      await openAccounts(tester);
      expect(find.byType(AccountsScreen), findsOneWidget);
      expect(key('accounts.transfer'), findsNothing);

      await tap(tester, 'accounts.add');
      await tester.enterText(key('account.name'), 'Yape');
      await tester.pump();
      await tap(tester, 'account.opening');
      expect(find.text('Saldo inicial de Yape'), findsOneWidget);
      await type(tester, '500');
      await tap(tester, 'opening.save');
      expect(find.descendant(of: key('account.opening'), matching: find.text('S/ 500.00')), findsOneWidget);
      await tap(tester, 'account.save');

      final a = await seed.db.select(seed.db.accounts).getSingle();
      expect((a.name, a.openingBalanceCents), ('Yape', 50000));
      expect(find.text('S/ 500.00'), findsOneWidget, reason: 'la fila muestra su saldo');
      expect(key('accounts.transfer'), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('nombre repetido (sin distinguir mayúsculas) da error', (tester) async {
      await home(tester, twoAccounts);
      await openAccounts(tester);
      await tap(tester, 'accounts.add');
      await tester.enterText(key('account.name'), 'yape');
      await tester.pump();
      await tap(tester, 'account.save');
      expect(find.text('Ya existe una con ese nombre.'), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('archivar la manda a "Archivadas" con su saldo; desarchivar la devuelve', (tester) async {
      final seed = await home(tester, twoAccounts);
      await openAccounts(tester);
      await tap(tester, 'accounts.yape');
      await tap(tester, 'account.archive');
      expect(find.text('Archivadas'), findsOneWidget);
      expect((await (seed.db.select(seed.db.accounts)..where((a) => a.id.equals('yape'))).getSingle()).archived, isTrue);
      await tap(tester, 'accounts.yape');
      expect(find.text('Desarchivar'), findsOneWidget);
      await tap(tester, 'account.archive');
      expect(find.text('Archivadas'), findsNothing);
      await h.unmount(tester);
    });
  });

  group('registro con cuenta', () {
    testWidgets('sin cuentas no hay chip', (tester) async {
      await home(tester);
      await tester.tap(key('home.cta.expense'));
      await tester.pumpAndSettle();
      expect(key('entry.account'), findsNothing);
      await h.unmount(tester);
    });

    testWidgets('con cuentas: por defecto la última usada; cambiarla y guardar', (tester) async {
      final seed = await home(tester, twoAccounts);
      await tester.tap(key('home.cta.expense'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: key('entry.account'), matching: find.text('Yape')), findsOneWidget,
          reason: 'el último gasto fue en Yape');
      await tap(tester, 'entry.account');
      await tap(tester, 'entry.account.efectivo');
      await type(tester, '7');
      await tap(tester, 'entry.save');
      final e = await (seed.db.select(seed.db.entries)..where((e) => e.amountCents.equals(700))).getSingle();
      expect(e.accountId, 'efectivo');
      await h.unmount(tester);
    });

    testWidgets('el borrador recuerda la cuenta elegida, también "Sin asignar"', (tester) async {
      await home(tester, twoAccounts);
      await tester.tap(key('home.cta.expense'));
      await tester.pumpAndSettle();
      await tap(tester, 'entry.account');
      await tap(tester, 'entry.account.unassigned');
      await type(tester, '3');
      await tap(tester, 'entry.close');
      final store = ProviderScope.containerOf(tester.element(find.byType(HomeScreen))).read(draftStoreProvider);
      expect(store.load(EntryKind.expense)?.account, '');
      await tester.tap(key('home.cta.expense'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: key('entry.account'), matching: find.text('Sin asignar')), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('editar un movimiento de una cuenta archivada la muestra marcada', (tester) async {
      await home(tester, (s) async {
        await twoAccounts(s);
        await s.db.setAccountArchived('yape', archived: true);
      });
      final row = find.byKey(const ValueKey('g1')); // la fila de Recientes del gasto en Yape
      await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(row); // si no, queda bajo los botones Gasto/Ingreso
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.descendant(of: key('entry.account'), matching: find.text('Yape (archivada)')), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('R3: 320 dp sin desbordes con un nombre largo; 640 dp de alto sin scroll', (tester) async {
      await home(tester, (s) async {
        await s.db.insertAccount(id: 'larga', name: 'Cuenta de ahorros', icon: 'savings');
        await s.db.insertManualEntry(
            id: 'x', kind: EntryKind.expense, amountCents: 1, day: h.ago(1), pickId: 'comida',
            now: DateTime(2026, 10, 7), accountId: 'larga');
      }, const Size(320, 640));
      await tester.tap(key('home.cta.expense'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(key('entry.account'), findsOneWidget);
      expect(key('entry.close'), findsOneWidget);
      final scroll = tester.state<ScrollableState>(
          find.descendant(of: key('entry.scroll'), matching: find.byType(Scrollable)));
      expect(scroll.position.maxScrollExtent, 0, reason: 'cabe sin scroll');
      await h.unmount(tester);
    });
  });

  group('Transferir', () {
    Future<void> openTransfer(WidgetTester tester) async {
      await openAccounts(tester);
      await tap(tester, 'accounts.transfer');
    }

    testWidgets('misma cuenta en los dos lados: aviso y botón deshabilitado; monto 0 avisa', (tester) async {
      await home(tester, twoAccounts);
      await openTransfer(tester);
      await tap(tester, 'transfer.to.yape');
      expect(find.text('Elige dos cuentas distintas.'), findsOneWidget);
      expect(tester.widget<FilledButton>(key('transfer.save')).onPressed, isNull);
      await tap(tester, 'transfer.to.efectivo');
      await tap(tester, 'transfer.save');
      expect(find.text('Ingresa un monto mayor a S/ 0'), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('desde "Sin asignar": se guarda, avisa y mueve los saldos', (tester) async {
      final seed = await home(tester, twoAccounts);
      await openTransfer(tester);
      await tap(tester, 'transfer.from.unassigned');
      await tap(tester, 'transfer.to.efectivo');
      await type(tester, '30');
      await tap(tester, 'transfer.save');
      expect(find.text('Transferencia guardada'), findsOneWidget);
      final t = await seed.db.select(seed.db.transfers).getSingle();
      expect((t.fromAccountId, t.toAccountId, t.amountCents), (null, 'efectivo', 3000));
      expect(find.descendant(of: key('accounts.efectivo'), matching: find.text('S/ 30.00')), findsOneWidget);
      await h.unmount(tester);
    });
  });

  group('Home', () {
    testWidgets('sin cuentas no hay bloque', (tester) async {
      await home(tester, (s) => s.expense(5, h.ago(1)));
      expect(key('home.accounts'), findsNothing);
      await h.unmount(tester);
    });

    testWidgets('saldos por cuenta; negativo en rojo; "Sin asignar" con sus movimientos', (tester) async {
      await home(tester, (s) async {
        await twoAccounts(s);
        await s.db.insertManualEntry(
            id: 'g3', kind: EntryKind.expense, amountCents: 900, day: h.ago(1), pickId: 'comida',
            now: DateTime(2026, 10, 7, 13), accountId: 'efectivo');
      });
      await tester.scrollUntilVisible(key('home.accounts'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.descendant(of: key('home.account.yape'), matching: find.text('S/ 480.00')), findsOneWidget);
      final neg = tester.widget<Text>(find.descendant(of: key('home.account.efectivo'), matching: find.text('−S/ 9.00')));
      expect(neg.style!.color, AppTheme.light.extension<Palette>()!.expenseFg);
      expect(key('home.account.unassigned'), findsOneWidget, reason: 'el gasto de S/ 5 sin cuenta');
      await h.unmount(tester);
    });

    testWidgets('"Sin asignar" se oculta sin saldo ni movimientos propios', (tester) async {
      await home(tester, (s) async {
        await s.db.insertAccount(id: 'yape', name: 'Yape', icon: 'phone_android');
        await s.db.insertManualEntry(
            id: 'g', kind: EntryKind.expense, amountCents: 100, day: h.ago(1), pickId: 'comida',
            now: DateTime(2026, 10, 7), accountId: 'yape');
      });
      await tester.scrollUntilVisible(key('home.accounts'), 200, scrollable: find.byType(Scrollable).first);
      expect(key('home.account.unassigned'), findsNothing);
      await h.unmount(tester);
    });

    testWidgets('tocar una cuenta abre el Historial filtrado (chip "Yape ✕" y solo lo de Yape)', (tester) async {
      await home(tester, twoAccounts);
      await tester.scrollUntilVisible(key('home.account.yape'), 200, scrollable: find.byType(Scrollable).first);
      await tap(tester, 'home.account.yape');
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.text('Yape ✕'), findsOneWidget);
      expect(key('history.row.g1'), findsOneWidget);
      expect(key('history.row.g2'), findsNothing);
      await tap(tester, 'history.account');
      expect(key('history.row.g2'), findsOneWidget, reason: 'la ✕ quita el filtro');
      await h.unmount(tester);
    });

    testWidgets('R2: con el saldo inicial de una cuenta activa, sin la tarjeta "¿Cuánto tienes hoy?"', (tester) async {
      await home(tester, (s) => s.expense(5, h.ago(1)));
      expect(key('home.openingCard'), findsOneWidget, reason: 'sin ningún saldo inicial');
      await h.unmount(tester);
      await home(tester, twoAccounts);
      expect(key('home.openingCard'), findsNothing);
      await h.unmount(tester);
    });

    testWidgets('R1: el número principal usa el saldo global (incluye el saldo inicial de la cuenta)', (tester) async {
      // Sin saldo inicial global y −S/ 25 en movimientos: sin el saldo de Yape
      // (S/ 500) sería "Sin reserva".
      await home(tester, twoAccounts);
      expect(find.text('Sin reserva'), findsNothing);
      expect(find.textContaining('días'), findsWidgets);
      await h.unmount(tester);
    });
  });

  group('Historial', () {
    Future<void> withTransfer(h.Seed s) async {
      await twoAccounts(s);
      await s.db.insertTransfer(id: 't1', fromAccountId: 'yape', toAccountId: 'efectivo', amountCents: 10000, day: h.ago(0),
          note: 'al bolsillo');
    }

    Future<void> openHistory(WidgetTester tester) async {
      await tester.scrollUntilVisible(key('home.seeAll'), 200, scrollable: find.byType(Scrollable).first);
      await tap(tester, 'home.seeAll');
    }

    testWidgets('la transferencia: "Yape → Efectivo", sin signo; solo con "Todos"; los totales no la suman',
        (tester) async {
      await home(tester, withTransfer);
      await openHistory(tester);
      expect(find.text('Yape → Efectivo'), findsOneWidget);
      expect(find.descendant(of: key('history.row.t1'), matching: find.text('S/ 100.00')), findsOneWidget);
      final totals = tester.widget<Text>(key('history.totals.oneLine')).textSpan!.toPlainText().replaceAll(' ', ' ');
      expect(totals, '3 movimientos · Gastos S/ 25.00 · Ingresos S/ 0.00');
      await tap(tester, 'history.kind.expense');
      expect(key('history.row.t1'), findsNothing);
      await h.unmount(tester);
    });

    testWidgets('la búsqueda encuentra la transferencia por el nombre de la cuenta', (tester) async {
      await home(tester, withTransfer);
      await openHistory(tester);
      await tester.enterText(key('history.search'), 'efectivo');
      await tester.pumpAndSettle();
      expect(key('history.row.t1'), findsOneWidget);
      expect(key('history.row.g1'), findsNothing);
      await h.unmount(tester);
    });

    testWidgets('tocarla la edita; deslizarla la borra con confirmación', (tester) async {
      final seed = await home(tester, withTransfer);
      await openHistory(tester);
      await tap(tester, 'history.row.t1');
      expect(find.text('Guardar cambios'), findsOneWidget);
      await tap(tester, 'transfer.to.unassigned');
      await tap(tester, 'transfer.save');
      expect((await seed.db.select(seed.db.transfers).getSingle()).toAccountId, isNull);

      await tester.drag(key('history.row.t1'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tap(tester, 'history.delete.confirm');
      expect(await seed.db.select(seed.db.transfers).get(), isEmpty);
      expect(tester.takeException(), isNull);
      await h.unmount(tester);
    });
  });

  group('Insights: "Por cuenta"', () {
    Future<void> openInsights(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Insights'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Por cuenta'), 200, scrollable: find.byType(Scrollable).last);
    }

    testWidgets('saldo, y lo que salió y entró en 30 días (sin transferencias)', (tester) async {
      await home(tester, (s) async {
        await twoAccounts(s);
        await s.db.insertTransfer(id: 't', fromAccountId: 'yape', toAccountId: 'efectivo', amountCents: 999, day: h.ago(0));
      });
      await openInsights(tester);
      final yape = key('insights.account.Yape');
      expect(find.descendant(of: yape, matching: find.text('S/ 470.01')), findsOneWidget);
      expect(find.descendant(of: yape, matching: find.text('Salió S/ 20.00 · Entró S/ 0.00')), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('sin cuentas no hay bloque', (tester) async {
      await home(tester, (s) => s.expense(5, h.ago(1)));
      await tester.tap(find.byTooltip('Insights'));
      await tester.pumpAndSettle();
      expect(find.text('Por cuenta'), findsNothing);
      await h.unmount(tester);
    });
  });
}

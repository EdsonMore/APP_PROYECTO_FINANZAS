import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/press_scale.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';
import '../entry/entry_sheet.dart';
import '../entry/opening_balance_sheet.dart';
import 'home_blocks.dart';
import 'providers.dart';

const undoSnackDuration = Duration(seconds: 4);
const deletedSnackDuration = Duration(seconds: 2);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(homeSummaryProvider);
    return Scaffold(
      // Fijo abajo y fuera del scroll; los avisos flotantes aparecen encima.
      bottomNavigationBar: CTAButtons(mode: summary.value?.mode ?? Mode.variable),
      body: SafeArea(
        bottom: false,
        child: summary.when(
          loading: () => const _DelayedSkeleton(),
          error: (_, _) => _ErrorView(onRetry: () {
            ref.invalidate(entriesStreamProvider);
            ref.invalidate(categoriesStreamProvider);
            ref.invalidate(sourcesStreamProvider);
            ref.invalidate(budgetsStreamProvider);
          }),
          data: (s) => ListView(
            key: const Key('home.scroll'),
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
            children: [
              HomeHeader(title: s.title, onSettings: () => _openSettings(context)),
              NumberBlock(headline: s.headline),
              AnimatedSize(
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.lightChange,
                curve: Motion.easeOut,
                alignment: Alignment.topCenter,
                child: s.showOpeningCard && !ref.watch(openingCardDismissedProvider)
                    ? OpeningCard(
                        onSet: () => showOpeningBalanceSheet(context),
                        onDismiss: () => ref.read(openingCardDismissedProvider.notifier).state = true,
                      )
                    : const SizedBox(width: double.infinity),
              ),
              LightCard(view: s.light),
              if (s.top.isNotEmpty) TopCategoriesBlock(rows: s.top),
              if (s.recents.isNotEmpty) RecentMovementsBlock(rows: s.recents),
            ],
          ),
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _SettingsPlaceholder()));
}

/// "− Gasto" y "+ Ingreso". Mismo tamaño, salvo en Supervivencia: Ingreso sólido y 3/5 del ancho.
class CTAButtons extends ConsumerWidget {
  const CTAButtons({super.key, required this.mode});
  final Mode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final survival = mode == Mode.survival;
    Widget button(EntryKind kind, String label, {required int flex, required Color bg, required Color fg}) => Expanded(
          flex: flex,
          child: PressScale(
            child: FilledButton(
              key: Key('home.cta.${kind.name}'),
              onPressed: () => _register(context, ref, kind),
              style: FilledButton.styleFrom(
                backgroundColor: bg,
                foregroundColor: fg,
                minimumSize: const Size.fromHeight(Space.ctaHeight),
              ),
              child: Text(label),
            ),
          ),
        );

    return Container(
      color: p.canvas,
      padding: EdgeInsets.fromLTRB(
          Space.gutter, Space.md, Space.gutter, Space.lg + MediaQuery.paddingOf(context).bottom),
      child: Row(children: [
        button(EntryKind.expense, '− Gasto', flex: survival ? 2 : 1, bg: p.expenseBg, fg: p.expenseFg),
        const SizedBox(width: Space.md),
        survival
            ? button(EntryKind.income, '+ Ingreso', flex: 3, bg: p.incomeFg, fg: p.canvas)
            : button(EntryKind.income, '+ Ingreso', flex: 1, bg: p.incomeBg, fg: p.incomeFg),
      ]),
    );
  }

  Future<void> _register(BuildContext context, WidgetRef ref, EntryKind kind) async {
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(databaseProvider);
    final entry = await showEntrySheet(context, kind);
    if (entry != null) showUndoSnack(messenger, db, entry);
  }
}

/// Aviso de 4 s con "Deshacer" (DELETE real) y luego "Movimiento eliminado" 2 s.
/// Se cierra deslizando hacia abajo sin ejecutar nada (C3).
void showUndoSnack(ScaffoldMessengerState messenger, AppDatabase db, Entry entry) {
  final what = entry.kind == EntryKind.expense ? 'Gasto' : 'Ingreso';
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      key: const Key('home.undoSnack'),
      content: Text('$what de ${Formatters.soles(entry.amountCents)} guardado'),
      duration: undoSnackDuration,
      // Con acción, Flutter lo deja fijo por defecto (persist = true): sin esto no se cerraría solo.
      persist: false,
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.down,
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () => unawaited(_undo(messenger, db, entry.id)),
      ),
    ));
}

Future<void> _undo(ScaffoldMessengerState messenger, AppDatabase db, String id) async {
  await db.deleteEntry(id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(
      key: Key('home.deletedSnack'),
      content: Text('Movimiento eliminado'),
      duration: deletedSnackDuration,
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.down,
    ));
}

/// La base es local: casi siempre responde antes del primer frame. Solo si
/// tarda más de 300 ms aparece un esqueleto con la forma del número y el semáforo.
class _DelayedSkeleton extends StatefulWidget {
  const _DelayedSkeleton();

  @override
  State<_DelayedSkeleton> createState() => _DelayedSkeletonState();
}

class _DelayedSkeletonState extends State<_DelayedSkeleton> {
  bool _visible = false;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 300), () => setState(() => _visible = true));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.expand();
    final c = context.palette.border;
    Widget block(double w, double h) =>
        Container(width: w, height: h, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(Radii.chip)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg + 48 + Space.xxl, Space.gutter, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        block(120, 16),
        const SizedBox(height: Space.sm),
        block(220, 52),
        const SizedBox(height: Space.xl),
        block(double.infinity, 76),
      ]),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('No pude leer tus datos.', style: AppType.body.copyWith(color: p.ink)),
        const SizedBox(height: Space.sm),
        TextButton(onPressed: onRetry, child: const Text('Reintentar')),
      ]),
    );
  }
}

// ponytail: Ajustes real llega en el siguiente paso de 1b.
class _SettingsPlaceholder extends StatelessWidget {
  const _SettingsPlaceholder();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ajustes')),
        body: Center(
          child: Text('Llega en el siguiente paso.', style: AppType.body.copyWith(color: context.palette.inkMuted)),
        ),
      );
}

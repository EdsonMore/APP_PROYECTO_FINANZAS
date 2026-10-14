import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/select_chip.dart';
import '../../core/widgets/sheet_grabber.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';
import '../accounts/providers.dart';
import 'providers.dart';

/// "¿Cuánto puedo gastar hoy?" (4E): hoja desde el link bajo el número
/// principal. Solo muestra; los días se eligen cada vez y no se guardan.
Future<void> showAllowanceSheet(BuildContext context) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    sheetAnimationStyle: reduced
        ? const AnimationStyle(duration: Motion.reducedFade, reverseDuration: Motion.reducedFade)
        : const AnimationStyle(
            duration: Duration(milliseconds: 350),
            reverseDuration: Duration(milliseconds: 250),
            curve: Motion.emphasized,
          ),
    builder: (_) => const AllowanceSheet(),
  );
}

class AllowanceSheet extends ConsumerStatefulWidget {
  const AllowanceSheet({super.key});

  @override
  ConsumerState<AllowanceSheet> createState() => _AllowanceSheetState();
}

class _AllowanceSheetState extends ConsumerState<AllowanceSheet> {
  int? _days = 14; // null = "Otra fecha"
  DateTime? _until;

  /// Un monto nunca se parte entre "S/" y la cifra.
  static String _soles(int cents) => Formatters.soles(cents).replaceAll(' ', '\u00A0');

  String _short(DateTime d) => DateFormat('d MMM', 'es_PE').format(DateTime(d.year, d.month, d.day));

  Future<void> _pickDate(DateTime today) async {
    DateTime local(DateTime d) => DateTime(d.year, d.month, d.day);
    final picked = await showDatePicker(
      context: context,
      confirmText: 'Aceptar', // es trae "ACEPTAR" en mayúsculas
      initialDate: local(_until ?? today.add(const Duration(days: 7))),
      firstDate: local(today.add(const Duration(days: 1))),
      lastDate: local(today.add(const Duration(days: 365))),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _days = null;
      _until = dayOf(picked);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final today = ref.watch(todayProvider);
    final entries = ref.watch(entriesStreamProvider).value ?? const <Entry>[];
    final opening = ref.watch(settingsProvider).value?.opening;
    final custom = _days == null && _until != null;
    final days = custom ? daysUntil(_until!, today: today) : (_days ?? 14);
    final data = ref.watch(accountsDataProvider);
    final book = data == null ? const AccountBook() : accountBookOf(data.accounts, data.transfers);
    final a = dailyAllowance([for (final e in entries) e.toMovement()],
        today: today, days: days, opening: opening, book: book);
    final span = custom ? 'hasta el ${_short(_until!)}' : '$days días';
    final reduced = MediaQuery.disableAnimationsOf(context);
    final number = a == null ? 'Sin reserva' : Formatters.soles(a.leftTodayCents);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xl),
        child: Column(
          key: const Key('allowance.sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetGrabber(),
            Semantics(
              header: true,
              child: Text('¿Cuánto puedo gastar hoy?', style: AppType.title.copyWith(color: p.ink)),
            ),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              children: [
                for (final n in const [7, 14, 30])
                  SelectChip(
                    key: Key('allowance.days.$n'),
                    label: '$n días',
                    selected: _days == n,
                    onTap: () => setState(() => _days = n),
                  ),
                SelectChip(
                  key: const Key('allowance.until'),
                  label: custom ? 'Hasta el ${_short(_until!)}' : 'Otra fecha',
                  selected: custom,
                  onTap: () => _pickDate(today),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            Semantics(
              label: a == null ? 'Sin reserva' : 'Puedes gastar hoy $number',
              excludeSemantics: true,
              child: AnimatedSwitcher(
                duration: reduced ? Duration.zero : Motion.numberChange,
                child: Text(
                  number,
                  key: ValueKey(number),
                  style: AppType.display.copyWith(fontSize: 44, letterSpacing: -0.88, color: p.ink),
                ),
              ),
            ),
            const SizedBox(height: Space.md),
            if (a == null)
              Text(
                'Tu saldo de hoy es S/ 0.00 o menos. Registra un ingreso o actualiza tu saldo inicial.',
                key: const Key('allowance.noReserve'),
                style: AppType.body.copyWith(color: p.inkMuted),
              )
            else ...[
              Text(
                'Para que te alcance $span, puedes gastar ${_soles(a.limitCents)} al día.'
                '${a.spentTodayCents > 0 ? ' Hoy ya gastaste ${_soles(a.spentTodayCents)}.' : ''}',
                key: const Key('allowance.explain'),
                style: AppType.body.copyWith(color: p.inkMuted),
              ),
              if (a.overCents > 0) ...[
                const SizedBox(height: Space.sm),
                Text(
                  'Hoy pasaste el límite por ${_soles(a.overCents)}.',
                  key: const Key('allowance.over'),
                  style: AppType.body.copyWith(color: p.inkMuted),
                ),
              ],
            ],
            if (opening == null) ...[
              const SizedBox(height: Space.md),
              Text(
                'Calculado solo con tus movimientos. Para más precisión, agrega tu saldo inicial.',
                key: const Key('allowance.noOpening'),
                style: AppType.caption.copyWith(color: p.inkMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

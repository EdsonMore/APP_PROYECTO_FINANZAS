import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/select_chip.dart';
import '../../core/widgets/sheet_grabber.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';
import '../entry/amount_input.dart';
import '../entry/amount_keypad.dart';
import 'providers.dart';

/// "Transferir" (4A): plata de una cuenta a otra. Con [editing] edita esa
/// transferencia. Si se guardó algo, "Transferencia guardada" 2 s.
Future<void> showTransferSheet(BuildContext context, {TransferRow? editing}) async {
  final messenger = ScaffoldMessenger.of(context);
  final reduced = MediaQuery.disableAnimationsOf(context);
  final saved = await showModalBottomSheet<bool>(
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
    builder: (_) => TransferSheet(editing: editing),
  );
  if (saved != true) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(
      key: Key('transfer.savedSnack'),
      content: Text('Transferencia guardada'),
      duration: Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.down,
    ));
}

/// Valor de un chip de cuenta: el id, o '' para "Sin asignar" (null en la base).
const _unassigned = '';

class TransferSheet extends ConsumerStatefulWidget {
  const TransferSheet({super.key, this.editing});
  final TransferRow? editing;

  @override
  ConsumerState<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<TransferSheet> {
  late AmountInput _amount = _initialAmount();
  late String? _from = widget.editing == null ? null : (widget.editing!.fromAccountId ?? _unassigned);
  late String? _to = widget.editing == null ? null : (widget.editing!.toAccountId ?? _unassigned);
  late DateTime? _day = widget.editing == null ? null : parseIsoDay(widget.editing!.occurredOn); // null = hoy
  late final _note = TextEditingController(text: widget.editing?.note ?? '');
  String? _error;
  bool _saving = false;

  AmountInput _initialAmount() {
    final c = widget.editing?.amountCents;
    if (c == null) return const AmountInput();
    var a = const AmountInput();
    for (final ch in (c % 100 == 0 ? '${c ~/ 100}' : '${c ~/ 100}.${(c % 100).toString().padLeft(2, '0')}').split('')) {
      a = a.press(ch) ?? a;
    }
    return a;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _press(String key) {
    final next = _amount.press(key);
    if (next == null) {
      HapticFeedback.lightImpact();
      return;
    }
    setState(() {
      _amount = next;
      if (_error != _sameText) _error = null;
    });
  }

  static const _sameText = 'Elige dos cuentas distintas.';

  Future<void> _save(String from, String to) async {
    if (_saving) return;
    if (_amount.cents == 0) return setState(() => _error = 'Ingresa un monto mayor a S/ 0');
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final today = ref.read(todayProvider);
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    String? id(String v) => v == _unassigned ? null : v;
    try {
      if (widget.editing case final t?) {
        final updated = await db.updateTransfer(
            id: t.id, fromAccountId: id(from), toAccountId: id(to), amountCents: _amount.cents, day: _day ?? today, note: note);
        if (mounted) Navigator.of(context).pop(updated != null && updated.updatedAt != t.updatedAt);
      } else {
        await db.insertTransfer(
            id: const Uuid().v4(),
            fromAccountId: id(from),
            toAccountId: id(to),
            amountCents: _amount.cents,
            day: _day ?? today,
            note: note);
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar. Intenta de nuevo.';
      });
    }
  }

  Future<void> _pickDate(DateTime today) async {
    DateTime local(DateTime d) => DateTime(d.year, d.month, d.day);
    final first = [today.subtract(const Duration(days: 730)), ?_day].reduce((a, b) => a.isBefore(b) ? a : b);
    final picked = await showDatePicker(
      context: context,
      confirmText: 'Aceptar', // es trae "ACEPTAR" en mayúsculas
      initialDate: local(_day ?? today),
      firstDate: local(first),
      lastDate: local(today),
    );
    if (picked == null) return;
    final d = dayOf(picked);
    setState(() => _day = d == today ? null : d);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenH = MediaQuery.sizeOf(context).height;
    final today = ref.watch(todayProvider);
    final accounts = ref.watch(accountsStreamProvider).value ?? const <Account>[];
    final editing = widget.editing;
    // Las activas + "Sin asignar"; en edición, también la archivada que use.
    final options = <({String value, String label})>[
      for (final a in accounts)
        if (!a.archived || a.id == editing?.fromAccountId || a.id == editing?.toAccountId)
          (value: a.id, label: a.archived ? '${a.name} (archivada)' : a.name),
      (value: _unassigned, label: unassignedName),
    ];
    final from = _from ?? options.first.value;
    final to = _to ?? (options.length > 1 ? options[1].value : _unassigned);
    final same = from == to;
    final error = same ? _sameText : _error;
    final d = _day ?? today;
    final dayLabel = d == today
        ? 'Hoy'
        : d == today.subtract(const Duration(days: 1))
            ? 'Ayer'
            : DateFormat('d MMM', 'es_PE').format(DateTime(d.year, d.month, d.day));

    Widget chips(String label, String selected, ValueChanged<String> onPick, String keyPrefix) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppType.label.copyWith(color: p.inkMuted)),
            Wrap(
              spacing: Space.sm,
              children: [
                for (final o in options)
                  SelectChip(
                    key: Key('$keyPrefix.${o.value.isEmpty ? 'unassigned' : o.value}'),
                    label: o.label,
                    selected: o.value == selected,
                    onTap: () => setState(() {
                      onPick(o.value);
                      if (_error != _sameText) _error = null;
                    }),
                  ),
              ],
            ),
          ],
        );

    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: p.surface,
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Column(
              key: const Key('transfer.sheet'),
              children: [
                const SheetGrabber(),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Semantics(
                        header: true,
                        child: Text('Transferir', style: AppType.title.copyWith(color: p.ink)),
                      ),
                      const Spacer(),
                      SelectChip(
                        key: const Key('transfer.date'),
                        label: dayLabel,
                        leading: Icon(Icons.calendar_today_outlined, size: 16, color: p.ink),
                        semanticsLabel: 'Fecha: $dayLabel. Cambiar',
                        selected: false,
                        onTap: () => _pickDate(today),
                      ),
                      IconButton(
                        key: const Key('transfer.close'),
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: Icon(Icons.close, color: p.inkMuted),
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: const Key('transfer.scroll'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: Space.md),
                          child: AmountDisplay(key: const Key('transfer.amount'), amount: _amount),
                        ),
                        SizedBox(
                          height: 20,
                          child: error == null
                              ? null
                              : Text(error,
                                  key: const Key('transfer.error'),
                                  style: AppType.caption.copyWith(color: p.expenseFg)),
                        ),
                        const SizedBox(height: Space.sm),
                        chips('Desde', from, (v) => _from = v, 'transfer.from'),
                        const SizedBox(height: Space.sm),
                        chips('Hacia', to, (v) => _to = v, 'transfer.to'),
                        const SizedBox(height: Space.sm),
                        TextField(
                          key: const Key('transfer.note'),
                          controller: _note,
                          style: AppType.body.copyWith(color: p.ink),
                          textCapitalization: TextCapitalization.sentences,
                          inputFormatters: [LengthLimitingTextInputFormatter(120)],
                          decoration: const InputDecoration(
                            hintText: 'Nota (opcional)',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Space.sm),
                AmountKeypad(
                  keyHeight: Space.keyHeight(screenH),
                  onKey: _press,
                  onBackspace: () => setState(() => _amount = _amount.backspace()),
                  onClear: () => setState(() => _amount = const AmountInput()),
                ),
                const SizedBox(height: Space.md),
                SizedBox(
                  height: Space.sheetCtaHeight(screenH),
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('transfer.save'),
                    onPressed: same || _saving ? null : () => _save(from, to),
                    style: FilledButton.styleFrom(
                      disabledBackgroundColor: p.border,
                      disabledForegroundColor: p.inkMuted,
                    ),
                    child: Text(editing == null ? 'Transferir' : 'Guardar cambios'),
                  ),
                ),
                const SizedBox(height: Space.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

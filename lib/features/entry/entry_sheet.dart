import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/icon_catalog.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/sheet_grabber.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';
import 'amount_input.dart';
import 'amount_keypad.dart';
import 'draft_store.dart';

/// Abre la hoja de registro. Devuelve el movimiento guardado, o null si se cerró.
Future<Entry?> showEntrySheet(BuildContext context, EntryKind kind) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<Entry>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    // ponytail: la ruta del sheet no acepta un spring; curva enfática ≈ sheetSpring.
    sheetAnimationStyle: reduced
        ? const AnimationStyle(duration: Motion.reducedFade, reverseDuration: Motion.reducedFade)
        : const AnimationStyle(
            duration: Duration(milliseconds: 350),
            reverseDuration: Duration(milliseconds: 250),
            curve: Motion.emphasized),
    builder: (_) => EntrySheet(kind: kind),
  );
}

/// Umbrales del cronómetro de guardado (C2). null = no se loguea.
({int level, String message})? saveDurationLog(int ms) {
  if (ms > 2000) return (level: 1000, message: 'guardado muy lento ($ms ms)');
  if (ms > 500) return (level: 900, message: 'guardado lento ($ms ms)');
  return null;
}

const _slowNoticeAfter = Duration(seconds: 2);
const _draftDebounce = Duration(milliseconds: 300);
const noteMaxLength = 120;

/// Cuánto debe seguir oculto el IME para tratarlo como "Atrás" y no como un
/// parpadeo (cambio de teclado, cambio de configuración).
const _imeHiddenGrace = Duration(milliseconds: 150);

/// Registro de gasto o ingreso. Un solo widget; [kind] cambia título, color,
/// catálogo (categorías/fuentes) y la columna que se llena al guardar.
class EntrySheet extends ConsumerStatefulWidget {
  const EntrySheet({super.key, required this.kind});
  final EntryKind kind;

  @override
  ConsumerState<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends ConsumerState<EntrySheet> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final DraftStore _store = ref.read(draftStoreProvider);
  late final AppDatabase _db = ref.read(databaseProvider);
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  final _note = TextEditingController();
  final _noteFocus = FocusNode();

  List<PickOption>? _options; // null = cargando
  AmountInput _amount = const AmountInput();
  String? _pick;
  DateTime? _day; // null = hoy
  bool _noteOpen = false; // pantalla normal: el campo queda visible si hay texto
  bool _noteEditing = false; // el campo existe y tiene (o está por tener) foco
  String? _error;
  bool _saving = false;
  bool _done = false; // guardado o descartado: el borrador ya no se escribe
  Timer? _debounce;
  Timer? _slowNotice;
  bool _imeVisible = false;
  Timer? _imeHidden;

  bool get _isExpense => widget.kind == EntryKind.expense;

  String get _noOptionsText => _isExpense
      ? 'No tienes categorías activas. Actívalas en Ajustes.'
      : 'No tienes fuentes activas. Actívalas en Ajustes.';

  Draft get _draft => Draft(amountText: _amount.text, pickId: _pick, day: _day, note: _note.text);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _noteFocus.addListener(() => setState(() {
          if (!_noteFocus.hasFocus) _noteEditing = false;
        }));
    _load();
  }

  Future<void> _load() async {
    final options = await _db.activeOptions(widget.kind);
    final lastUsed = await _db.lastUsedPick(widget.kind);
    final draft = _store.load(widget.kind);
    if (!mounted) return;
    final today = ref.read(todayProvider);
    final ids = {for (final o in options) o.id};
    setState(() {
      _options = options;
      // Borrador → última usada → primera del orden (Comida / Chamba).
      _pick = [draft?.pickId, lastUsed, options.firstOrNull?.id].firstWhere(ids.contains, orElse: () => null);
      if (draft != null) {
        _amount = _sanitize(draft.amountText);
        _day = draft.day == null || draft.day!.isAfter(today) || draft.day == today ? null : draft.day;
        _note.text = draft.note;
        _noteOpen = draft.note.isNotEmpty;
      }
    });
  }

  /// El borrador viene de disco: se re-teclea para que solo entren textos válidos.
  static AmountInput _sanitize(String text) {
    var a = const AmountInput();
    for (final c in text.split('')) {
      if ('0123456789.'.contains(c)) a = a.press(c) ?? a;
    }
    return a;
  }

  // ---- Borrador (C3): debounce + escritura incondicional en eventos críticos.

  void _changed(VoidCallback update) {
    setState(update);
    _debounce?.cancel();
    _debounce = Timer(_draftDebounce, _writeDraft);
  }

  void _writeDraft() {
    if (_done || _options == null) return;
    unawaited(_store.save(widget.kind, _draft));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive = la hoja pierde el foco (overlay del sistema, cambio de app);
    // paused/hidden = Android puede matar el proceso después.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _writeDraft();
    }
  }

  /// Android oculta el teclado con Atrás sin quitar el foco: sin esto el
  /// teclado propio no vuelve (C1). Solo reacciona a visible → oculto, y solo
  /// si sigue oculto tras [_imeHiddenGrace] (un cambio de teclado no cuenta).
  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final visible = view.viewInsets.bottom > 0;
    if (visible) {
      _imeHidden?.cancel();
    } else if (_imeVisible) {
      _imeHidden?.cancel();
      _imeHidden = Timer(_imeHiddenGrace, () {
        final stillHidden = WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom == 0;
        if (mounted && stillHidden && _noteFocus.hasFocus) _noteFocus.unfocus();
      });
    }
    _imeVisible = visible;
  }

  @override
  void dispose() {
    _imeHidden?.cancel();
    _debounce?.cancel();
    _slowNotice?.cancel();
    _writeDraft(); // cierre por X, gesto, scrim o Atrás
    WidgetsBinding.instance.removeObserver(this);
    _shake.dispose();
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _openNote() {
    setState(() {
      _noteOpen = true;
      _noteEditing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _noteFocus.requestFocus());
  }

  // ---- Teclado propio

  void _press(String key) {
    final next = _amount.press(key);
    if (next == null) {
      HapticFeedback.lightImpact();
      return;
    }
    _changed(() {
      _amount = next;
      _error = null;
    });
  }

  void _backspace() => _changed(() => _amount = _amount.backspace());

  void _clearAmount() => _changed(() => _amount = const AmountInput());

  // ---- Guardar

  void _fail(String message) {
    setState(() => _error = message);
    HapticFeedback.mediumImpact();
    if (!MediaQuery.disableAnimationsOf(context)) _shake.forward(from: 0);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_options != null && _options!.isEmpty) return _fail(_noOptionsText);
    if (_amount.cents == 0) return _fail('Ingresa un monto mayor a S/ 0');
    if (_pick == null) return _fail(_noOptionsText);

    setState(() {
      _saving = true;
      _error = null;
    });
    final watch = Stopwatch()..start();
    _slowNotice = Timer(_slowNoticeAfter, () {
      if (mounted) _snack('Esto está tardando más de lo normal');
    });
    try {
      final note = _note.text.trim();
      final entry = await _db.insertManualEntry(
        id: const Uuid().v4(),
        kind: widget.kind,
        amountCents: _amount.cents,
        day: _day ?? ref.read(todayProvider),
        pickId: _pick!,
        note: note.isEmpty ? null : note,
        now: DateTime.now(),
      );
      _logDuration(watch.elapsedMilliseconds);
      _done = true;
      _debounce?.cancel();
      await _store.clear(widget.kind);
      HapticFeedback.lightImpact();
      if (mounted) Navigator.of(context).pop(entry);
    } catch (_) {
      _logDuration(watch.elapsedMilliseconds);
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('No se pudo guardar. Intenta de nuevo.');
    } finally {
      _slowNotice?.cancel();
    }
  }

  void _logDuration(int ms) {
    final log = saveDurationLog(ms);
    if (log != null) developer.log(log.message, name: 'SaldoClaro.entry', level: log.level);
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  // ---- Cerrar / descartar

  Future<void> _showDiscardMenu(BuildContext buttonContext) async {
    if (_draft.isEmpty) return; // sin borrador, mantener presionado no hace nada
    final box = buttonContext.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(buttonContext).context.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final choice = await showMenu<bool>(
      context: buttonContext,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: const [PopupMenuItem(value: true, child: Text('Descartar borrador'))],
    );
    if (choice == true) await _discard();
  }

  Future<void> _discard() async {
    _done = true;
    _debounce?.cancel();
    await _store.clear(widget.kind);
    if (mounted) Navigator.of(context).pop();
  }

  // ---- Fecha

  Future<void> _pickDate() async {
    final today = ref.read(todayProvider);
    DateTime local(DateTime d) => DateTime(d.year, d.month, d.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: local(_day ?? today),
      firstDate: local(today.subtract(const Duration(days: 730))),
      lastDate: local(today), // nunca futuro: las métricas lo ignorarían
    );
    if (picked == null) return;
    final d = dayOf(picked);
    _changed(() => _day = d == today ? null : d);
  }

  String _dayLabel(DateTime today) {
    final d = _day ?? today;
    if (d == today) return 'Hoy';
    if (d == today.subtract(const Duration(days: 1))) return 'Ayer';
    return DateFormat('d MMM', 'es_PE').format(DateTime(d.year, d.month, d.day));
  }

  // ---- UI

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenH = MediaQuery.sizeOf(context).height;
    final noteActive = _noteFocus.hasFocus;
    final today = ref.watch(todayProvider);
    // 720p ≈ 640 dp: la nota pasa a ser un chip más para que la hoja quepa sin scroll.
    final compact = screenH < Space.compactBelowHeight;

    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: p.surface,
        resizeToAvoidBottomInset: true, // "Guardar" sube sobre el teclado del sistema
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Column(children: [
              const SheetGrabber(),
              _header(p, today),
              Expanded(
                // Sin teclado del sistema cabe sin scroll (ver test de 640 dp);
                // con él, la parte de arriba se desplaza y nada desborda.
                child: SingleChildScrollView(
                  key: const Key('entry.scroll'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _amountView(p),
                    _errorLine(p),
                    const SizedBox(height: Space.md),
                    _chips(p, compact),
                    if (!compact || _noteEditing) ...[
                      const SizedBox(height: Space.sm),
                      _noteView(p, compact),
                    ],
                  ]),
                ),
              ),
              // C1: con la nota activa, el teclado propio desaparece.
              if (!noteActive) ...[
                const SizedBox(height: Space.sm),
                AmountKeypad(keyHeight: Space.keyHeight(screenH), onKey: _press, onBackspace: _backspace, onClear: _clearAmount),
              ],
              const SizedBox(height: Space.md),
              _saveButton(p, Space.sheetCtaHeight(screenH)),
              const SizedBox(height: Space.lg),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header(Palette p, DateTime today) => SizedBox(
        height: 48,
        child: Row(children: [
          Semantics(
            header: true,
            child: Text(_isExpense ? 'Gasto' : 'Ingreso',
                style: AppType.title.copyWith(color: _isExpense ? p.expenseFg : p.incomeFg)),
          ),
          const Spacer(),
          PressScale(
            child: Semantics(
              button: true,
              label: 'Fecha: ${_dayLabel(today)}. Cambiar',
              excludeSemantics: true,
              child: GestureDetector(
                key: const Key('entry.date'),
                behavior: HitTestBehavior.opaque,
                onTap: _pickDate,
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.only(left: Space.md, right: Space.sm),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(Radii.chip),
                        border: Border.all(color: p.border),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_dayLabel(today), style: AppType.label.copyWith(color: p.ink)),
                        Icon(Icons.expand_more, size: 18, color: p.inkMuted),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          Builder(
            builder: (buttonContext) => Semantics(
              button: true,
              label: 'Cerrar',
              customSemanticsActions: {
                const CustomSemanticsAction(label: 'Descartar borrador'): () => _discard(),
              },
              excludeSemantics: true,
              child: GestureDetector(
                onLongPress: () => _showDiscardMenu(buttonContext),
                child: IconButton(
                  key: const Key('entry.close'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: p.inkMuted),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                ),
              ),
            ),
          ),
        ]),
      );

  Widget _amountView(Palette p) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _noteFocus.unfocus(), // tocar el monto vuelve al teclado propio
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          final t = _shake.value;
          final dx = _shake.isAnimating ? 8 * math.sin(t * 3 * 2 * math.pi) * (1 - t) : 0.0;
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: Padding(
          padding: const EdgeInsets.only(top: Space.lg),
          child: AmountDisplay(key: const Key('entry.amount'), amount: _amount),
        ),
      ),
    );
  }

  /// Alto reservado: el error aparece sin mover la hoja.
  Widget _errorLine(Palette p) => SizedBox(
        height: 20,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: _error == null
              ? null
              : Text(_error!,
                  key: const Key('entry.error'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(color: p.expenseFg)),
        ),
      );

  /// En pantalla compacta, "Agregar nota" es el último chip del Wrap.
  Widget _chips(Palette p, bool compact) {
    final options = _options;
    if (options == null) return const SizedBox(height: 88);
    final note = _note.text.trim();
    final noteChip = _PickChip(
      key: const Key('entry.addNote'),
      label: note.isEmpty ? 'Agregar nota' : note,
      semanticsLabel: note.isEmpty ? 'Agregar nota' : 'Nota: $note. Editar',
      icon: Icons.notes,
      selected: false,
      outlined: _noteEditing || note.isNotEmpty,
      onTap: _openNote,
    );
    if (options.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_noOptionsText, style: AppType.caption.copyWith(color: p.inkMuted)),
        if (compact) noteChip,
      ]);
    }
    return Wrap(spacing: Space.sm, children: [
      for (final o in options)
        _PickChip(
          key: Key('pick.${o.id}'),
          label: o.name,
          icon: IconCatalog.iconFor(o.icon),
          selected: o.id == _pick,
          onTap: () => _changed(() {
            _pick = o.id;
            if (_error == _noOptionsText) _error = null;
          }),
        ),
      if (compact) noteChip,
    ]);
  }

  /// Normal: enlace o campo. Compacta: solo el campo mientras se edita (el
  /// chip del Wrap hace de enlace y muestra el texto cuando no hay foco).
  Widget _noteView(Palette p, bool compact) {
    if (!compact && !_noteOpen && !_noteEditing) {
      return Semantics(
        button: true,
        child: GestureDetector(
          key: const Key('entry.addNote'),
          behavior: HitTestBehavior.opaque,
          onTap: _openNote,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.notes, size: 18, color: p.inkMuted),
              const SizedBox(width: Space.sm),
              Text('Agregar nota', style: AppType.label.copyWith(color: p.inkMuted)),
            ]),
          ),
        ),
      );
    }
    return TextField(
      key: const Key('entry.note'),
      controller: _note,
      focusNode: _noteFocus,
      style: AppType.body.copyWith(color: p.ink),
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      inputFormatters: [LengthLimitingTextInputFormatter(noteMaxLength)],
      decoration: const InputDecoration(
        hintText: 'Nota (opcional)',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      ),
      onChanged: (_) => _changed(() {}),
      onSubmitted: (_) => _noteFocus.unfocus(),
    );
  }

  Widget _saveButton(Palette p, double height) => SizedBox(
        height: height,
        width: double.infinity,
        child: Semantics(
          enabled: !_saving,
          child: AbsorbPointer(
            absorbing: _saving,
            child: AnimatedOpacity(
              opacity: _saving ? 0.6 : 1,
              duration: Motion.press,
              child: PressScale(
                child: FilledButton(
                  key: const Key('entry.save'),
                  onPressed: _save,
                  style: FilledButton.styleFrom(minimumSize: Size.fromHeight(height)),
                  child: _saving
                      ? SizedBox(
                          key: const Key('entry.saving'),
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: p.canvas),
                        )
                      : const Text('Guardar'),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Chip de categoría/fuente (o de nota en pantalla compacta): visible 36, área táctil 44.
class _PickChip extends StatelessWidget {
  const _PickChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.outlined = false,
    this.semanticsLabel,
  });
  final String label;
  final IconData icon;
  final bool selected;

  /// Borde ink sin relleno: chip de nota activo o con texto.
  final bool outlined;
  final String? semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected ? p.canvas : p.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            widthFactor: 1, // sin esto el chip se estira a toda la fila del Wrap
            child: AnimatedContainer(
              duration: Motion.lightChange,
              curve: Motion.easeOut,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              decoration: BoxDecoration(
                color: selected ? p.ink : p.surface,
                borderRadius: BorderRadius.circular(Radii.chip),
                border: Border.all(color: selected || outlined ? p.ink : p.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label.copyWith(color: fg)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

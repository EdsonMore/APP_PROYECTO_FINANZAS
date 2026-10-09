import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/icon_catalog.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/sheet_grabber.dart';
import '../../core/widgets/text_link.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';

/// Pictogramas + piezas de secuencias emoji: variation selector, ZWJ, tonos de
/// piel, indicadores regionales (banderas), keycap y tag characters.
// El lint no evalúa con `unicode: true`; la regex es válida (cubierta por tests).
final emojiRegex = RegExp(
    // ignore: valid_regexps
    r'[\p{Extended_Pictographic}\u{FE0F}\u{200D}\u{1F3FB}-\u{1F3FF}\u{1F1E6}-\u{1F1FF}\u{20E3}\u{E0020}-\u{E007F}]',
    unicode: true);

/// Los chips del registro tienen que caber en 720p.
const catalogNameMaxLength = 20;
const lastActiveText = 'Necesitas al menos una activa.';

/// Nombre de categoría/fuente: sin emojis, trim, ≤ 20, sin repetir otro
/// nombre del mismo catálogo (sin distinguir mayúsculas).
({String? value, String? error}) validateCatalogName(String raw, {required Iterable<String> taken}) {
  final v = raw.replaceAll(emojiRegex, '').trim();
  if (v.isEmpty) return (value: null, error: null);
  if (v.characters.length > catalogNameMaxLength) return (value: null, error: 'Máximo $catalogNameMaxLength caracteres');
  final lower = v.toLowerCase();
  if (taken.any((t) => t.toLowerCase() == lower)) return (value: null, error: 'Ya existe una con ese nombre.');
  return (value: v, error: null);
}

/// Crea ([existing] null) o edita un ítem. [items] = el catálogo completo, para
/// detectar duplicados y si es la última activa.
Future<void> showCatalogEditor(BuildContext context,
    {required EntryKind kind, required List<CatalogItem> items, CatalogItem? existing}) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    sheetAnimationStyle: reduced
        ? const AnimationStyle(duration: Motion.reducedFade, reverseDuration: Motion.reducedFade)
        : const AnimationStyle(
            duration: Duration(milliseconds: 350), reverseDuration: Duration(milliseconds: 250), curve: Motion.emphasized),
    builder: (_) => CatalogEditor(kind: kind, items: items, existing: existing),
  );
}

class CatalogEditor extends ConsumerStatefulWidget {
  const CatalogEditor({super.key, required this.kind, required this.items, this.existing});
  final EntryKind kind;
  final List<CatalogItem> items;
  final CatalogItem? existing;

  @override
  ConsumerState<CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends ConsumerState<CatalogEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _icon = widget.existing?.icon ?? (widget.kind == EntryKind.expense ? 'category' : 'payments');
  String? _error;
  bool _busy = false;

  bool get _isExpense => widget.kind == EntryKind.expense;
  Iterable<String> get _taken => widget.items.where((i) => i.id != widget.existing?.id).map((i) => i.name);

  /// Archivar la última activa dejaría el registro sin opciones (decisión b).
  bool get _isLastActive =>
      widget.existing != null && !widget.existing!.archived && widget.items.where((i) => !i.archived).length <= 1;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final r = validateCatalogName(_name.text, taken: _taken);
    if (r.error != null || r.value == null) return setState(() => _error = r.error);
    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    try {
      if (widget.existing == null) {
        await db.addCatalogItem(widget.kind, id: const Uuid().v4(), name: r.value!, icon: _icon);
      } else {
        await db.updateCatalogItem(widget.kind, widget.existing!.id, name: r.value!, icon: _icon);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // UNIQUE de la BD: otra pantalla pudo crear el mismo nombre.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Ya existe una con ese nombre.';
      });
    }
  }

  Future<void> _archive() async {
    setState(() => _busy = true);
    await ref.read(databaseProvider).setArchived(widget.kind, widget.existing!.id, archived: true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenH = MediaQuery.sizeOf(context).height;
    final canSave = !_busy && _name.text.replaceAll(emojiRegex, '').trim().isNotEmpty;
    final title = widget.existing == null
        ? (_isExpense ? 'Nueva categoría' : 'Nueva fuente')
        : (_isExpense ? 'Editar categoría' : 'Editar fuente');

    final save = FilledButton(
      key: const Key('editor.save'),
      onPressed: canSave ? _save : null,
      style: FilledButton.styleFrom(
        minimumSize: Size.fromHeight(Space.sheetCtaHeight(screenH)),
        disabledBackgroundColor: p.border,
        disabledForegroundColor: p.inkMuted,
      ),
      child: const Text('Guardar'),
    );

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            Space.gutter, 0, Space.gutter, Space.lg + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          key: const Key('editor.sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetGrabber(),
            Semantics(header: true, child: Text(title, style: AppType.title.copyWith(color: p.ink))),
            const SizedBox(height: Space.lg),
            TextField(
              key: const Key('editor.name'),
              controller: _name,
              autofocus: widget.existing == null,
              style: AppType.body.copyWith(color: p.ink),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.deny(emojiRegex)],
              decoration: InputDecoration(hintText: _isExpense ? 'Ej.: Mascotas' : 'Ej.: Propinas', errorText: _error),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => canSave ? _save() : null,
            ),
            const SizedBox(height: Space.lg),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              for (final e in IconCatalog.items.entries)
                _IconTile(
                  key: Key('editor.icon.${e.key}'),
                  icon: e.value,
                  name: e.key,
                  selected: e.key == _icon,
                  onTap: () => setState(() => _icon = e.key),
                ),
            ]),
            const SizedBox(height: Space.lg),
            canSave ? PressScale(child: save) : save,
            if (widget.existing != null) ...[
              const SizedBox(height: Space.sm),
              Center(
                child: TextLink(
                  key: const Key('editor.archive'),
                  label: 'Archivar',
                  semanticsLabel: _isLastActive ? 'Archivar, desactivado. $lastActiveText' : 'Archivar',
                  onTap: _isLastActive || _busy ? null : _archive,
                ),
              ),
              if (_isLastActive)
                Center(child: Text(lastActiveText, style: AppType.caption.copyWith(color: p.inkMuted))),
            ],
          ],
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({super.key, required this.icon, required this.name, required this.selected, required this.onTap});
  final IconData icon;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Ícono ${name.replaceAll('_', ' ')}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.lightChange,
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(Radii.chip),
            border: Border.all(color: selected ? p.ink : p.border, width: selected ? 2 : 1),
          ),
          child: Icon(icon, size: 24, color: selected ? p.ink : p.inkMuted),
        ),
      ),
    );
  }
}

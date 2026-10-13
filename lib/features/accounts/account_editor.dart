import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/icon_catalog.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/sheet_grabber.dart';
import '../../core/widgets/text_link.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../entry/opening_balance_sheet.dart';
import '../settings/catalog_editor.dart' show IconTile, emojiRegex, validateCatalogName;
import '../settings/settings_screen.dart' show SettingsRow;

/// Íconos de cuenta: billetera, celular, banco, tarjeta, alcancía, efectivo.
const accountIcons = [
  'account_balance_wallet',
  'phone_android',
  'account_balance',
  'credit_card',
  'savings',
  'payments',
];

/// Crea ([existing] null) o edita una cuenta. [all] = todas las cuentas, para
/// no repetir nombres (sin distinguir mayúsculas, como los catálogos).
Future<void> showAccountEditor(BuildContext context, {required List<Account> all, Account? existing}) {
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
    builder: (_) => AccountEditor(all: all, existing: existing),
  );
}

class AccountEditor extends ConsumerStatefulWidget {
  const AccountEditor({super.key, required this.all, this.existing});
  final List<Account> all;
  final Account? existing;

  @override
  ConsumerState<AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends ConsumerState<AccountEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _icon = widget.existing?.icon ?? accountIcons.first;

  /// Cuenta nueva: el saldo inicial se guarda junto con la cuenta.
  int? _newOpening;
  String? _error;
  bool _busy = false;

  Iterable<String> get _taken => widget.all.where((a) => a.id != widget.existing?.id).map((a) => a.name);

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
      if (widget.existing case final a?) {
        await db.updateAccount(a.id, name: r.value!, icon: _icon);
      } else {
        final id = const Uuid().v4();
        await db.transaction(() async {
          await db.insertAccount(id: id, name: r.value!, icon: _icon);
          if (_newOpening case final c?) await db.setAccountOpening(id, cents: c, at: DateTime.now());
        });
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return; // UNIQUE de la BD: otra pantalla pudo crear el mismo nombre.
      setState(() {
        _busy = false;
        _error = 'Ya existe una con ese nombre.';
      });
    }
  }

  Future<void> _opening() async {
    final db = ref.read(databaseProvider);
    final existing = widget.existing;
    final name = _name.text.trim().isEmpty ? 'la cuenta' : _name.text.trim();
    await showOpeningBalanceSheet(
      context,
      title: 'Saldo inicial de $name',
      save: existing == null
          ? (c) async => setState(() => _newOpening = c)
          : (c) => db.setAccountOpening(existing.id, cents: c, at: DateTime.now()),
    );
  }

  Future<void> _toggleArchived() async {
    setState(() => _busy = true);
    final a = widget.existing!;
    await ref.read(databaseProvider).setAccountArchived(a.id, archived: !a.archived);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenH = MediaQuery.sizeOf(context).height;
    final existing = widget.existing;
    // El saldo inicial vigente: el de la base (cuenta existente) o el elegido.
    final live = existing == null
        ? null
        : ref.watch(_accountProvider(existing.id)).value ?? existing;
    final openingCents = existing == null ? _newOpening : live?.openingBalanceCents;
    final canSave = !_busy && _name.text.replaceAll(emojiRegex, '').trim().isNotEmpty;

    final save = FilledButton(
      key: const Key('account.save'),
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
        padding: EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          key: const Key('account.editor'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetGrabber(),
            Semantics(
              header: true,
              child: Text(existing == null ? 'Nueva cuenta' : existing.name, style: AppType.title.copyWith(color: p.ink)),
            ),
            const SizedBox(height: Space.lg),
            TextField(
              key: const Key('account.name'),
              controller: _name,
              autofocus: existing == null,
              style: AppType.body.copyWith(color: p.ink),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.deny(emojiRegex)],
              decoration: InputDecoration(hintText: 'Ej.: Yape', errorText: _error),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => canSave ? _save() : null,
            ),
            const SizedBox(height: Space.lg),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final name in accountIcons)
                  IconTile(
                    key: Key('account.icon.$name'),
                    icon: IconCatalog.iconFor(name),
                    name: name,
                    selected: name == _icon,
                    onTap: () => setState(() => _icon = name),
                  ),
              ],
            ),
            const SizedBox(height: Space.md),
            SettingsRow(
              key: const Key('account.opening'),
              label: 'Saldo inicial',
              value: openingCents == null ? 'Sin definir' : Formatters.soles(openingCents),
              link: 'Cambiar',
              onTap: _busy ? null : _opening,
            ),
            const SizedBox(height: Space.md),
            canSave ? PressScale(child: save) : save,
            if (existing != null) ...[
              const SizedBox(height: Space.sm),
              Center(
                child: TextLink(
                  key: const Key('account.archive'),
                  label: existing.archived ? 'Desarchivar' : 'Archivar',
                  semanticsLabel: existing.archived ? 'Desarchivar' : 'Archivar',
                  onTap: _busy ? null : _toggleArchived,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// La cuenta al día (el saldo inicial cambia mientras el editor está abierto).
final _accountProvider = StreamProvider.autoDispose.family<Account?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.accounts)..where((a) => a.id.equals(id))).watchSingleOrNull();
});

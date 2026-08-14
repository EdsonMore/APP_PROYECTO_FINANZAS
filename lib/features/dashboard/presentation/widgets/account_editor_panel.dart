import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/models/account.dart';
import 'package:saldo_claro/features/dashboard/providers/repository_providers.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/icon_catalog.dart';

/// Panel (bottom sheet) para crear/editar una cuenta.
class AccountEditorPanel extends ConsumerStatefulWidget {
  const AccountEditorPanel({super.key, this.existing});

  final Account? existing;

  @override
  ConsumerState<AccountEditorPanel> createState() => _AccountEditorPanelState();
}

class _AccountEditorPanelState extends ConsumerState<AccountEditorPanel> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _bankController;
  late final TextEditingController _colorController;
  final _balanceController = TextEditingController();

  int _sortOrder = 99;
  String _selectedIcon = 'account_balance_wallet';
  bool _isEdit = false;
  bool _saving = false;

  static const List<Color> _palette = [
    Color(0xFF7B1FA2),
    Color(0xFF002A8F),
    Color(0xFFEF3340),
    Color(0xFF00A859),
    Color(0xFFE67E22),
    Color(0xFF3498DB),
    Color(0xFF9B59B6),
    Color(0xFFE91E63),
    Color(0xFF16A085),
    Color(0xFF2ECC71),
    Color(0xFFC0392B),
    Color(0xFFF39C12),
  ];

  String _hexFromColor(Color c) {
    final value = c.toARGB32() & 0xFFFFFF;
    return value.toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _isEdit = a != null;
    _nameController = TextEditingController(text: a?.name ?? '');
    _bankController = TextEditingController(text: a?.bank ?? '');
    _colorController =
        TextEditingController(text: a?.colorHex ?? '7B1FA2');
    _selectedIcon = a?.resolvedIcon ?? 'account_balance_wallet';
    _sortOrder = a?.sortOrder ?? 99;
    if (a != null) {
      _balanceController.text = a.balance.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bankController.dispose();
    _colorController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(accountRepositoryProvider);
      final name = _nameController.text.trim();
      final balance =
          double.tryParse(_balanceController.text.replaceAll(',', '.')) ?? 0;
      final bank = _bankController.text.trim().isEmpty
          ? null
          : _bankController.text.trim();
      final colorHex = _colorController.text.trim();

      if (_isEdit) {
        final existing = widget.existing!;
        final updated = existing.copyWith(
          name: name,
          bank: bank,
          icon: _selectedIcon,
          colorHex: colorHex,
          sortOrder: _sortOrder,
        );
        // Actualiza los metadatos; el saldo se ajusta vía la RPC atómica.
        await repo.update(updated);
        final delta = balance - existing.balance;
        if (delta.abs() > 0.0001) {
          await repo.adjustBalance(existing.id, delta);
        }
        if (mounted) {
          Navigator.pop(context,
              AccountEditorResult(isNew: false, accountName: name));
        }
      } else {
        // La cuenta parte de 0.00; si el usuario indica saldo inicial distinto
        // de 0, se registra una transacción especial "Saldo Inicial" (INCOME)
        // que ajusta el balance con la RPC insert_transaction.
        final created = await repo.create(
          name: name,
          balance: 0,
          bank: bank,
          icon: _selectedIcon,
          colorHex: colorHex,
          sortOrder: _sortOrder,
        );
        if (balance > 0) {
          await repo.registerInitialBalance(
            accountId: created.id,
            amount: balance,
          );
        }
        if (mounted) {
          Navigator.pop(context,
              AccountEditorResult(
                isNew: true,
                accountId: created.id,
                accountName: name,
                balance: balance,
              ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(ColorConfig.surfaceAlt),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEdit ? 'Editar cuenta' : 'Nueva cuenta',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(ColorConfig.textPrimary),
                ),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Ingresa el nombre' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bankController,
                decoration: const InputDecoration(
                  labelText: 'Banco / App',
                  hintText: 'Ej: BBVA, Plin, Interbank',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _balanceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Saldo inicial',
                  hintText: 'Ej: 150.00',
                  prefixText: 'S/ ',
                ),
                validator: (v) {
                  final raw = v?.trim() ?? '';
                  if (raw.isEmpty) return 'Ingresa tu saldo inicial';
                  final value = double.tryParse(raw.replaceAll(',', '.'));
                  if (value == null || value < 0) return 'Monto inválido';
                  return null;
                },
              ),

              const SizedBox(height: 20),
              const Text('Ícono',
                  style: TextStyle(color: Color(ColorConfig.textSecondary))),
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: IconCatalog.items.length,
                  itemBuilder: (context, index) {
                    final name = IconCatalog.items.keys.elementAt(index);
                    final icon = IconCatalog.items.values.elementAt(index);
                    final selected = name == _selectedIcon;
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _selectedIcon = name),
                      child: Container(
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(ColorConfig.accent)
                              : const Color(ColorConfig.surfaceAlt),
                          borderRadius: BorderRadius.circular(10),
                          border: selected
                              ? Border.all(color: Colors.white, width: 1.5)
                              : null,
                        ),
                        child: Icon(icon, size: 20, color: Colors.white),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),
              const Text('Color',
                  style: TextStyle(color: Color(ColorConfig.textSecondary))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _palette)
                    GestureDetector(
                      onTap: () => setState(
                          () => _colorController.text = _hexFromColor(c)),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: _colorController.text == _hexFromColor(c)
                              ? Border.all(color: Colors.white, width: 2)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? 'Guardar cambios' : 'Crear cuenta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resultado devuelto por [AccountEditorPanel] al cerrarse.
///
/// Indica si fue una creación o edición y, en creaciones nuevas, si el saldo
/// inicial quedó en 0.00 (para mostrar el banner/modal de bienvenida).
class AccountEditorResult {
  const AccountEditorResult({
    required this.isNew,
    required this.accountName,
    this.accountId,
    this.balance = 0,
  });

  final bool isNew;
  final String accountName;
  final String? accountId;
  final double balance;
}

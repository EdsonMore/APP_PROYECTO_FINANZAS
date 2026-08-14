import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/models/category.dart';
import 'package:saldo_claro/core/models/transaction_type.dart';
import 'package:saldo_claro/features/dashboard/providers/repository_providers.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/icon_catalog.dart';

/// Panel (bottom sheet) para crear/editar una categoría + keywords.
class CategoryEditorPanel extends ConsumerStatefulWidget {
  const CategoryEditorPanel({super.key, this.existing});

  final Category? existing;

  @override
  ConsumerState<CategoryEditorPanel> createState() =>
      _CategoryEditorPanelState();
}

class _CategoryEditorPanelState extends ConsumerState<CategoryEditorPanel> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _keywordsController = TextEditingController();
  final _budgetController = TextEditingController();

  late TransactionType _type;
  late String _selectedIcon;
  String? _colorHex;
  bool _isEdit = false;
  bool _saving = false;

  static const List<Color> _palette = [
    Color(0xFF8E44AD),
    Color(0xFFE91E63),
    Color(0xFFC0392B),
    Color(0xFFE67E22),
    Color(0xFF16A085),
    Color(0xFF2ECC71),
    Color(0xFF3498DB),
    Color(0xFFF39C12),
  ];

  String _hexFromColor(Color c) => (c.toARGB32() & 0xFFFFFF)
      .toRadixString(16)
      .padLeft(6, '0')
      .toUpperCase();

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _isEdit = c != null;
    _nameController = TextEditingController(text: c?.name ?? '');
    _keywordsController.text = c?.keywords.join(', ') ?? '';
    _budgetController.text =
        c?.budget != null ? c!.budget!.toStringAsFixed(2) : '';
    _type = c?.type ?? TransactionType.expense;
    _selectedIcon = c?.icon ?? 'category';
    _colorHex = c?.colorHex;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _keywordsController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  List<String> _parseKeywords() =>
      _keywordsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(categoryRepositoryProvider);
      final keywords = _parseKeywords();
      final budgetText = _budgetController.text.replaceAll(',', '.');
      final budget = double.tryParse(budgetText);

      if (_isEdit) {
        final updated = Category(
          id: widget.existing!.id,
          userId: widget.existing!.userId,
          name: _nameController.text.trim(),
          type: _type,
          icon: _selectedIcon,
          colorHex: _colorHex,
          keywords: keywords,
          budget: budget != null && budget > 0 ? budget : null,
        );
        await repo.update(updated);
      } else {
        await repo.create(
          name: _nameController.text.trim(),
          type: _type,
          icon: _selectedIcon,
          colorHex: _colorHex,
          keywords: keywords,
          budget: budget != null && budget > 0 ? budget : null,
        );
      }
      if (mounted) Navigator.pop(context, true);
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
                _isEdit ? 'Editar categoría' : 'Nueva categoría',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(ColorConfig.textPrimary),
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('Gasto'),
                    icon: Icon(Icons.trending_down),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('Ingreso'),
                    icon: Icon(Icons.trending_up),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Ingresa el nombre' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _keywordsController,
                decoration: const InputDecoration(
                  labelText: 'Keywords / Comercios',
                  hintText: 'cine, restaurante, flores, regalo... (separados por coma)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _budgetController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Presupuesto mensual (opcional)',
                  prefixText: 'S/ ',
                  hintText: 'Ej: 300 para "Enamorada / Pareja"',
                ),
              ),
              const SizedBox(height: 20),
              const Text('Ícono',
                  style: TextStyle(color: Color(ColorConfig.textSecondary))),
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 10,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: IconCatalog.items.length,
                  itemBuilder: (context, index) {
                    final name = IconCatalog.items.keys.elementAt(index);
                    final icon = IconCatalog.items.values.elementAt(index);
                    final selected = name == _selectedIcon;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _selectedIcon = name),
                      child: Container(
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(ColorConfig.accent)
                              : const Color(ColorConfig.surfaceAlt),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, size: 18, color: Colors.white),
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
                      onTap: () =>
                          setState(() => _colorHex = _hexFromColor(c)),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: _colorHex == _hexFromColor(c)
                              ? Border.all(color: Colors.white, width: 2)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? 'Guardar cambios' : 'Crear categoría'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

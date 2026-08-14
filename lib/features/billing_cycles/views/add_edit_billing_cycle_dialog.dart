import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/utils/formatters.dart';
import 'package:saldo_claro/features/billing_cycles/models/billing_cycle_model.dart';

/// Abre el formulario modal para crear o editar un ciclo de facturación.
///
/// Devuelve el [BillingCycle] con los datos ingresados (o `null` si el
/// usuario cancela). En modo edición se conserva el `id` original.
Future<BillingCycle?> showAddEditBillingCycleDialog(
  BuildContext context, {
  BillingCycle? cycle,
}) {
  return showModalBottomSheet<BillingCycle>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(ColorConfig.surface),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AddEditBillingCycleSheet(cycle: cycle),
  );
}

class _AddEditBillingCycleSheet extends ConsumerStatefulWidget {
  const _AddEditBillingCycleSheet({this.cycle});

  final BillingCycle? cycle;

  @override
  ConsumerState<_AddEditBillingCycleSheet> createState() =>
      _AddEditBillingCycleSheetState();
}

class _AddEditBillingCycleSheetState
    extends ConsumerState<_AddEditBillingCycleSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _supplyController;
  final TextEditingController _keywordController = TextEditingController();

  late BillingCategory _category;
  late BillingFrequency _frequency;
  late DateTime _dueDate;
  late List<String> _keywords;
  bool _submitting = false;

  bool get _isEditing => widget.cycle != null;

  @override
  void initState() {
    super.initState();
    final cycle = widget.cycle;
    _titleController = TextEditingController(text: cycle?.title ?? '');
    _amountController = TextEditingController(
      text: cycle != null ? cycle.amount.toStringAsFixed(2) : '',
    );
    _supplyController = TextEditingController(text: cycle?.supplyNumber ?? '');
    _category = cycle?.category ?? BillingCategory.utilityService;
    _frequency = cycle?.frequency ?? BillingFrequency.monthly;
    _dueDate = cycle?.dueDate ?? DateTime.now().add(const Duration(days: 30));
    _keywords = List.of(cycle?.keywords ?? const []);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _supplyController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate.isBefore(now) ? now : _dueDate,
      firstDate: now,
      lastDate: DateTime(now.year + 10),
      helpText: 'Próximo día de vencimiento',
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _pasteSupply() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _supplyController.text = text;
      _supplyController.selection = TextSelection.collapsed(offset: text.length);
    });
  }

  void _addKeyword(String raw) {
    final keyword = raw.trim().toLowerCase();
    if (keyword.isEmpty || _keywords.contains(keyword)) {
      return;
    }
    setState(() => _keywords.add(keyword));
  }

  void _removeKeyword(String keyword) {
    setState(() => _keywords.remove(keyword));
  }

  /// Sugerencias de keywords auto-generadas según el título y la categoría.
  List<String> get _suggestions {
    final title = _titleController.text.trim().toLowerCase();
    final suggestions = <String>[];
    if (title.isNotEmpty) {
      for (final word in title.split(RegExp(r'[\s\-]+'))) {
        if (word.length < 3) {
          continue;
        }
        if (const {
          'el', 'la', 'los', 'las', 'de', 'del', 'para', 'por', 'con', 'pago',
          'pagos', 'servicio', 'servicios', 'recibo', 'mensual', 'nuevo', 'mi',
        }.contains(word)) {
          continue;
        }
        suggestions.add(word);
      }
    }
    // Keywords canónicas por servicio conocido.
    final known = {
      'enosa': ['enosa', 'luz'],
      'distriluz': ['distriluz', 'luz'],
      'sedapal': ['sedapal', 'agua'],
      'grau': ['eps grau', 'agua'],
      'agua': ['agua'],
      'luz': ['luz'],
      'movistar': ['movistar', 'internet'],
      'entel': ['entel', 'internet'],
      'claro': ['claro', 'internet'],
      'netflix': ['netflix'],
      'spotify': ['spotify'],
      'disney': ['disney+', 'disney'],
      'prime': ['prime video', 'amazon'],
      'youtube': ['youtube premium', 'youtube'],
    };
    for (final entry in known.entries) {
      if (title.contains(entry.key)) {
        suggestions.addAll(entry.value);
      }
    }
    return suggestions
        .where((s) => !_keywords.contains(s))
        .take(8)
        .toList();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', '.'));
      final supply = _supplyController.text.trim();
      final base = widget.cycle;
      final result = BillingCycle(
        id: base?.id ?? '',
        userId: base?.userId ?? '',
        title: _titleController.text.trim(),
        category: _category,
        amount: amount,
        dueDate: _dueDate,
        frequency: _frequency,
        supplyNumber: supply.isEmpty ? null : supply,
        keywords: _keywords,
        isAutoPay: base?.isAutoPay ?? false,
        isActive: base?.isActive ?? true,
        status: base?.status ?? BillingStatus.pending,
        createdAt: base?.createdAt ?? DateTime.now(),
        updatedAt: base?.updatedAt ?? DateTime.now(),
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      _showSnack('Verifica los valores ingresados.');
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHandle(),
              const SizedBox(height: 16),
              Text(
                _isEditing ? 'Editar servicio' : 'Nuevo servicio / recibo',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(ColorConfig.textPrimary),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Registra tus servicios recurrentes y SaldoClaro te '
                'recordará los vencimientos.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(ColorConfig.textSecondary),
                ),
              ),
              const SizedBox(height: 20),

              // Categoría
              SegmentedButton<BillingCategory>(
                segments: const [
                  ButtonSegment(
                    value: BillingCategory.utilityService,
                    label: Text('Servicio público'),
                    icon: Icon(Icons.home_work_outlined),
                  ),
                  ButtonSegment(
                    value: BillingCategory.subscription,
                    label: Text('Suscripción'),
                    icon: Icon(Icons.subscriptions_outlined),
                  ),
                ],
                selected: {_category},
                onSelectionChanged: (selection) {
                  setState(() => _category = selection.first);
                },
              ),
              const SizedBox(height: 16),

              // Nombre
              TextFormField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Ej: ENOSA - Luz, EPS Grau, Netflix',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Ingresa el nombre del servicio';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),

              // Monto
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto estimado',
                  prefixText: 'S/ ',
                  hintText: 'Ej: 85.00',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingresa el monto';
                  final amount = double.tryParse(v.replaceAll(',', '.'));
                  if (amount == null || amount <= 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Fecha de vencimiento
              InkWell(
                onTap: _pickDueDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Próximo día de vencimiento',
                    prefixIcon: Icon(Icons.event),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        Formatters.date(_dueDate),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(ColorConfig.textPrimary),
                        ),
                      ),
                      const Icon(
                        Icons.calendar_month,
                        size: 18,
                        color: Color(ColorConfig.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Frecuencia
              DropdownButtonFormField<BillingFrequency>(
                initialValue: _frequency,
                decoration: const InputDecoration(
                  labelText: 'Frecuencia',
                  prefixIcon: Icon(Icons.autorenew),
                ),
                items: [
                  for (final f in BillingFrequency.values)
                    DropdownMenuItem(value: f, child: Text(f.label)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _frequency = value);
                },
              ),
              const SizedBox(height: 12),

              // Número de suministro
              TextFormField(
                controller: _supplyController,
                decoration: InputDecoration(
                  labelText: 'Número de cliente / suministro (opcional)',
                  prefixIcon: const Icon(Icons.pin_outlined),
                  suffixIcon: IconButton(
                    tooltip: 'Pegar del portapapeles',
                    icon: const Icon(Icons.content_paste),
                    onPressed: _pasteSupply,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Palabras clave (Auto-Match)
              Text(
                'Palabras clave (Auto-Match)',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(ColorConfig.textPrimary),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sirven para detectar tu pago automáticamente desde las '
                'notificaciones. Ej: "enosa", "luz", "netflix".',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color(ColorConfig.textSecondary),
                ),
              ),
              const SizedBox(height: 10),
              if (_keywords.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final keyword in _keywords)
                      InputChip(
                        label: Text(keyword),
                        onDeleted: () => _removeKeyword(keyword),
                        backgroundColor: const Color(ColorConfig.surfaceAlt),
                        side: BorderSide.none,
                        deleteIconColor: const Color(ColorConfig.textSecondary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (_suggestions.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final suggestion in _suggestions)
                      ActionChip(
                        label: Text('+ $suggestion'),
                        onPressed: () => _addKeyword(suggestion),
                        backgroundColor: const Color(ColorConfig.accent)
                            .withValues(alpha: 0.2),
                        side: BorderSide.none,
                        labelStyle: const TextStyle(
                          fontSize: 12,
                          color: Color(ColorConfig.textPrimary),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _keywordController,
                textInputAction: TextInputAction.done,
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    _addKeyword(value);
                    _keywordController.clear();
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Escribe una palabra clave y presiona Enter…',
                  prefixIcon: const Icon(Icons.add_chart),
                  suffixIcon: IconButton(
                    tooltip: 'Agregar',
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      if (_keywordController.text.trim().isNotEmpty) {
                        _addKeyword(_keywordController.text);
                        _keywordController.clear();
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEditing ? 'Guardar cambios' : 'Guardar servicio'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(ColorConfig.surfaceAlt),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

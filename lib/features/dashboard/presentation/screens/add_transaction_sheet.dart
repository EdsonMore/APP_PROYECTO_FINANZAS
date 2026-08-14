import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/models/account.dart';
import 'package:saldo_claro/core/models/category.dart';
import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/models/transaction_type.dart';
import 'package:saldo_claro/features/dashboard/providers/category_providers.dart';
import 'package:saldo_claro/features/dashboard/providers/dashboard_providers.dart';
import 'package:saldo_claro/features/dashboard/providers/repository_providers.dart';

/// Modal para registrar una transacción de forma manual.
class AddTransactionSheet extends ConsumerStatefulWidget {
  const AddTransactionSheet({super.key});

  @override
  ConsumerState<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  Account? _selectedAccount;
  TransactionType _type = TransactionType.expense;
  Category? _selectedCategory;
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccount == null) {
      _showSnack('Selecciona una cuenta');
      return;
    }
    if (_selectedCategory == null) {
      _showSnack('Selecciona una categoría');
      return;
    }

    setState(() => _submitting = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', '.'));
      await ref.read(transactionRepositoryProvider).insert(
            accountId: _selectedAccount!.id,
            amount: amount,
            type: _type,
            categoryId: _selectedCategory!.id,
            rawText: _descriptionController.text.trim().isEmpty
                ? 'Movimiento manual'
                : _descriptionController.text.trim(),
            merchantOrPerson: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            sourceApp: _selectedAccount!.name,
            source: TransactionSource.manual,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Movimiento registrado')),
        );
      }
    } catch (e) {
      _showSnack('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesByTypeProvider(_type));

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
              _buildHandle(),
              const SizedBox(height: 16),
              Text(
                'Agregar movimiento',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(ColorConfig.textPrimary),
                ),
              ),
              const SizedBox(height: 20),

              // Tipo: Gasto / Ingreso
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
                onSelectionChanged: (selection) {
                  setState(() {
                    _type = selection.first;
                    _selectedCategory = null;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Cuenta
              accountsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (accounts) => DropdownButtonFormField<Account>(
                  initialValue: _selectedAccount,
                  decoration: const InputDecoration(labelText: 'Cuenta'),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(value: a, child: Text(a.name)),
                  ],
                  onChanged: (value) => setState(() => _selectedAccount = value),
                ),
              ),
              const SizedBox(height: 12),

              // Monto
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  prefixText: 'S/ ',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingresa el monto';
                  final amount = double.tryParse(v.replaceAll(',', '.'));
                  if (amount == null || amount <= 0) return 'Monto inválido';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Categoría
              categoriesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (categories) => DropdownButtonFormField<Category>(
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(value: c, child: Text(c.name)),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedCategory = value),
                ),
              ),
              const SizedBox(height: 12),

              // Descripción / comercio
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descripción (persona o comercio)',
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
                    : const Text('Guardar movimiento'),
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

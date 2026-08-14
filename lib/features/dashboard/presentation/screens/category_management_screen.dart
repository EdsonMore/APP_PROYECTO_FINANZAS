import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/models/category.dart';
import 'package:saldo_claro/core/models/transaction_type.dart';
import 'package:saldo_claro/features/dashboard/providers/category_providers.dart';
import 'package:saldo_claro/features/dashboard/providers/repository_providers.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/category_editor_panel.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/icon_catalog.dart';

/// Pantalla de Gestión de Categorías (añadir, editar, eliminar, keywords).
class CategoryManagementScreen extends ConsumerStatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  ConsumerState<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState
    extends ConsumerState<CategoryManagementScreen> {
  Future<void> _openEditor({Category? category}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(ColorConfig.surface),
      builder: (_) => CategoryEditorPanel(existing: category),
    );
    if (result == true) {
      ref.invalidate(categoriesProvider);
    }
  }

  Future<void> _delete(Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar categoría?'),
        content: Text('Se eliminará "${category.name}".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(categoryRepositoryProvider).delete(category.id);
      ref.invalidate(categoriesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva categoría'),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (categories) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: categories.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final cat = categories[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(cat.resolvedColor),
                  child: Icon(IconCatalog.iconFor(cat.icon), color: Colors.white),
                ),
                title: Text(cat.name),
                subtitle: Text(
                  cat.keywords.isNotEmpty
                      ? 'Keywords: ${cat.keywords.take(3).join(', ')}'
                      : cat.type.label,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _openEditor(category: cat),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Color(ColorConfig.danger)),
                      onPressed: () => _delete(cat),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

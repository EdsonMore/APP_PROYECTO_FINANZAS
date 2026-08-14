import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/models/transaction.dart';
import '../../../../core/models/transaction_type.dart';
import '../../providers/dashboard_providers.dart';
import '../widgets/transaction_tile.dart';

/// Pantalla completa "Todos los movimientos".
///
/// Incluye:
/// - Búsqueda en tiempo real por persona/comercio, categoría, app y texto.
/// - Chips de filtro rápido por fecha (Hoy / Esta Semana / Este Mes / Rango).
/// - Filtro por tipo (Todos / Ingresos / Gastos).
/// - Scroll infinito: el ListView se renderiza por bloques para no saturar la
///   UI con cientos de transacciones.
class TransactionsListView extends ConsumerStatefulWidget {
  const TransactionsListView({super.key});

  @override
  ConsumerState<TransactionsListView> createState() =>
      _TransactionsListViewState();
}

class _TransactionsListViewState extends ConsumerState<TransactionsListView> {
  static const int _pageSize = 40;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  _DateFilter _dateFilter = _DateFilter.all;
  DateTimeRange? _customRange;
  TransactionType? _typeFilter;
  int _visibleCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final remaining = _filteredLength - _visibleCount;
      if (remaining > 0 && mounted) {
        setState(() {
          _visibleCount += math.min(_pageSize, remaining);
        });
      }
    }
  }

  void _resetPagination() {
    setState(() => _visibleCount = _pageSize);
  }

  int _filteredLength = 0;
  List<Transaction> _applyFilters(List<Transaction> all) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = all.where((t) {
      final matchesQuery = query.isEmpty ||
          (t.merchantOrPerson?.toLowerCase().contains(query) ?? false) ||
          (t.categoryName?.toLowerCase().contains(query) ?? false) ||
          t.sourceApp.toLowerCase().contains(query) ||
          t.rawText.toLowerCase().contains(query);
      if (!matchesQuery) return false;

      if (_typeFilter != null && t.isIncome != _typeFilter!.isIncome) {
        return false;
      }
      return _inDateRange(t.createdAt);
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _filteredLength = filtered.length;
    return filtered;
  }

  bool _inDateRange(DateTime date) {
    final now = DateTime.now();
    switch (_dateFilter) {
      case _DateFilter.all:
        return true;
      case _DateFilter.today:
        final today = DateTime(now.year, now.month, now.day);
        final that = DateTime(date.year, date.month, date.day);
        return that == today;
      case _DateFilter.week:
        final start = now.subtract(Duration(days: now.weekday - 1));
        final startDay = DateTime(start.year, start.month, start.day);
        final end = startDay.add(const Duration(days: 7));
        return !date.isBefore(startDay) && date.isBefore(end);
      case _DateFilter.month:
        return date.year == now.year && date.month == now.month;
      case _DateFilter.custom:
        if (_customRange == null) return true;
        return !date.isBefore(_customRange!.start) &&
            !date.isAfter(_customRange!.end);
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: _customRange,
      helpText: 'Rango de fechas',
    );
    if (range != null && mounted) {
      setState(() {
        _dateFilter = _DateFilter.custom;
        _customRange = DateTimeRange(
          start: DateTime(range.start.year, range.start.month, range.start.day),
          end: DateTime(range.end.year, range.end.month, range.end.day, 23, 59),
        );
        _visibleCount = _pageSize;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(allTransactionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Todos los movimientos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _resetPagination(),
              decoration: InputDecoration(
                hintText: 'Buscar persona, comercio o categoría…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _resetPagination();
                        },
                      ),
                filled: true,
                fillColor: const Color(ColorConfig.surfaceAlt),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          _buildFilterBar(),
          const SizedBox(height: 4),
          Expanded(
            child: transactionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error cargando: $e')),
              data: (all) {
                final filtered = _applyFilters(all);
                if (filtered.isEmpty) {
                  return _EmptyState(
                    hasSearch: _searchController.text.trim().isNotEmpty ||
                        _dateFilter != _DateFilter.all ||
                        _typeFilter != null,
                  );
                }
                final visible = filtered
                    .take(_visibleCount)
                    .toList();
                final hasMore = filtered.length > _visibleCount;

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: visible.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= visible.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    return TransactionTile(transaction: visible[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final option in _DateFilter.values) ...[
            _chip(
              label: option.label,
              selected: _dateFilter == option,
              onTap: () {
                setState(() {
                  _dateFilter = option;
                  _visibleCount = _pageSize;
                });
                if (option == _DateFilter.custom) {
                  _pickCustomRange();
                }
              },
            ),
            const SizedBox(width: 8),
          ],
          _chip(
            label: 'Ingresos',
            selected: _typeFilter == TransactionType.income,
            onTap: () => setState(() {
              _typeFilter =
                  _typeFilter == TransactionType.income ? null : TransactionType.income;
              _visibleCount = _pageSize;
            }),
          ),
          const SizedBox(width: 8),
          _chip(
            label: 'Gastos',
            selected: _typeFilter == TransactionType.expense,
            onTap: () => setState(() {
              _typeFilter = _typeFilter == TransactionType.expense
                  ? null
                  : TransactionType.expense;
              _visibleCount = _pageSize;
            }),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: Color(
          selected ? ColorConfig.textPrimary : ColorConfig.textSecondary,
        ),
      ),
      selectedColor: const Color(ColorConfig.accent),
      backgroundColor: const Color(ColorConfig.surfaceAlt),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}

enum _DateFilter {
  all('Todos'),
  today('Hoy'),
  week('Esta Semana'),
  month('Este Mes'),
  custom('Rango');

  const _DateFilter(this.label);

  final String label;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasSearch});

  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              hasSearch
                  ? 'No hay movimientos que coincidan con tu búsqueda.'
                  : 'Todavía no hay movimientos registrados.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(ColorConfig.textSecondary),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
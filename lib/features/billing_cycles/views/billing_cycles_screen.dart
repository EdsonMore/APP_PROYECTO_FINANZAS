import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/features/billing_cycles/models/billing_cycle_model.dart';
import 'package:saldo_claro/features/billing_cycles/providers/billing_cycles_provider.dart';
import 'package:saldo_claro/features/billing_cycles/views/add_edit_billing_cycle_dialog.dart';
import 'package:saldo_claro/features/billing_cycles/widgets/billing_cycle_card.dart';

/// Pantalla de Ciclos de Facturación y Servicios.
///
/// - Pestañas: Servicios Manuales / Suscripciones Automáticas / Pausados.
/// - FAB para crear un nuevo servicio/recibo.
/// - CRUD completo con menú de opciones por tarjeta.
class BillingCyclesScreen extends ConsumerStatefulWidget {
  const BillingCyclesScreen({super.key});

  @override
  ConsumerState<BillingCyclesScreen> createState() => _BillingCyclesScreenState();
}

class _BillingCyclesScreenState extends ConsumerState<BillingCyclesScreen> {
  static const _tabs = ['Servicios Manuales', 'Suscripciones', 'Pausados'];

  int _tabIndex = 0;
  String? _busyId;

  @override
  Widget build(BuildContext context) {
    final cyclesAsync = ref.watch(billingCyclesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ciclos de Facturación'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: () => refreshBillingCycles(ref),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: cyclesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                message: 'No se pudieron cargar tus servicios: $e',
              ),
              data: (cycles) {
                final visible = _filter(cycles);
                if (visible.isEmpty) {
                  return _EmptyState(
                    isPausedTab: _tabIndex == 2,
                    hasAny: cycles.isNotEmpty,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final cycle = visible[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BillingCycleCard(
                        cycle: cycle,
                        isBusy: _busyId == cycle.id,
                        onEdit: () => _editCycle(cycle),
                        onMarkPaid: () => _markPaid(cycle),
                        onTogglePause: () => _togglePause(cycle),
                        onDelete: () => _confirmDelete(cycle),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCycle,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Servicio / Recibo'),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(ColorConfig.surfaceAlt),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tabIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  decoration: BoxDecoration(
                    color: _tabIndex == i
                        ? const Color(ColorConfig.accent)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _tabs[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight:
                          _tabIndex == i ? FontWeight.w700 : FontWeight.w500,
                      color: _tabIndex == i
                          ? const Color(ColorConfig.textPrimary)
                          : const Color(ColorConfig.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
            if (i < _tabs.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  /// Filtra los ciclos según la pestaña activa.
  List<BillingCycle> _filter(List<BillingCycle> cycles) {
    switch (_tabIndex) {
      case 0:
        return cycles
            .where((c) => c.isActive && c.category == BillingCategory.utilityService)
            .toList();
      case 1:
        return cycles
            .where((c) => c.isActive && c.category == BillingCategory.subscription)
            .toList();
      default:
        return cycles.where((c) => !c.isActive).toList();
    }
  }

  Future<void> _addCycle() async {
    final result = await showAddEditBillingCycleDialog(context);
    if (result == null || !mounted) return;

    try {
      final created = await ref
          .read(billingCycleRepositoryProvider)
          .insert(
            title: result.title,
            category: result.category,
            amount: result.amount,
            dueDate: result.dueDate,
            frequency: result.frequency,
            supplyNumber: result.supplyNumber,
            keywords: result.keywords,
            isAutoPay: result.isAutoPay,
          );
      await ref
          .read(billingNotificationSchedulerProvider)
          .scheduleForCycle(created);
      refreshBillingCycles(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Servicio registrado. Recibirás recordatorios.'),
            backgroundColor: Color(ColorConfig.success),
          ),
        );
      }
    } catch (e) {
      _showError('Error al guardar: $e');
    }
  }

  Future<void> _editCycle(BillingCycle cycle) async {
    final result = await showAddEditBillingCycleDialog(context, cycle: cycle);
    if (result == null || !mounted) return;

    setState(() => _busyId = cycle.id);
    try {
      final scheduler = ref.read(billingNotificationSchedulerProvider);
      // Cancela las alarmas viejas y reprograma según los nuevos datos.
      await scheduler.cancelForCycle(cycle.id);
      await ref.read(billingCycleRepositoryProvider).update(result);
      await scheduler.scheduleForCycle(result);
      refreshBillingCycles(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Servicio actualizado')),
        );
      }
    } catch (e) {
      _showError('Error al actualizar: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _markPaid(BillingCycle cycle) async {
    setState(() => _busyId = cycle.id);
    try {
      final scheduler = ref.read(billingNotificationSchedulerProvider);
      await scheduler.cancelForCycle(cycle.id);
      final next =
          await ref.read(billingCycleRepositoryProvider).settleAndAdvance(cycle.id);
      if (next != null) {
        await scheduler.scheduleForCycle(next);
      }
      refreshBillingCycles(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🎉 ${cycle.title} marcado como pagado. '
              'Próximo vencimiento: ${_formatDate(next?.dueDate ?? cycle.nextDueDate())}',
            ),
            backgroundColor: const Color(ColorConfig.success),
          ),
        );
      }
    } catch (e) {
      _showError('Error al marcar como pagado: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _togglePause(BillingCycle cycle) async {
    setState(() => _busyId = cycle.id);
    try {
      final scheduler = ref.read(billingNotificationSchedulerProvider);
      final nextActive = !cycle.isActive;
      await ref.read(billingCycleRepositoryProvider).setActive(cycle.id, nextActive);
      if (nextActive) {
        await scheduler.scheduleForCycle(cycle.copyWith(isActive: true));
      } else {
        await scheduler.cancelForCycle(cycle.id);
      }
      refreshBillingCycles(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nextActive
                  ? '▶️ ${cycle.title} reanudado'
                  : '⏸️ ${cycle.title} pausado. Recordatorios detenidos.',
            ),
          ),
        );
      }
    } catch (e) {
      _showError('Error al cambiar el estado: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _confirmDelete(BillingCycle cycle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Eliminar ${cycle.title}?'),
        content: const Text(
          'Se cancelarán los recordatorios programados. Esta acción no '
          'se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(ColorConfig.danger),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = cycle.id);
    try {
      await ref
          .read(billingNotificationSchedulerProvider)
          .cancelForCycle(cycle.id);
      await ref.read(billingCycleRepositoryProvider).delete(cycle.id);
      refreshBillingCycles(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🗑️ Servicio eliminado')),
        );
      }
    } catch (e) {
      _showError('Error al eliminar: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ $message'),
        backgroundColor: const Color(ColorConfig.danger),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isPausedTab, required this.hasAny});

  final bool isPausedTab;
  final bool hasAny;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = isPausedTab
        ? (
            Icons.pause_circle_outline,
            'Nada pausado',
            'Los servicios que pauses aparecerán aquí sin borrarlos.',
          )
        : (
            Icons.receipt_long_outlined,
            'Aún no tienes servicios aquí',
            hasAny
                ? 'Cambia de pestaña o agrega uno nuevo.'
                : 'Registra tu luz, agua, internet o suscripciones y '
                    'SaldoClaro te avisará antes de cada vencimiento.',
          );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Colors.white24),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(ColorConfig.textPrimary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(ColorConfig.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(ColorConfig.danger)),
        ),
      ),
    );
  }
}

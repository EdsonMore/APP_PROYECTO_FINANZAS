import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/utils/formatters.dart';
import 'package:saldo_claro/features/billing_cycles/models/billing_cycle_model.dart';

/// Tarjeta de un ciclo de facturación/servicio recurrente.
///
/// Muestra el ícono dinámico, monto, próxima fecha, número de suministro
/// (con copiado de 1-tap), badge de urgencia y acciones rápidas.
class BillingCycleCard extends ConsumerStatefulWidget {
  const BillingCycleCard({
    super.key,
    required this.cycle,
    required this.isBusy,
    required this.onEdit,
    required this.onMarkPaid,
    required this.onTogglePause,
    required this.onDelete,
  });

  final BillingCycle cycle;
  final bool isBusy;
  final VoidCallback onEdit;
  final VoidCallback onMarkPaid;
  final VoidCallback onTogglePause;
  final VoidCallback onDelete;

  @override
  ConsumerState<BillingCycleCard> createState() => _BillingCycleCardState();
}

class _BillingCycleCardState extends ConsumerState<BillingCycleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.cycle.urgency == BillingUrgency.urgent &&
        widget.cycle.status != BillingStatus.paid) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  bool get _isPulsing =>
      widget.cycle.urgency == BillingUrgency.urgent &&
      widget.cycle.status != BillingStatus.paid;

  Future<void> _copySupplyNumber() async {
    final supply = widget.cycle.supplyNumber?.trim() ?? '';
    if (supply.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: supply));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📋 Número de suministro copiado al portapapeles'),
        backgroundColor: Color(ColorConfig.accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cycle = widget.cycle;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final shadow = _isPulsing
            ? [
                BoxShadow(
                  color: const Color(ColorConfig.danger)
                      .withValues(alpha: 0.35 + 0.25 * _pulseController.value),
                  blurRadius: 10 + 14 * _pulseController.value,
                  spreadRadius: 1 + 2 * _pulseController.value,
                ),
              ]
            : const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ];

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(ColorConfig.surface),
            borderRadius: BorderRadius.circular(16),
            boxShadow: shadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(cycle),
                const SizedBox(height: 14),
                _buildAmountRow(cycle),
                const SizedBox(height: 12),
                _buildDueRow(cycle),
                if (cycle.supplyNumber?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 10),
                  _buildSupplyRow(cycle),
                ],
                const SizedBox(height: 12),
                const Divider(
                  height: 1,
                  color: Color(ColorConfig.surfaceAlt),
                ),
                const SizedBox(height: 8),
                _buildActionsRow(cycle),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BillingCycle cycle) {
    final isPaid = cycle.status == BillingStatus.paid;
    final urgency = isPaid ? BillingUrgency.ok : cycle.urgency;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _urgencyColor(urgency).withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              cycle.emoji,
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cycle.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(ColorConfig.textPrimary),
                ),
              ),
              const SizedBox(height: 4),
              _buildUrgencyBadge(urgency, isPaid),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUrgencyBadge(BillingUrgency urgency, bool isPaid) {
    final (label, color, icon) = switch (urgency) {
      BillingUrgency.urgent => isPaid
          ? ('Pagado', const Color(ColorConfig.success), '✓')
          : (cycle.daysUntilDue < 0
              ? 'Vencido'
              : (cycle.daysUntilDue == 0 ? '¡Vence hoy!' : '¡Vence mañana!'),
              const Color(ColorConfig.danger),
              '🔴'),
      BillingUrgency.warning => (
          'Próximo a vencer (${_daysLabel(cycle)})',
          const Color(0xFFF39C12),
          '🟡'
        ),
      BillingUrgency.ok => isPaid
          ? ('Pagado', const Color(ColorConfig.success), '✓')
          : ('En plazo', const Color(ColorConfig.success), '🟢'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountRow(BillingCycle cycle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          Formatters.currency(cycle.amount),
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: const Color(ColorConfig.textPrimary),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            cycle.category.label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(ColorConfig.textSecondary),
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(ColorConfig.accent).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.autorenew,
                size: 13,
                color: Color(ColorConfig.textPrimary),
              ),
              const SizedBox(width: 4),
              Text(
                cycle.frequency.label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(ColorConfig.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDueRow(BillingCycle cycle) {
    final overdue = cycle.daysUntilDue < 0;
    final daysLabel = overdue
        ? 'Vencido hace ${-cycle.daysUntilDue} día${-cycle.daysUntilDue == 1 ? '' : 's'}'
        : _daysLabel(cycle);
    final color = overdue
        ? const Color(ColorConfig.danger)
        : const Color(ColorConfig.textSecondary);

    return Row(
      children: [
        const Icon(
          Icons.event,
          size: 15,
          color: Color(ColorConfig.textSecondary),
        ),
        const SizedBox(width: 6),
        Text(
          'Vence el ${Formatters.date(cycle.dueDate)}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(ColorConfig.textPrimary),
          ),
        ),
        const Spacer(),
        Text(
          daysLabel,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }

  Widget _buildSupplyRow(BillingCycle cycle) {
    final supply = cycle.supplyNumber!.trim();
    return InkWell(
      onTap: _copySupplyNumber,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(ColorConfig.surfaceAlt),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.content_copy,
              size: 14,
              color: Color(ColorConfig.textSecondary),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Nº Suministro: $supply',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(ColorConfig.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsRow(BillingCycle cycle) {
    final isPaid = cycle.status == BillingStatus.paid;
    return Row(
      children: [
        Expanded(
          child: widget.isBusy
              ? const SizedBox(
                  height: 36,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : FilledButton.icon(
                  onPressed: isPaid ? null : widget.onMarkPaid,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(isPaid ? 'Pagado ✓' : 'Marcar como Pagado'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(36),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Opciones',
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          color: const Color(ColorConfig.surface),
          onSelected: (value) {
            switch (value) {
              case 'edit':
                widget.onEdit();
              case 'copy':
                _copySupplyNumber();
              case 'pause':
                widget.onTogglePause();
              case 'paid':
                widget.onMarkPaid();
              case 'delete':
                widget.onDelete();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_outlined),
                title: Text('Editar'),
              ),
            ),
            if (cycle.supplyNumber?.trim().isNotEmpty ?? false)
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.content_copy),
                  title: Text('Copiar Nº de Suministro'),
                ),
              ),
            PopupMenuItem(
              value: 'pause',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  cycle.isActive
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                ),
                title: Text(cycle.isActive ? 'Pausar' : 'Reanudar'),
              ),
            ),
            PopupMenuItem(
              value: 'paid',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline),
                title: Text(isPaid ? 'Pagado' : 'Marcar como Pagado'),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline, color: Color(ColorConfig.danger)),
                title: Text(
                  'Eliminar',
                  style: TextStyle(color: Color(ColorConfig.danger)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  BillingCycle get cycle => widget.cycle;

  String _daysLabel(BillingCycle cycle) {
    final days = cycle.daysUntilDue;
    if (days <= 0) return '¡Vence hoy!';
    if (days == 1) return 'Vence mañana';
    if (days == 2) return 'En 2 días';
    return 'En $days días';
  }

  Color _urgencyColor(BillingUrgency urgency) {
    return switch (urgency) {
      BillingUrgency.urgent => const Color(ColorConfig.danger),
      BillingUrgency.warning => const Color(0xFFF39C12),
      BillingUrgency.ok => const Color(ColorConfig.success),
    };
  }
}

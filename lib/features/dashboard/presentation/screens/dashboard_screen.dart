import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/permissions/notification_permission_service.dart';
import 'package:saldo_claro/features/auth/presentation/providers/auth_provider.dart';
import 'package:saldo_claro/features/billing_cycles/views/billing_cycles_screen.dart';
import 'package:saldo_claro/features/billing_cycles/widgets/dashboard_upcoming_bills_widget.dart';
import 'package:saldo_claro/features/capture/providers/notification_capture_provider.dart';
import 'package:saldo_claro/features/capture/service/notification_capture_service.dart';
import 'package:saldo_claro/features/chat/presentation/screens/cfo_chat_screen.dart';
import 'package:saldo_claro/features/couple/presentation/widgets/couple_dashboard_card.dart';
import 'package:saldo_claro/features/dashboard/presentation/screens/add_transaction_sheet.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/budget_dialog.dart';
import 'package:saldo_claro/features/dashboard/providers/dashboard_providers.dart';
import 'package:saldo_claro/features/dashboard/presentation/screens/account_management_screen.dart';
import 'package:saldo_claro/features/dashboard/presentation/screens/app_recognition_screen.dart';
import 'package:saldo_claro/features/dashboard/presentation/screens/category_management_screen.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/insights_section.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/account_card.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/balance_overview_card.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/expenses_chart.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/initial_balance_banner.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/transaction_tile.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/transactions_list_view.dart';
import 'package:saldo_claro/features/gamification/presentation/widgets/achievements_section.dart';
import 'package:saldo_claro/features/profile/presentation/screens/profile_screen.dart';
import 'package:saldo_claro/features/reports/presentation/export_sheet.dart';

/// Pantalla principal: balances, gráfico y movimientos recientes.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  /// Filtro activo de la lista de movimientos recientes.
  _MovementFilter _movementFilter = _MovementFilter.all;

  /// Máximo de movimientos mostrados en el dashboard.
  static const int _recentLimit = 10;

  StreamSubscription<CaptureResult>? _captureSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCapture();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureSubscription?.cancel();
    _captureSubscription = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refreshDashboard(ref);
    }
  }

  void _startCapture() {
    final service = ref.read(notificationCaptureServiceProvider);
    // Se suscribe UNA vez (el dashboard se mantiene montado durante toda la
    // sesión; AppLockGate no lo destruye al bloquear/desbloquear).
    _captureSubscription ??= service.results.listen(_onCaptureResult);
    service.start();

    // Re-enlaza el listener nativo con el sistema por si quedó desvinculado.
    NotificationPermissionService.instance.requestRebind();
  }

  /// Muestra el resultado de cada intento de captura para que el usuario
  /// SIEMPRE sepa qué pasó con la notificación (capturada/ignorada/fallida).
  void _onCaptureResult(CaptureResult result) {
    if (!mounted) return;

    if (result.isSuccess) {
      refreshDashboard(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Movimiento capturado automáticamente'),
          backgroundColor: Color(ColorConfig.success),
        ),
      );
      return;
    }

    if (result.reason != null) {
      // Ignorada (no se pudo interpretar o no hay cuenta mapeada).
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ℹ️ Notificación no registrada: ${result.reason}'),
          backgroundColor: const Color(0xFF8E6A00),
        ),
      );
      return;
    }

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al registrar: ${result.error}'),
          backgroundColor: const Color(ColorConfig.danger),
        ),
      );
    }
  }

  Future<void> _openAddTransaction() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(ColorConfig.surface),
      builder: (_) => const AddTransactionSheet(),
    );
    refreshDashboard(ref);
  }

  /// Aplica el filtro de tipo y limita a los [_recentLimit] movimientos más
  /// recientes por fecha (el repositorio ya los devuelve ordenados por fecha).
  List<Transaction> _applyFilter(List<Transaction> transactions) {
    final filtered = switch (_movementFilter) {
      _MovementFilter.all => transactions,
      _MovementFilter.income =>
        transactions.where((t) => t.isIncome).toList(),
      _MovementFilter.expense =>
        transactions.where((t) => !t.isIncome).toList(),
    };
    return filtered.take(_recentLimit).toList();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final transactionsAsync = ref.watch(recentTransactionsProvider);
    final expensesAsync = ref.watch(expensesByCategoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppConfig.appName,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Perfil',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          _ManagementMenu(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshDashboard(ref),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- Balance total ---
            accountsAsync.when(
              loading: () => const _Skeleton(height: 130),
              error: (e, _) => _ErrorCard(
                message: 'No se pudieron cargar tus cuentas: $e',
              ),
              data: (accounts) => Column(
                children: [
                  BalanceOverviewCard(accounts: accounts),
                  InitialBalanceBanner(
                    accounts: accounts,
                    hasTransactions:
                        transactionsAsync.value?.isNotEmpty ?? false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // --- Próximos vencimientos de servicios ---
            const DashboardUpcomingBillsWidget(),

            // --- Cuentas individuales ---
            Text(
              'Tus cuentas',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(ColorConfig.textPrimary),
              ),
            ),
            const SizedBox(height: 12),
            accountsAsync.when(
              loading: () => const _Skeleton(height: 120),
              error: (e, _) => _ErrorCard(
                message: 'Error cargando cuentas: $e',
              ),
              data: (accounts) => GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.25,
                children: [
                  for (final account in accounts) AccountCard(account: account),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // --- Especial Pareja / Enamorada (VIP) ---
            const CoupleDashboardCard(),
            const SizedBox(height: 24),

            // --- Gráfico de gastos ---
            Text(
              'Gastos por categoría',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(ColorConfig.textPrimary),
              ),
            ),
            const SizedBox(height: 12),
            expensesAsync.when(
              loading: () => const _Skeleton(height: 220),
              error: (e, _) => _ErrorCard(
                message: 'Error en el gráfico: $e',
              ),
              data: (data) => ExpensesChart(data: data),
            ),
            const SizedBox(height: 24),

            // --- Insights de IA ---
            const InsightsSection(),
            const SizedBox(height: 24),

            // --- Logros de gamificación ---
            const AchievementsSection(),
            const SizedBox(height: 24),

            // --- Movimientos recientes ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Movimientos recientes',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(ColorConfig.textPrimary),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TransactionsListView(),
                          ),
                        );
                      },
                      child: const Text('Ver todos'),
                    ),
                    TextButton(
                      onPressed: _openAddTransaction,
                      child: const Text('+ Agregar'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            transactionsAsync.when(
              loading: () => const _Skeleton(height: 200),
              error: (e, _) =>
                  _ErrorCard(message: 'Error cargando movimientos: $e'),
              data: (transactions) {
                if (transactions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Todavía no hay movimientos.\n'
                        'Concede el permiso de notificaciones y tus '
                        'movimientos aparecerán aquí.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(ColorConfig.textSecondary),
                          height: 1.4,
                        ),
                      ),
                    ),
                  );
                }
                final visible = _applyFilter(transactions);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MovementFilterBar(
                      selected: _movementFilter,
                      onChanged: (value) {
                        setState(() => _movementFilter = value);
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mostrando los últimos $_recentLimit por fecha',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(ColorConfig.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (visible.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No hay movimientos con este filtro.',
                            style: TextStyle(
                              color: Color(ColorConfig.textSecondary),
                            ),
                          ),
                        ),
                      )
                    else
                      Card(
                        child: Column(
                          children: [
                            for (final Transaction t in visible)
                              TransactionTile(transaction: t),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddTransaction,
        icon: const Icon(Icons.add),
        label: const Text('Movimiento'),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(ColorConfig.surfaceAlt),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE74C3C).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFE74C3C)),
      ),
    );
  }
}

/// Menú del dashboard: micro-acciones (chat IA, presupuesto, exportación)
/// y gestión (cuentas, categorías, apps).
class _ManagementMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.tune),
      tooltip: 'Menú',
      onSelected: (value) {
        switch (value) {
          case 'chat':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CfoChatScreen(),
              ),
            );
          case 'budget':
            showBudgetDialog(context, ref);
          case 'export':
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: const Color(ColorConfig.surface),
              builder: (_) => const ExportSheet(),
            );
          case 'accounts':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AccountManagementScreen(),
              ),
            );
          case 'categories':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CategoryManagementScreen(),
              ),
            );
          case 'apps':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AppRecognitionScreen(),
              ),
            );
          case 'bills':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const BillingCyclesScreen(),
              ),
            );
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'chat',
          child: ListTile(
            leading: Icon(Icons.auto_awesome),
            title: Text('CFO de bolsillo (Chat IA)'),
          ),
        ),
        PopupMenuItem(
          value: 'bills',
          child: ListTile(
            leading: Icon(Icons.receipt_long_outlined),
            title: Text('Ciclos de Facturación y Servicios'),
          ),
        ),
        PopupMenuItem(
          value: 'budget',
          child: ListTile(
            leading: Icon(Icons.savings_outlined),
            title: Text('Presupuesto mensual'),
          ),
        ),
        PopupMenuItem(
          value: 'export',
          child: ListTile(
            leading: Icon(Icons.ios_share),
            title: Text('Exportar reporte (PDF / Excel)'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'accounts',
          child: ListTile(
            leading: Icon(Icons.manage_accounts),
            title: Text('Gestión de Cuentas'),
          ),
        ),
        PopupMenuItem(
          value: 'categories',
          child: ListTile(
            leading: Icon(Icons.category_outlined),
            title: Text('Gestión de Categorías'),
          ),
        ),
        PopupMenuItem(
          value: 'apps',
          child: ListTile(
            leading: Icon(Icons.apps),
            title: Text('Reconocimiento de Apps'),
          ),
        ),
      ],
    );
  }
}

/// Filtro de tipo aplicado a la lista de movimientos recientes.
enum _MovementFilter {
  all('Todos'),
  income('Ingresos'),
  expense('Gastos');

  const _MovementFilter(this.label);

  final String label;
}

/// Barra de chips para filtrar los movimientos por tipo.
class _MovementFilterBar extends StatelessWidget {
  const _MovementFilterBar({
    required this.selected,
    required this.onChanged,
  });

  final _MovementFilter selected;
  final ValueChanged<_MovementFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final option in _MovementFilter.values) ...[
          _chip(option),
          if (option != _MovementFilter.values.last)
            const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _chip(_MovementFilter option) {
    final isSelected = option == selected;
    return ChoiceChip(
      label: Text(option.label),
      selected: isSelected,
      showCheckmark: false,
      onSelected: (_) => onChanged(option),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: Color(
          isSelected
              ? ColorConfig.textPrimary
              : ColorConfig.textSecondary,
        ),
      ),
      selectedColor: const Color(ColorConfig.accent),
      backgroundColor: const Color(ColorConfig.surfaceAlt),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

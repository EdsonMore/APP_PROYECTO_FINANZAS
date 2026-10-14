import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'actions_sheet.dart';
import 'service.dart';

/// Arriba de la app (4D): inicia las notificaciones, recuerda la que abrió la
/// app (N7) y al abrir y al volver corre fechas y reprograma (N2, N8).
class ReminderLifecycle extends ConsumerStatefulWidget {
  const ReminderLifecycle({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ReminderLifecycle> createState() => _ReminderLifecycleState();
}

class _ReminderLifecycleState extends ConsumerState<ReminderLifecycle> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final notifier = ref.read(reminderNotifierProvider);
    await notifier.init((payload) => ref.read(pendingReminderProvider.notifier).state = payload);
    final launch = await notifier.launchPayload();
    if (launch != null && mounted) ref.read(pendingReminderProvider.notifier).state = launch;
    await ref.read(reminderServiceProvider).refreshAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.read(reminderServiceProvider).refreshAll();
    ref.invalidate(notificationsGrantedProvider); // pudo activarlas en los ajustes del sistema
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Envuelve el Home: si se tocó un recordatorio, abre la hoja precargada para
/// confirmar el pago (R1). Funciona con la app abierta y recién abierta.
class ReminderOpener extends ConsumerStatefulWidget {
  const ReminderOpener({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ReminderOpener> createState() => _ReminderOpenerState();
}

class _ReminderOpenerState extends ConsumerState<ReminderOpener> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(pendingReminderProvider, (_, id) {
      if (id != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(id));
    }, fireImmediately: true);
  }

  Future<void> _open(String id) async {
    if (!mounted) return;
    ref.read(pendingReminderProvider.notifier).state = null;
    final db = ref.read(databaseProvider);
    final r = await (db.select(db.recurrences)..where((x) => x.id.equals(id))).getSingleOrNull();
    if (r == null || !mounted) return; // borrado mientras tanto
    await payReminder(context, r); // fix5: lo mismo que "Pagado" (E1 incluido)
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

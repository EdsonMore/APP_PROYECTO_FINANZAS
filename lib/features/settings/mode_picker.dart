import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/metrics.dart';
import 'choice_sheet.dart';
import 'settings_screen.dart';

/// 3 opciones, no las 4 del Onboarding: Mixto se guarda como Variable y
/// mostrarlo aquí mentiría sobre lo que hay en la BD (decisión f).
const modeOptions = <ChoiceOption<Mode>>[
  (value: Mode.stable, title: 'Estable', description: 'Me pagan un monto fijo: mensual, quincenal o semanal.'),
  (value: Mode.variable, title: 'Variable', description: 'Chambas, ventas, freelance, o un fijo más extras.'),
  (value: Mode.survival, title: 'Supervivencia', description: 'Entra plata de vez en cuando, o nada por ahora.'),
];

/// C2: qué cambia en el Home con cada modo.
const modeFooter = 'Al cambiar el modo, el Home se reorganiza:\n'
    'Estable: presupuesto del mes.\n'
    'Variable: cuánto te alcanza.\n'
    'Supervivencia: cuántos días te quedan.';

/// Cambia al instante, sin confirmación (decisión d): es reversible.
Future<void> showModePicker(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  final current = container.read(settingsProvider).value?.mode ?? Mode.variable;
  assert(modeLabels.length == modeOptions.length);
  return showChoiceSheet<Mode>(
    context,
    title: 'Modo de uso',
    options: modeOptions,
    footer: modeFooter,
    current: current,
    onChoose: (m) => container.read(databaseProvider).setMode(m),
  );
}

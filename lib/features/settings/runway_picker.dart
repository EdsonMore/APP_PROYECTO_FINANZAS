import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'choice_sheet.dart';

/// 4 opciones fijas (decisión a). La BD admite 7–90: sumar más no requiere migración.
const runwayOptions = <ChoiceOption<int>>[
  (value: 7, title: '7 días', description: 'Reacciona rápido a cambios recientes.'),
  (value: 14, title: '14 días (recomendado)', description: 'Equilibrio entre rapidez y estabilidad.'),
  (value: 21, title: '21 días', description: 'Más estable.'),
  (value: 30, title: '30 días', description: 'Muy estable; tarda más en reflejar cambios.'),
];

Future<void> showRunwayPicker(BuildContext context, int current) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showChoiceSheet<int>(
    context,
    title: 'Ventana de runway',
    help: 'Cuántos días recientes uso para calcular tu gasto diario promedio.',
    options: runwayOptions,
    current: current,
    onChoose: (d) => container.read(databaseProvider).setRunwayWindow(d),
  );
}

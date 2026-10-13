import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../entry/draft_store.dart';
import 'choice_sheet.dart';

/// Tema manual (4E). Preferencia del teléfono: shared_preferences, sin sync
/// (excepción documentada en SPEC junto a sync.lastOkAt).
const themeModeKey = 'ui.themeMode';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(themeModeKey);
    // Ausente o desconocido → Sistema.
    return ThemeMode.values.where((m) => m.name == saved).firstOrNull ?? ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode; // se aplica al instante; el disco va detrás
    await ref.read(sharedPreferencesProvider).setString(themeModeKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

const themeLabels = {ThemeMode.system: 'Sistema', ThemeMode.light: 'Claro', ThemeMode.dark: 'Oscuro'};

const List<ChoiceOption<ThemeMode>> _options = [
  (value: ThemeMode.system, title: 'Sistema', description: 'Sigue el modo claro u oscuro de tu teléfono.'),
  (value: ThemeMode.light, title: 'Claro', description: 'Siempre claro.'),
  (value: ThemeMode.dark, title: 'Oscuro', description: 'Siempre oscuro.'),
];

Future<void> showAppearancePicker(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showChoiceSheet<ThemeMode>(
    context,
    title: 'Apariencia',
    options: _options,
    current: container.read(themeModeProvider),
    onChoose: (m) => container.read(themeModeProvider.notifier).set(m),
  );
}

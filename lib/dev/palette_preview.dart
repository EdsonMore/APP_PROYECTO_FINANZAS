// Verificación V1 de la 1c: la paleta categórica vista en el emulador.
// No es parte de la app: se corre con `flutter run -t lib/dev/palette_preview.dart`.
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

const _slots = [
  ('terracota', 'Comida'), ('lago', 'Transporte'), ('mostaza', 'Vivienda'), ('uva', 'Ocio'), ('salvia', 'Salud'),
  ('piedra', 'Otros'), ('ciruela', 'libre 1'), ('añil', 'libre 2'), ('petróleo', 'libre 3'),
];
const _sample = [412, 186, 350, 95, 60, 48]; // soles, slots 1-6

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: const String.fromEnvironment('mode') == 'dark' ? ThemeMode.dark : ThemeMode.light,
      home: const _Preview(),
    ));

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<Palette>()!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final total = _sample.fold<int>(0, (a, b) => a + b);
    Color c(int i) => categoryColor('cat:${i + 1}', Theme.of(context).brightness);
    String hex(Color x) => '#${(x.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Space.gutter),
          children: [
            Text('Paleta ${dark ? 'oscuro' : 'claro'}', style: AppType.title.copyWith(color: p.ink)),
            const SizedBox(height: Space.lg),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              for (var i = 0; i < _slots.length; i++)
                SizedBox(
                  width: 112,
                  child: Row(children: [
                    Container(width: 28, height: 28, decoration: BoxDecoration(color: c(i), borderRadius: BorderRadius.circular(6))),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${i + 1} ${_slots[i].$1}', style: AppType.caption.copyWith(color: p.ink)),
                        Text(hex(c(i)), style: AppType.caption.copyWith(color: p.inkMuted)),
                      ]),
                    ),
                  ]),
                ),
            ]),
            const SizedBox(height: Space.lg),
            Text('Junto a los colores de estado', style: AppType.label.copyWith(color: p.inkMuted)),
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              _chip('Ingreso', p.incomeBg, p.incomeFg),
              _chip('Salud', c(4), dark ? p.canvas : Colors.white),
              _chip('Gasto', p.expenseBg, p.expenseFg),
              _chip('Comida', c(0), dark ? p.canvas : Colors.white),
              _chip('Ámbar', p.amberBg, p.amberFg),
              _chip('Vivienda', c(2), dark ? p.canvas : Colors.white),
            ]),
            const SizedBox(height: Space.xl),
            // Gasto de 30 días como barras ordenadas por monto (decisión A de la 1c).
            for (final i in [for (var i = 0; i < _sample.length; i++) i]..sort((a, b) => _sample[b] - _sample[a]))
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(_slots[i].$2, style: AppType.label.copyWith(color: p.ink))),
                    Text('S/ ${_sample[i]}  ${(_sample[i] * 100 / total).round()}%', style: AppType.label.copyWith(color: p.inkMuted)),
                  ]),
                  const SizedBox(height: Space.xs),
                  FractionallySizedBox(
                    widthFactor: _sample[i] / _sample.reduce((a, b) => a > b ? a : b),
                    child: Container(height: 6, decoration: BoxDecoration(color: c(i), borderRadius: BorderRadius.circular(3))),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.chip)),
        child: Text(text, style: AppType.label.copyWith(color: fg)),
      );
}

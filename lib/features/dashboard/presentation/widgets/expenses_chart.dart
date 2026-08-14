import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/utils/formatters.dart';

/// Paleta de colores para las categorías del gráfico.
const List<Color> kChartColors = [
  Color(0xFF7B1FA2),
  Color(0xFF002A8F),
  Color(0xFFEF3340),
  Color(0xFF00A859),
  Color(0xFFF39C12),
  Color(0xFF8E44AD),
  Color(0xFF16A085),
  Color(0xFFC0392B),
];

/// Gráfico circular de gastos por categoría (fl_chart).
class ExpensesChart extends StatelessWidget {
  const ExpensesChart({super.key, required this.data});

  /// Mapa: nombre de categoría -> total gastado.
  final Map<String, double> data;

  double get total => data.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || total <= 0) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        child: const Text(
          'Aún no hay gastos registrados',
          style: TextStyle(color: Color(ColorConfig.textSecondary)),
        ),
      );
    }

    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      sections.add(
        PieChartSectionData(
          value: entry.value,
          title: '${(entry.value / total * 100).toStringAsFixed(0)}%',
          color: kChartColors[i % kChartColors.length],
          radius: 48,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 44,
              sectionsSpace: 3,
              startDegreeOffset: -90,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Legend(items: entries),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});

  final List<MapEntry<String, double>> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: kChartColors[i % kChartColors.length],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${items[i].key} · ${Formatters.compact(items[i].value)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(ColorConfig.textSecondary),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

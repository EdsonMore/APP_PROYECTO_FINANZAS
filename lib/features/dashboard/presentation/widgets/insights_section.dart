import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/providers/service_providers.dart';
import 'package:saldo_claro/core/services/insights_engine.dart';
import 'package:saldo_claro/features/dashboard/providers/dashboard_providers.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/icon_catalog.dart';

/// Widget de "Insights de IA" para el dashboard.
///
/// Muestra al instante los insights calculados por reglas locales y, cuando
/// llega (o si ya estaba cacheado), el insight generado por la IA del mes.
class InsightsSection extends ConsumerWidget {
  const InsightsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(insightsProvider);
    final aiInsightAsync = ref.watch(aiInsightProvider);
    final aiAvailable = ref.watch(aiServiceProvider).available;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 18, color: Color(0xFFF39C12)),
            const SizedBox(width: 8),
            Text(
              'Insights de IA',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(ColorConfig.textPrimary),
              ),
            ),
            const Spacer(),
            if (!aiAvailable)
              const Tooltip(
                message: 'IA no configurada (agrega GEMINI_API_KEY o GROQ_API_KEY). Insights basados en reglas locales.',
                child: Icon(Icons.info_outline, size: 16,
                    color: Color(ColorConfig.textSecondary)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        insightsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Error en insights: $e',
                style: const TextStyle(color: Color(ColorConfig.danger))),
          ),
          data: (insights) {
            if (insights.isEmpty && !_hasAiResult(aiInsightAsync)) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(ColorConfig.surface),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Sin suficientes datos. Registra movimientos para ver tus insights.',
                  style: TextStyle(color: Color(ColorConfig.textSecondary)),
                ),
              );
            }
            return Column(
              children: [
                for (final insight in insights)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _InsightCard(insight: insight),
                  ),
                ..._aiInsightWidgets(aiInsightAsync),
              ],
            );
          },
        ),
      ],
    );
  }

  /// ¿Ya hay un insight de IA (o está pendiente de calcular)?
  bool _hasAiResult(AsyncValue<Insight?> aiInsightAsync) {
    return aiInsightAsync.isLoading || aiInsightAsync.valueOrNull != null;
  }

  List<Widget> _aiInsightWidgets(AsyncValue<Insight?> aiInsightAsync) {
    final aiInsight = aiInsightAsync.valueOrNull;
    if (aiInsight != null) {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _InsightCard(insight: aiInsight),
        ),
      ];
    }
    if (aiInsightAsync.isLoading) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text(
                'La IA está analizando tu mes…',
                style: TextStyle(
                    fontSize: 12, color: Color(ColorConfig.textSecondary)),
              ),
            ],
          ),
        ),
      ];
    }
    return const [];
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final color = switch (insight.type) {
      'ai' => const Color(0xFF8E44AD),
      'ant' => const Color(0xFFE91E63),
      'couple' => const Color(0xFFE91E63),
      'projection' => const Color(0xFFF39C12),
      _ => const Color(0xFF3498DB),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(IconCatalog.iconFor(insight.iconName), color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(ColorConfig.textPrimary),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  insight.message,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(ColorConfig.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/models/achievement.dart';
import 'package:saldo_claro/features/dashboard/presentation/widgets/icon_catalog.dart';
import 'package:saldo_claro/features/gamification/presentation/providers/achievements_provider.dart';

/// Sección de logros/medallas desbloqueables en el Dashboard.
class AchievementsSection extends ConsumerWidget {
  const AchievementsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievementsAsync = ref.watch(achievementsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Logros 🏆',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(ColorConfig.textPrimary),
          ),
        ),
        const SizedBox(height: 12),
        achievementsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) =>
              Text('Error en logros: $e',
                  style: const TextStyle(color: Color(ColorConfig.danger))),
          data: (achievements) {
            final unlocked = achievements.where((a) => a.unlocked).length;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(ColorConfig.surface),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$unlocked/${achievements.length} desbloqueados',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(ColorConfig.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final a in achievements)
                        Expanded(child: _Medal(achievement: a)),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Medal extends StatelessWidget {
  const _Medal({required this.achievement});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final color = achievement.unlocked
        ? const Color(0xFFF39C12)
        : const Color(ColorConfig.textSecondary).withValues(alpha: 0.35);
    final iconColor = achievement.unlocked
        ? const Color(0xFFF39C12)
        : const Color(ColorConfig.textSecondary).withValues(alpha: 0.4);

    return Tooltip(
      message: '${achievement.title}\n${achievement.description}',
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
              border: Border.all(
                color: color.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Icon(
              IconCatalog.iconFor(achievement.icon),
              color: iconColor,
              size: 26,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            achievement.unlocked ? '¡Desbloqueado!' : 'Bloqueado',
            style: const TextStyle(
              fontSize: 10,
              color: Color(ColorConfig.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
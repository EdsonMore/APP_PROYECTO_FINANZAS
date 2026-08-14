/// Identificadores de los logros/medallas desbloqueables.
enum AchievementId {
  survivor,
  antShield,
  responsibleCouple;

  /// Método machine-legible para la UI/mock de fecha.
  String get key => name;
}

/// Logro / medalla visual de la gamificación financiera.
class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.unlocked,
    this.unlockedAt,
  });

  final AchievementId id;
  final String title;
  final String description;
  final String icon;

  /// `true` si el usuario ya lo desbloqueó según sus datos actuales.
  final bool unlocked;
  final DateTime? unlockedAt;

  Achievement copyWith({bool? unlocked, DateTime? unlockedAt}) {
    return Achievement(
      id: id,
      title: title,
      description: description,
      icon: icon,
      unlocked: unlocked ?? this.unlocked,
      unlockedAt: unlockedAt ?? this.unlockedAt,
    );
  }
}
import 'transaction.dart';

/// Sub-categorías internas del módulo "Especial Pareja / Enamorada".
///
/// Permiten agrupar los movimientos de la pareja en bloques significativos:
/// cenas, regalos, entretenimiento y viajes.
enum CoupleSubcategory {
  dinner('Cenas / Comida', 'restaurant'),
  gifts('Regalos / Detalles', 'redeem'),
  entertainment('Entretenimiento / Cine', 'movie'),
  travel('Viajes', 'flight'),
  other('Otros', 'favorite');

  const CoupleSubcategory(this.label, this.icon);

  final String label;
  final String icon;

  /// Clasifica una transacción de la pareja según su comercio/persona.
  static CoupleSubcategory classify(Transaction transaction) {
    final text = (transaction.merchantOrPerson ?? '').toLowerCase();

    const dinners = [
      'restaurant', 'restaurante', 'cena', 'cafe', 'café', 'comida', 'pizza',
      'sushi', 'kfc', 'burger', 'menú', 'buffet', 'bar', 'helado', 'donde',
    ];
    const gifts = [
      'regalo', 'gift', 'flores', 'detalle', 'rosas', 'joyer', 'perfumer',
      'reloj', 'bolso', 'dulce',
    ];
    const entertainment = [
      'cine', 'cinemark', 'cineplanet', 'teatro', 'concierto', 'bolet',
      'spotify', 'netflix', 'sala', 'juego',
    ];
    const travel = [
      'viaje', 'vuelo', 'hotel', 'airbnb', 'taxi', 'uber', 'agencia',
      'tours', 'terminal',
    ];

    for (final k in dinners) {
      if (text.contains(k)) return CoupleSubcategory.dinner;
    }
    for (final k in gifts) {
      if (text.contains(k)) return CoupleSubcategory.gifts;
    }
    for (final k in entertainment) {
      if (text.contains(k)) return CoupleSubcategory.entertainment;
    }
    for (final k in travel) {
      if (text.contains(k)) return CoupleSubcategory.travel;
    }
    return CoupleSubcategory.other;
  }
}

/// Estadísticas del módulo "Especial Pareja" calculadas por el provider.
class CoupleStats {
  const CoupleStats({
    required this.categoryName,
    this.budget,
    required this.monthTotal,
    required this.monthCount,
    required this.pendingSplits,
    required this.breakdown,
    required this.transactions,
  });

  /// Nombre de la categoría objetivo (encontrada entre las del usuario).
  final String categoryName;

  /// Presupuesto mensual configurado para esa categoría (si lo tiene).
  final double? budget;

  /// Total gastado este mes en la categoría de la pareja.
  final double monthTotal;
  final int monthCount;

  /// Suma de splits pendientes de cobrar.
  final double pendingSplits;

  /// Desglose por sub-categoría (total gastado en cada una).
  final Map<CoupleSubcategory, double> breakdown;

  /// Movimientos de la categoría de la pareja (los del mes actual).
  final List<Transaction> transactions;

  int get budgetProgress => budget == null || budget == 0
      ? 0
      : ((monthTotal / budget!) * 100).round();
}
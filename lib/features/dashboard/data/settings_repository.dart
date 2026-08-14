import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:saldo_claro/core/network/supabase_client.dart';

/// Repositorio de ajustes del usuario (presupuestos, preferencias).
///
/// Los presupuestos por categoría viven en `categories.budget`; aquí se
/// gestiona el presupuesto mensual global del usuario en `profiles`.
class SettingsRepository {
  SettingsRepository({SupabaseClient? client})
      : _client = client ?? supabase;

  final SupabaseClient _client;

  /// Presupuesto mensual global del usuario (null si no está configurado).
  Future<double?> fetchMonthlyBudget() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final rows = await _client
        .from('profiles')
        .select('monthly_budget')
        .eq('id', userId)
        .maybeSingle();
    if (rows == null) return null;
    final value = rows['monthly_budget'] as num?;
    return value?.toDouble();
  }

  /// Guarda el presupuesto mensual global. 0/null lo limpia.
  Future<void> setMonthlyBudget(double? budget) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final value = budget != null && budget > 0 ? budget : null;
    await _client.from('profiles').upsert({
      'id': userId,
      'monthly_budget': value,
    });
  }
}
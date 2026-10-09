import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database.dart' show isoDay, parseIsoDay;
import '../../domain/metrics.dart';

/// Se inicializa en main() y se sobreescribe en ProviderScope (y en tests).
final sharedPreferencesProvider = Provider<SharedPreferences>((_) => throw UnimplementedError('override en main'));

final draftStoreProvider = Provider((ref) => DraftStore(ref.watch(sharedPreferencesProvider)));

/// Lo que el usuario dejó a medias en la hoja de registro. Invisible en la UI.
class Draft {
  const Draft({this.amountText = '', this.pickId, this.day, this.note = ''});

  final String amountText;

  /// category_id (gasto) o source_id (ingreso).
  final String? pickId;

  /// null = "hoy" (se resuelve al abrir, así un borrador de ayer abre en hoy).
  final DateTime? day;
  final String note;

  /// Sin monto, nota ni fecha elegida no hay nada que proteger.
  bool get isEmpty => amountText.isEmpty && note.trim().isEmpty && day == null;

  Map<String, Object?> toJson() =>
      {'amount': amountText, 'pick': pickId, 'day': day == null ? null : isoDay(day!), 'note': note};

  factory Draft.fromJson(Map<String, Object?> j) => Draft(
        amountText: j['amount'] as String? ?? '',
        pickId: j['pick'] as String?,
        day: j['day'] == null ? null : parseIsoDay(j['day'] as String),
        note: j['note'] as String? ?? '',
      );
}

/// Un borrador por tipo en shared_preferences: `draft.expense`, `draft.income`.
class DraftStore {
  DraftStore(this._prefs);
  final SharedPreferences _prefs;

  static String _key(EntryKind kind) => 'draft.${kind.name}';

  Draft? load(EntryKind kind) {
    final raw = _prefs.getString(_key(kind));
    if (raw == null) return null;
    try {
      return Draft.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on FormatException {
      return null; // borrador corrupto: se ignora, no rompe la hoja
    } on TypeError {
      return null;
    }
  }

  bool has(EntryKind kind) => _prefs.containsKey(_key(kind));

  /// Un borrador vacío borra el guardado en vez de persistir "nada".
  Future<void> save(EntryKind kind, Draft draft) =>
      draft.isEmpty ? clear(kind) : _prefs.setString(_key(kind), jsonEncode(draft.toJson()));

  Future<void> clear(EntryKind kind) => _prefs.remove(_key(kind));
}

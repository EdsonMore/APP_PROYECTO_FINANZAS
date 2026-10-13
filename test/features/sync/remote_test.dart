import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/features/sync/remote.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PostgrestException _pg(String? code) => PostgrestException(message: 'm', code: code);

void main() {
  test('syncFailureFrom: red corta push(); datos sigue con la fila siguiente', () {
    for (final e in <Object>[
      TimeoutException('t'),
      const SocketException('s'),
      const HttpException('h'),
      _pg('500'),
      _pg('503'),
      _pg('429'),
      StateError('desconocido'),
    ]) {
      expect(syncFailureFrom(e), isA<NetworkFailure>(), reason: '$e');
    }
    // Sesión vencida: aparte, porque se arregla refrescando la sesión.
    for (final c in ['401', 'PGRST301', 'PGRST303']) {
      expect(syncFailureFrom(_pg(c)), isA<AuthExpiredFailure>(), reason: c);
    }
    for (final c in ['23503', '23505', '400', '403', '409', '499', 'PGRST204', null]) {
      final f = syncFailureFrom(_pg(c));
      expect(f, isA<DataFailure>(), reason: '$c');
      expect((f as DataFailure).code, c ?? '');
    }
  });
}

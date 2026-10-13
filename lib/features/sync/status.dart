/// Estado de la sincronización (Fase 3C). La 3D lo muestra como ícono.
enum SyncState {
  /// Sin cuenta: la app no sincroniza ni abre conexiones.
  off,
  syncing,

  /// Todo subido y bajado.
  ok,

  /// Sin conexión (o servidor caído): lo pendiente sale en el próximo intento.
  offline,

  /// La sesión venció y no se pudo renovar: volver a entrar.
  needsLogin,

  /// D5: la cuenta ya tiene datos y el teléfono también. Hay que elegir
  /// "Unir" o "Usar solo los de la nube"; hasta entonces no se sube nada.
  needsChoice,

  /// Sincronizó, pero [SyncStatus.issues] filas no se pudieron subir o bajar.
  issues,
}

class SyncStatus {
  const SyncStatus(this.state, {this.lastSyncAt, this.issues = 0});

  final SyncState state;

  /// Última sincronización completa. Solo en memoria.
  final DateTime? lastSyncAt;
  final int issues;

  @override
  String toString() => 'SyncStatus(${state.name}, $lastSyncAt, $issues)';
}

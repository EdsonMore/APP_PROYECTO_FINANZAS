import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/sheet_grabber.dart';
import '../../core/widgets/text_link.dart';
import 'providers.dart';
import 'screens/account_form.dart';
import 'screens/credentials_screens.dart';
import 'screens/sync_screen.dart';
import 'status.dart';

/// D7: el spinner del header aparece recién si el sync dura más que esto
/// (el polling y el sync tras una escritura duran ~300 ms: sin parpadeo)…
const spinnerDelay = Duration(seconds: 1);

/// …y una vez visible se queda al menos esto.
const spinnerMinShow = Duration(milliseconds: 600);

/// "Última vez" de la hoja. [now] inyectado para los tests.
String relativeSyncTime(DateTime? at, DateTime now) {
  if (at == null) return 'Todavía no';
  final d = now.difference(at);
  if (d < const Duration(minutes: 1)) return 'hace un momento'; // incluye un reloj que retrocedió
  if (d < const Duration(hours: 1)) return 'hace ${d.inMinutes} min';
  if (!at.isBefore(DateTime(now.year, now.month, now.day))) return 'hace ${d.inHours} h';
  if (!at.isBefore(DateTime(now.year, now.month, now.day - 1))) {
    return 'ayer a las ${DateFormat('HH:mm', 'es_PE').format(at)}';
  }
  return DateFormat(at.year == now.year ? 'd MMM' : 'd MMM y', 'es_PE').format(at);
}

String _tooltip(SyncState s) => switch (s) {
  SyncState.off => '',
  SyncState.syncing => 'Sincronización: sincronizando',
  SyncState.ok => 'Sincronización: todo al día',
  SyncState.offline => 'Sincronización: sin conexión',
  SyncState.needsLogin => 'Sincronización: tu sesión venció',
  SyncState.needsChoice => 'Sincronización: elige qué datos usar',
  SyncState.issues => 'Sincronización: hay cambios sin sincronizar',
};

/// Ícono de estado del header del Home (Fase 3D). Sin cuenta (off) no ocupa
/// lugar. Tocarlo abre la hoja con el detalle.
class SyncIndicator extends ConsumerStatefulWidget {
  const SyncIndicator({super.key});

  @override
  ConsumerState<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends ConsumerState<SyncIndicator> {
  /// Lo que se ve; puede ir detrás del estado real por D7.
  SyncStatus _shown = const SyncStatus(SyncState.off);
  SyncStatus _latest = const SyncStatus(SyncState.off);
  Timer? _delay;
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    final first = ref.read(syncStatusProvider).value;
    if (first != null) _onStatus(first, initial: true);
    ref.listenManual(syncStatusProvider, (_, next) {
      final s = next.value;
      if (s != null) _onStatus(s);
    });
  }

  void _show(SyncStatus s, {bool initial = false}) => initial ? _shown = s : setState(() => _shown = s);

  void _onStatus(SyncStatus s, {bool initial = false}) {
    _latest = s;
    if (s.state == SyncState.syncing) {
      if (_shown.state != SyncState.syncing) {
        _delay ??= Timer(spinnerDelay, () {
          _delay = null;
          if (_latest.state != SyncState.syncing) return;
          _hold = Timer(spinnerMinShow, () {
            _hold = null;
            _show(_latest);
          });
          _show(_latest);
        });
      }
      return;
    }
    _delay?.cancel();
    _delay = null;
    if (_hold == null) _show(s, initial: initial); // si no, se aplica al terminar el mínimo
  }

  @override
  void dispose() {
    _delay?.cancel();
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _shown;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : Motion.lightChange,
      child: s.state == SyncState.off
          ? const SizedBox.shrink()
          : IconButton(
              key: const Key('sync.indicator'),
              onPressed: () => showSyncSheet(context, ref),
              tooltip: _tooltip(s.state),
              icon: KeyedSubtree(key: ValueKey(s.state), child: _glyph(context, s, reduced)),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
    );
  }
}

Widget _glyph(BuildContext context, SyncStatus s, bool reduced) {
  final p = context.palette;
  Key k(SyncState st) => Key('sync.icon.${st.name}');
  Icon icon(IconData d, Color c) => Icon(d, key: k(s.state), size: 20, color: c);
  return switch (s.state) {
    SyncState.off => const SizedBox.shrink(),
    SyncState.syncing =>
      reduced
          ? icon(Icons.cloud_sync_outlined, p.inkMuted)
          : SizedBox.square(
              dimension: 20,
              child: Center(
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(key: k(s.state), strokeWidth: 1.5, color: p.inkMuted),
                ),
              ),
            ),
    SyncState.ok => icon(Icons.cloud_done_outlined, p.inkMuted),
    SyncState.offline => icon(Icons.cloud_off_outlined, p.inkMuted),
    SyncState.needsLogin => icon(Icons.error_outline, p.expenseFg),
    SyncState.needsChoice => Badge(
      smallSize: 6,
      backgroundColor: p.attention,
      child: icon(Icons.cloud_outlined, p.attention),
    ),
    // C1: con 1 el ícono ya avisa; el número exacto está en la hoja.
    SyncState.issues =>
      s.issues > 1
          ? Badge(
              key: const Key('sync.badge'),
              label: Text(s.issues > 9 ? '9+' : '${s.issues}'),
              backgroundColor: p.expenseFg,
              textColor: p.surface,
              textStyle: AppType.caption.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFeatures: AppType.tabular,
              ),
              child: icon(Icons.sync_problem_outlined, p.expenseFg),
            )
          : icon(Icons.sync_problem_outlined, p.expenseFg),
  };
}

(String, String?) _sheetText(SyncStatus s) => switch (s.state) {
  SyncState.off || SyncState.syncing => ('Sincronizando', null),
  SyncState.ok => ('Todo sincronizado', null),
  SyncState.offline => (
    'Sin conexión',
    'Tus cambios se guardan en este teléfono y se subirán cuando vuelva la conexión.',
  ),
  SyncState.issues => ('Algunos cambios no se sincronizaron', syncStatusText(s)),
  SyncState.needsLogin => (
    'Tu sesión venció',
    'Tus datos siguen en este teléfono. Vuelve a entrar para seguir sincronizando.',
  ),
  SyncState.needsChoice => ('Elige qué datos usar', 'Tu cuenta ya tiene datos y este teléfono también.'),
};

String _pendingText(int n) => switch (n) {
  0 => 'Nada',
  1 => '1 cambio',
  _ => '$n cambios',
};

/// Hoja del ícono: el estado al día (escucha el mismo provider que el ícono,
/// sin el retraso de D7) y lo que se puede hacer. Las acciones usan [ref]
/// (el del ícono): la hoja se cierra antes de que terminen.
Future<void> showSyncSheet(BuildContext context, WidgetRef ref) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  final nav = Navigator.of(context);
  void go(BuildContext sheet, Widget screen) {
    Navigator.of(sheet).pop();
    nav.push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: false,
    sheetAnimationStyle: reduced
        ? const AnimationStyle(duration: Motion.reducedFade, reverseDuration: Motion.reducedFade)
        : const AnimationStyle(
            duration: Duration(milliseconds: 350),
            reverseDuration: Duration(milliseconds: 250),
            curve: Motion.emphasized,
          ),
    builder: (sheet) => Consumer(
      builder: (sheet, sref, _) {
        final p = sheet.palette;
        final s = sref.watch(syncStatusProvider).value ?? const SyncStatus(SyncState.off);
        final signedIn = sref.watch(accountEmailProvider).value != null;
        final (title, body) = _sheetText(s);
        final details = const {SyncState.syncing, SyncState.ok, SyncState.offline, SyncState.issues}.contains(s.state);
        final pending = details ? sref.watch(syncPendingProvider).value : null;

        Widget row(String key, String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Row(
            children: [
              Text(label, style: AppType.label.copyWith(color: p.inkMuted)),
              const Spacer(),
              Text(
                value,
                key: Key(key),
                style: AppType.label.copyWith(color: p.ink),
              ),
            ],
          ),
        );

        final AccountButton action = switch (s.state) {
          SyncState.needsChoice => AccountButton(
            label: 'Elegir qué datos usar',
            busy: false,
            onPressed: () => go(sheet, const ChoiceScreen()),
          ),
          SyncState.needsLogin => AccountButton(
            label: 'Volver a entrar',
            busy: false,
            onPressed: () => go(sheet, const SignInScreen()),
          ),
          _ => AccountButton(
            label: 'Sincronizar ahora',
            busy: s.state == SyncState.syncing,
            onPressed: () => ref.read(syncSchedulerProvider).syncNow(),
          ),
        };

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Column(
              key: const Key('syncSheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetGrabber(),
                Semantics(
                  header: true,
                  child: Text(title, style: AppType.title.copyWith(color: p.ink)),
                ),
                if (body != null) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    body,
                    style: AppType.body.copyWith(color: s.state == SyncState.needsLogin ? p.expenseFg : p.inkMuted),
                  ),
                ],
                const SizedBox(height: Space.xl),
                if (details) ...[
                  row('syncSheet.last', 'Última vez', relativeSyncTime(s.lastSyncAt, DateTime.now())),
                  row('syncSheet.pending', 'Por subir', pending == null ? '' : _pendingText(pending)),
                  const SizedBox(height: Space.md),
                ],
                action,
                const SizedBox(height: Space.md),
                // TextLink trae 16 de padding a cada lado: se corre 16 para que
                // el texto quede alineado al margen (como en la hoja del ⓘ).
                Row(
                  children: [
                    Transform.translate(
                      offset: const Offset(-Space.lg, 0),
                      child: s.state == SyncState.needsLogin
                          ? TextLink(
                              key: const Key('syncSheet.notNow'),
                              label: 'Ahora no',
                              semanticsLabel: 'Ahora no',
                              onTap: () {
                                Navigator.of(sheet).pop();
                                ref.read(syncEngineProvider).dismissLogin();
                              },
                            )
                          : TextLink(
                              key: const Key('syncSheet.settings'),
                              label: 'Ajustes de sync',
                              semanticsLabel: 'Ajustes de sync',
                              onTap: () {
                                Navigator.of(sheet).pop();
                                nav.push(SyncScreen.route());
                              },
                            ),
                    ),
                    const Spacer(),
                    if (signedIn)
                      Transform.translate(
                        offset: const Offset(Space.lg, 0),
                        child: TextLink(
                          key: const Key('syncSheet.signOut'),
                          label: 'Cerrar sesión',
                          semanticsLabel: 'Cerrar sesión',
                          onTap: () {
                            Navigator.of(sheet).pop();
                            confirmSignOut(context, ref);
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Space.xl),
              ],
            ),
          ),
        );
      },
    ),
  );
}

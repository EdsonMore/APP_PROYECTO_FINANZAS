import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/sheet_grabber.dart';
import '../../core/widgets/text_link.dart';
import '../entry/amount_input.dart';
import '../entry/amount_keypad.dart';
import '../settings/settings_screen.dart' show SubpageHeader;
import 'ai_client.dart';
import 'consent.dart';
import 'facts.dart';
import 'usage.dart';

/// Las predefinidas, en el orden de la lista (las 6 de v1 y la cuota).
const aiQuestionLabels = {
  AiQuestion.canSpend: '¿Puedo gastar S/ X en algo?',
  AiQuestion.whatIf: '¿Qué pasaría si gasto S/ X más al mes?',
  AiQuestion.breakEven: '¿Cuánto necesito ganar para cubrir mis gastos?',
  AiQuestion.cut: '¿Qué puedo recortar sin que se sienta?',
  AiQuestion.save: '¿Cuánto debería ahorrar cada mes?',
  AiQuestion.payFirst: '¿Qué me conviene pagar primero?',
  AiQuestion.installment: '¿Puedo asumir una cuota mensual de S/ X?',
};

/// Una consulta: lo que se muestra y lo que se manda (para "Reintentar").
typedef _Ask = ({AiQuestion q, String shown, int? amount, String? item, String? text});

sealed class _Msg {}

class _UserMsg extends _Msg {
  _UserMsg(this.text);
  final String text;
}

class _AnswerMsg extends _Msg {
  _AnswerMsg(this.text);
  final String text;
}

class _ErrorMsg extends _Msg {
  _ErrorMsg(this.error, this.retry);
  final AiError error;

  /// null: no se reintenta (sesión vencida).
  final _Ask? retry;
}

/// 5C-Chat: las predefinidas, la pregunta libre (C1-A) y el contador. El
/// historial vive solo en esta pantalla: al salir se pierde (sin memoria,
/// cada pregunta va sola).
class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _messages = <_Msg>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _waiting = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start(AiQuestion q) async {
    if (!await ensureAiConsent(context) || !mounted) return;
    int? amount;
    String? item;
    if (q == AiQuestion.canSpend || q == AiQuestion.whatIf || q == AiQuestion.installment) {
      final r = await showAiAmountSheet(context,
          withItem: q == AiQuestion.canSpend, title: q == AiQuestion.installment ? '¿Cuánto es la cuota?' : '¿Cuánto?');
      if (r == null || !mounted) return;
      amount = r.cents;
      item = q == AiQuestion.canSpend ? r.item : null;
    }
    final shown = switch (q) {
      AiQuestion.canSpend => '¿Puedo gastar ${Formatters.soles(amount!)} en ${item ?? 'algo'}?',
      AiQuestion.whatIf => '¿Qué pasaría si gasto ${Formatters.soles(amount!)} más al mes?',
      AiQuestion.installment => '¿Puedo asumir una cuota de ${Formatters.soles(amount!)}?',
      _ => aiQuestionLabels[q]!,
    };
    await _send((q: q, shown: shown, amount: amount, item: item, text: null));
  }

  Future<void> _sendFree() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (!await ensureAiConsent(context) || !mounted) return;
    _input.clear();
    await _send((q: AiQuestion.free, shown: text, amount: null, item: null, text: text));
  }

  Future<void> _send(_Ask a, {bool retry = false}) async {
    final source = ref.read(aiFactsSourceProvider);
    if (source == null) return;
    setState(() {
      if (!retry) _messages.add(_UserMsg(a.shown));
      _waiting = true;
    });
    _scrollToEnd();
    final result = await ref
        .read(aiClientProvider)
        .ask(a.q, factsFor(a.q, source, amountCents: a.amount), amountCents: a.amount, item: a.item, text: a.text);
    if (!mounted) return;
    final usage = ref.read(aiUsageProvider.notifier);
    setState(() {
      _waiting = false;
      switch (result) {
        case AiAnswer(:final text, :final left):
          _messages.add(_AnswerMsg(text));
          usage.applyLeft(left);
        case AiFailure(error: AiError.limit):
          usage.applyLeft(0); // el aviso de límite ya lo dice
        case AiFailure(:final error):
          _messages.add(_ErrorMsg(error, error == AiError.session ? null : a));
      }
    });
    _scrollToEnd();
  }

  void _retry(_ErrorMsg m) {
    setState(() => _messages.remove(m));
    _send(m.retry!, retry: true);
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final usage = ref.watch(aiUsageProvider).value;
    final limited = usage?.left == 0;
    final source = ref.watch(aiFactsSourceProvider);
    final busy = limited || _waiting;
    final questions = [
      for (final q in aiQuestionLabels.keys)
        if (q != AiQuestion.payFirst || (source != null && duePendingCount(source) >= 2)) q,
    ];
    final canSend = !busy && _input.text.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SubpageHeader(title: 'Pregúntale a SaldoClaro'),
            // En 0 no se repite arriba: el aviso de límite va junto al campo.
            if (usage != null && !limited)
              Padding(
                padding: const EdgeInsets.only(left: 48 + Space.xs),
                child: Text(
                  aiUsageText(usage),
                  key: const Key('ai.counter'),
                  style: AppType.caption.copyWith(color: usage.left <= 2 ? p.expenseFg : p.inkMuted),
                ),
              ),
            const SizedBox(height: Space.md),
            Expanded(
              child: ListView(
                key: const Key('ai.chat'),
                controller: _scroll,
                children: [
                  if (_messages.isEmpty)
                    for (final q in questions) _QuestionRow(q: q, onTap: busy ? null : () => _start(q))
                  else ...[
                    for (final m in _messages) _bubble(p, m),
                    if (_waiting) const _Waiting(),
                  ],
                  const SizedBox(height: Space.lg),
                  Text('Respuestas generadas con tus números. No es asesoría financiera.',
                      style: AppType.caption.copyWith(color: p.inkMuted)),
                  if (ref.watch(aiConsentProvider))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Transform.translate(
                        offset: const Offset(-Space.lg, 0), // TextLink trae 16 de padding
                        child: TextLink(
                          key: const Key('ai.deactivate.link'),
                          label: 'Desactivar la IA',
                          semanticsLabel: 'Desactivar la inteligencia artificial',
                          onTap: () => showDeactivateAiSheet(context),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_messages.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final q in questions) _QuestionChip(q: q, onTap: busy ? null : () => _start(q)),
                ]),
              ),
            if (limited)
              Padding(
                key: const Key('ai.limit'),
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Text(aiErrorTexts[AiError.limit]!, style: AppType.caption.copyWith(color: p.expenseFg)),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  key: const Key('ai.input'),
                  controller: _input,
                  enabled: !limited,
                  maxLength: aiFreeTextMax,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => canSend ? _sendFree() : null,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  style: AppType.body.copyWith(color: p.ink),
                  decoration: const InputDecoration(hintText: 'Escribe tu pregunta', isDense: true),
                ),
              ),
              IconButton(
                key: const Key('ai.send'),
                tooltip: 'Enviar',
                onPressed: canSend ? _sendFree : null,
                icon: const Icon(Icons.send),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _bubble(Palette p, _Msg m) {
    final width = MediaQuery.sizeOf(context).width * 0.8;
    Widget box({required Key key, required Widget child, required bool mine, bool border = false}) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            key: key,
            constraints: BoxConstraints(maxWidth: width),
            margin: const EdgeInsets.only(bottom: Space.sm),
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: mine ? p.border : p.surface,
              borderRadius: BorderRadius.circular(Radii.card),
              border: border ? Border.all(color: p.border) : null,
            ),
            child: child,
          ),
        );
    return switch (m) {
      _UserMsg(:final text) => box(
          key: const Key('ai.msg.user'),
          mine: true,
          child: Text(text, style: AppType.body.copyWith(color: p.ink)),
        ),
      _AnswerMsg(:final text) => box(
          key: const Key('ai.msg.answer'),
          mine: false,
          border: true,
          child: Text(text, style: AppType.body.copyWith(color: p.ink)),
        ),
      _ErrorMsg(:final error, :final retry) => box(
          key: const Key('ai.msg.error'),
          mine: false,
          border: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(aiErrorTexts[error]!, style: AppType.body.copyWith(color: p.inkMuted)),
            if (retry != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextLink(
                  key: const Key('ai.retry'),
                  label: 'Reintentar',
                  semanticsLabel: 'Reintentar la pregunta',
                  onTap: _waiting ? null : () => _retry(m),
                ),
              ),
          ]),
        ),
    };
  }
}

/// Fila de la lista vacía.
class _QuestionRow extends StatelessWidget {
  const _QuestionRow({required this.q, required this.onTap});
  final AiQuestion q;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: Key('ai.q.${q.wire}'),
      margin: const EdgeInsets.only(bottom: Space.sm),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: p.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.card),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
            child: Text(aiQuestionLabels[q]!,
                style: AppType.body.copyWith(color: onTap == null ? p.inkMuted : p.ink)),
          ),
        ),
      ),
    );
  }
}

/// Chip de la fila horizontal (con mensajes).
class _QuestionChip extends StatelessWidget {
  const _QuestionChip({required this.q, required this.onTap});
  final AiQuestion q;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      key: Key('ai.q.${q.wire}'),
      padding: const EdgeInsets.only(right: Space.sm),
      child: Center(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.chip),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(Radii.chip),
              border: Border.all(color: p.border),
            ),
            child: Text(aiQuestionLabels[q]!,
                style: AppType.label.copyWith(color: onTap == null ? p.inkMuted : p.ink)),
          ),
        ),
      ),
    );
  }
}

/// Tres puntos mientras llega la respuesta (quietos con "reducir movimiento").
class _Waiting extends StatefulWidget {
  const _Waiting();

  @override
  State<_Waiting> createState() => _WaitingState();
}

class _WaitingState extends State<_Waiting> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        key: const Key('ai.waiting'),
        label: 'Esperando respuesta',
        liveRegion: true,
        excludeSemantics: true,
        child: Container(
          margin: const EdgeInsets.only(bottom: Space.sm),
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: p.border),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.inkMuted.withValues(alpha: ((_c.value * 3 - i) % 3) < 1 ? 1 : 0.35),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "¿Cuánto?" ([title]) con el teclado propio de la app; en "¿Puedo gastar…?", también "¿En qué?".
Future<({int cents, String? item})?> showAiAmountSheet(BuildContext context,
        {required bool withItem, String title = '¿Cuánto?'}) =>
    showModalBottomSheet<({int cents, String? item})>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => _AmountSheet(withItem: withItem, title: title),
    );

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({required this.withItem, required this.title});
  final bool withItem;
  final String title;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  AmountInput _amount = const AmountInput();
  final _item = TextEditingController();

  @override
  void dispose() {
    _item.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenH = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetGrabber(),
            Semantics(header: true, child: Text(widget.title, style: AppType.title.copyWith(color: p.ink))),
            const SizedBox(height: Space.sm),
            AmountDisplay(amount: _amount),
            if (widget.withItem) ...[
              const SizedBox(height: Space.md),
              TextField(
                key: const Key('ai.amount.item'),
                controller: _item,
                maxLength: 40,
                textCapitalization: TextCapitalization.none,
                onChanged: (_) => setState(() {}),
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                style: AppType.body.copyWith(color: p.ink),
                decoration: const InputDecoration(labelText: '¿En qué?', hintText: 'zapatillas', isDense: true),
              ),
            ],
            const SizedBox(height: Space.sm),
            AmountKeypad(
              keyHeight: Space.keyHeight(screenH),
              onKey: (k) => setState(() => _amount = _amount.press(k) ?? _amount),
              onBackspace: () => setState(() => _amount = _amount.backspace()),
              onClear: () => setState(() => _amount = const AmountInput()),
            ),
            const SizedBox(height: Space.md),
            FilledButton(
              key: const Key('ai.amount.ask'),
              onPressed: _amount.cents > 0
                  ? () {
                      final t = _item.text.trim(); // al tocar, no el de la última construcción
                      Navigator.of(context).pop((cents: _amount.cents, item: t.isEmpty ? null : t));
                    }
                  : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Space.ctaHeight)),
              child: const Text('Preguntar'),
            ),
          ]),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_card.dart';
import '../../core/widgets/sheet_grabber.dart';

typedef ChoiceOption<T> = ({T value, String title, String description});

/// Hoja con opciones [ChoiceCard] (las del Onboarding). Tocar una la marca,
/// deja ver el borde/check [Motion.lightChange], llama a [onChoose] y cierra.
Future<void> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  String? help,
  String? footer,
  required List<ChoiceOption<T>> options,
  required T current,
  required Future<void> Function(T value) onChoose,
}) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    sheetAnimationStyle: reduced
        ? const AnimationStyle(duration: Motion.reducedFade, reverseDuration: Motion.reducedFade)
        : const AnimationStyle(
            duration: Duration(milliseconds: 350), reverseDuration: Duration(milliseconds: 250), curve: Motion.emphasized),
    builder: (_) => _ChoiceSheet<T>(
        title: title, help: help, footer: footer, options: options, current: current, onChoose: onChoose),
  );
}

class _ChoiceSheet<T> extends StatefulWidget {
  const _ChoiceSheet({
    required this.title,
    required this.help,
    required this.footer,
    required this.options,
    required this.current,
    required this.onChoose,
  });

  final String title;
  final String? help;
  final String? footer;
  final List<ChoiceOption<T>> options;
  final T current;
  final Future<void> Function(T value) onChoose;

  @override
  State<_ChoiceSheet<T>> createState() => _ChoiceSheetState<T>();
}

class _ChoiceSheetState<T> extends State<_ChoiceSheet<T>> {
  late T _selected = widget.current;
  bool _busy = false;

  Future<void> _choose(T value) async {
    if (_busy) return;
    _busy = true;
    setState(() => _selected = value);
    await widget.onChoose(value);
    await Future<void>.delayed(Motion.lightChange); // deja ver el borde/check
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SheetGrabber(),
          Semantics(header: true, child: Text(widget.title, style: AppType.title.copyWith(color: p.ink))),
          if (widget.help != null) ...[
            const SizedBox(height: Space.sm),
            Text(widget.help!, style: AppType.body.copyWith(color: p.inkMuted)),
          ],
          const SizedBox(height: Space.lg),
          for (final o in widget.options) ...[
            ChoiceCard(
              key: Key('choice.${o.value}'),
              title: o.title,
              description: o.description,
              selected: o.value == _selected,
              onTap: () => _choose(o.value),
            ),
            const SizedBox(height: Space.md),
          ],
          if (widget.footer != null)
            Text(widget.footer!, style: AppType.caption.copyWith(color: p.inkMuted)),
        ]),
      ),
    );
  }
}

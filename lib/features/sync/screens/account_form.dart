import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/press_scale.dart';
import '../../settings/settings_screen.dart';

/// Piezas comunes de las pantallas de cuenta: etiqueta arriba del campo,
/// error debajo (anunciado por el lector de pantalla), botón principal.

class AccountScaffold extends StatelessWidget {
  const AccountScaffold({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
            children: [SubpageHeader(title: title), const SizedBox(height: Space.lg), ...children],
          ),
        ),
      );
}

class AccountField extends StatefulWidget {
  const AccountField({
    super.key,
    required this.label,
    required this.controller,
    this.error,
    this.helper,
    this.password = false,
    this.keyboardType,
    this.autofillHints,
    this.inputFormatters,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? error;
  final String? helper;
  final bool password;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final VoidCallback? onSubmitted;

  @override
  State<AccountField> createState() => _AccountFieldState();
}

class _AccountFieldState extends State<AccountField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.label, style: AppType.label.copyWith(color: p.ink)),
        const SizedBox(height: Space.sm),
        TextField(
          controller: widget.controller,
          obscureText: widget.password && _hidden,
          keyboardType: widget.keyboardType,
          autofillHints: widget.autofillHints,
          inputFormatters: widget.inputFormatters,
          autocorrect: false,
          enableSuggestions: !widget.password,
          onSubmitted: (_) => widget.onSubmitted?.call(),
          style: AppType.body.copyWith(color: p.ink),
          decoration: InputDecoration(
            semanticCounterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.button)),
            suffixIcon: widget.password
                ? IconButton(
                    tooltip: _hidden ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: p.inkMuted),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : null,
          ),
        ),
        if (widget.error != null) ...[
          const SizedBox(height: Space.xs),
          Semantics(
            liveRegion: true,
            child: Text(widget.error!, style: AppType.caption.copyWith(color: p.expenseFg)),
          ),
        ] else if (widget.helper != null) ...[
          const SizedBox(height: Space.xs),
          Text(widget.helper!, style: AppType.caption.copyWith(color: p.inkMuted)),
        ],
      ]),
    );
  }
}

/// Error del servidor (no de un campo), debajo del botón.
class AccountError extends StatelessWidget {
  const AccountError(this.message, {super.key});
  final String? message;

  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: Space.md),
          child: Semantics(
            liveRegion: true,
            child: Text(message!,
                key: const Key('account.error'), style: AppType.body.copyWith(color: context.palette.expenseFg)),
          ),
        );
}

class AccountButton extends StatelessWidget {
  const AccountButton({super.key, required this.label, required this.busy, required this.onPressed, this.danger = false});
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null && !busy;
    final button = FilledButton(
      key: Key('account.button.$label'),
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(Space.ctaHeight),
        backgroundColor: danger ? p.expenseBg : null,
        foregroundColor: danger ? p.expenseFg : null,
        disabledBackgroundColor: p.border,
        disabledForegroundColor: p.inkMuted,
      ),
      child: busy
          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: p.inkMuted))
          : Text(label),
    );
    return enabled ? PressScale(child: button) : button;
  }
}

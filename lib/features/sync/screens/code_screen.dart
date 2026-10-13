import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/text_link.dart';
import '../auth_gateway.dart';
import '../providers.dart';
import '../validation.dart';
import 'account_form.dart';
import 'credentials_screens.dart';

enum CodePurpose { signup, recovery }

/// Espera antes de poder pedir otro código.
const resendWait = Duration(seconds: 60);

/// Código de 6 dígitos que llega al correo: confirma la cuenta nueva o
/// autoriza a poner una contraseña nueva.
class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key, required this.email, required this.purpose});
  final String email;
  final CodePurpose purpose;

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  final _code = TextEditingController();
  String? _codeError, _serverError;
  bool _busy = false;
  int _wait = resendWait.inSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _wait = resendWait.inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _serverError = null;
    });
    try {
      await action();
    } on AuthFailure catch (f) {
      if (mounted) setState(() => _serverError = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    setState(() => _codeError = codeError(_code.text));
    if (_codeError != null) return;
    final gateway = ref.read(authGatewayProvider);
    await _guard(() async {
      if (widget.purpose == CodePurpose.signup) {
        await gateway.verifySignupCode(widget.email, _code.text);
        if (mounted) await attachAndFinish(context, ref);
      } else {
        await gateway.verifyRecoveryCode(widget.email, _code.text);
        if (mounted) {
          await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const NewPasswordScreen()));
        }
      }
    });
  }

  Future<void> _resend() async {
    final gateway = ref.read(authGatewayProvider);
    await _guard(() async {
      if (widget.purpose == CodePurpose.signup) {
        await gateway.resendSignupCode(widget.email);
      } else {
        await gateway.sendRecoveryCode(widget.email);
      }
      if (mounted) setState(_startTimer);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AccountScaffold(title: 'Revisa tu correo', children: [
      Text('Te enviamos un código de 6 dígitos a ${widget.email}.', style: AppType.body.copyWith(color: p.ink)),
      const SizedBox(height: Space.lg),
      AccountField(
        key: const Key('code.field'),
        label: 'Código',
        controller: _code,
        error: _codeError,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        onSubmitted: _confirm,
      ),
      AccountButton(label: 'Confirmar', busy: _busy, onPressed: _confirm),
      AccountError(_serverError),
      const SizedBox(height: Space.sm),
      Center(
        child: _wait > 0
            ? Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Text('Puedes pedir otro código en $_wait s',
                    key: const Key('code.wait'), style: AppType.caption.copyWith(color: p.inkMuted)),
              )
            : TextLink(
                key: const Key('code.resend'),
                label: 'Reenviar código',
                semanticsLabel: 'Reenviar código',
                onTap: _busy ? null : _resend,
              ),
      ),
    ]);
  }
}

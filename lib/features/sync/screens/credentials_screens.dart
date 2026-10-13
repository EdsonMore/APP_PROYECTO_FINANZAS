import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/text_link.dart';
import '../auth_gateway.dart';
import '../providers.dart';
import '../validation.dart';
import 'account_form.dart';
import 'code_screen.dart';
import 'sync_screen.dart';

/// D2: al crear cuenta se sube todo lo del teléfono, sin preguntar.
Future<void> attachAndFinish(BuildContext context, WidgetRef ref) async {
  final r = await ref.read(pusherProvider).push();
  if (!context.mounted) return;
  SyncScreen.finish(
    context,
    r.failed == 0 && !r.stoppedByNetwork
        ? 'Cuenta creada. Tus datos ya están en la nube.'
        : 'Cuenta creada. Algunos datos no se subieron; se volverán a intentar.',
  );
}

/// Estado común: errores por campo, error del servidor y "ocupado".
mixin _Form<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;
  String? serverError;

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      serverError = null;
    });
    try {
      await action();
    } on AuthFailure catch (f) {
      if (mounted) setState(() => serverError = f.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> with _Form {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  String? _emailError, _passwordError, _repeatError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _emailError = emailError(_email.text);
      _passwordError = passwordError(_password.text);
      _repeatError = repeatError(_password.text, _repeat.text);
    });
    if (_emailError != null || _passwordError != null || _repeatError != null) return;
    await run(() async {
      final email = _email.text.trim();
      final outcome = await ref.read(authGatewayProvider).signUp(email, _password.text);
      if (!mounted) return;
      if (outcome == SignUpOutcome.signedIn) return attachAndFinish(context, ref);
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => CodeScreen(email: email, purpose: CodePurpose.signup)));
    });
  }

  @override
  Widget build(BuildContext context) => AccountScaffold(title: 'Crear cuenta', children: [
        AccountField(
            key: const Key('signUp.email'),
            label: 'Correo',
            controller: _email,
            error: _emailError,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email]),
        AccountField(
            key: const Key('signUp.password'),
            label: 'Contraseña',
            controller: _password,
            error: _passwordError,
            helper: 'Mínimo $minPasswordLength caracteres.',
            password: true,
            autofillHints: const [AutofillHints.newPassword]),
        AccountField(
            key: const Key('signUp.repeat'),
            label: 'Repite la contraseña',
            controller: _repeat,
            error: _repeatError,
            password: true,
            onSubmitted: _submit),
        AccountButton(label: 'Crear cuenta', busy: busy, onPressed: _submit),
        AccountError(serverError),
      ]);
}

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> with _Form {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _emailError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _emailError = emailError(_email.text));
    if (_emailError != null) return;
    await run(() async {
      // D3: entrar no sube nada hasta la 3C (antes hay que elegir nube o unir).
      await ref.read(authGatewayProvider).signIn(_email.text, _password.text);
      if (mounted) SyncScreen.finish(context, 'Entraste a tu cuenta.');
    });
  }

  @override
  Widget build(BuildContext context) => AccountScaffold(title: 'Entrar', children: [
        AccountField(
            key: const Key('signIn.email'),
            label: 'Correo',
            controller: _email,
            error: _emailError,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email]),
        AccountField(
            key: const Key('signIn.password'),
            label: 'Contraseña',
            controller: _password,
            password: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: _submit),
        AccountButton(label: 'Entrar', busy: busy, onPressed: _submit),
        AccountError(serverError),
        const SizedBox(height: Space.sm),
        Center(
          child: TextLink(
            key: const Key('signIn.forgot'),
            label: 'Olvidé mi contraseña',
            semanticsLabel: 'Olvidé mi contraseña',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => RecoverScreen(email: _email.text.trim()))),
          ),
        ),
      ]);
}

/// Pide el correo y manda el código de recuperación.
class RecoverScreen extends ConsumerStatefulWidget {
  const RecoverScreen({super.key, this.email = ''});
  final String email;

  @override
  ConsumerState<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends ConsumerState<RecoverScreen> with _Form {
  late final _email = TextEditingController(text: widget.email);
  String? _emailError;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _emailError = emailError(_email.text));
    if (_emailError != null) return;
    await run(() async {
      final email = _email.text.trim();
      await ref.read(authGatewayProvider).sendRecoveryCode(email);
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => CodeScreen(email: email, purpose: CodePurpose.recovery)));
    });
  }

  @override
  Widget build(BuildContext context) => AccountScaffold(title: 'Recuperar contraseña', children: [
        Text('Te enviaremos un código de 6 dígitos a tu correo.',
            style: AppType.body.copyWith(color: context.palette.inkMuted)),
        const SizedBox(height: Space.lg),
        AccountField(
            key: const Key('recover.email'),
            label: 'Correo',
            controller: _email,
            error: _emailError,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            onSubmitted: _submit),
        AccountButton(label: 'Enviar código', busy: busy, onPressed: _submit),
        AccountError(serverError),
      ]);
}

/// Después del código de recuperación: la contraseña nueva.
class NewPasswordScreen extends ConsumerStatefulWidget {
  const NewPasswordScreen({super.key});

  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> with _Form {
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  String? _passwordError, _repeatError;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _passwordError = passwordError(_password.text);
      _repeatError = repeatError(_password.text, _repeat.text);
    });
    if (_passwordError != null || _repeatError != null) return;
    await run(() async {
      await ref.read(authGatewayProvider).updatePassword(_password.text);
      if (mounted) SyncScreen.finish(context, 'Contraseña actualizada. Ya entraste a tu cuenta.');
    });
  }

  @override
  Widget build(BuildContext context) => AccountScaffold(title: 'Nueva contraseña', children: [
        AccountField(
            key: const Key('newPassword.password'),
            label: 'Contraseña',
            controller: _password,
            error: _passwordError,
            helper: 'Mínimo $minPasswordLength caracteres.',
            password: true,
            autofillHints: const [AutofillHints.newPassword]),
        AccountField(
            key: const Key('newPassword.repeat'),
            label: 'Repite la contraseña',
            controller: _repeat,
            error: _repeatError,
            password: true,
            onSubmitted: _submit),
        AccountButton(label: 'Guardar contraseña', busy: busy, onPressed: _submit),
        AccountError(serverError),
      ]);
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/text_link.dart';
import '../../settings/legal_screen.dart';
import '../auth_gateway.dart';
import '../providers.dart';
import '../status.dart';
import '../validation.dart';
import 'account_form.dart';
import 'code_screen.dart';
import 'sync_screen.dart';

/// D2: al crear cuenta se sube todo lo del teléfono, sin preguntar (la
/// cuenta nueva está vacía: el primer sync sube todo).
Future<void> attachAndFinish(BuildContext context, WidgetRef ref) async {
  final s = await ref.read(syncEngineProvider).sync();
  if (!context.mounted) return;
  SyncScreen.finish(
    context,
    s.state == SyncState.ok
        ? 'Cuenta creada. Tus datos ya están en la nube.'
        : 'Cuenta creada. Algunos datos no se subieron; se volverán a intentar.',
  );
}

/// Al entrar a una cuenta que ya existe (D5): primer sync; si la cuenta y el
/// teléfono tienen datos, hay que elegir.
Future<void> connectAndFinish(BuildContext context, WidgetRef ref, String message) async {
  final s = await ref.read(syncEngineProvider).sync();
  if (!context.mounted) return;
  if (s.state == SyncState.needsChoice) {
    // Reemplaza la pantalla actual: "Volver" lleva a Sincronizar, que ofrece elegir.
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const ChoiceScreen()));
    return;
  }
  SyncScreen.finish(context, message);
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

  /// Ley 29733: los ingresos son dato sensible; sin este consentimiento
  /// expreso no se crea la cuenta (ni con el botón ni con Enter).
  bool _consent = false;
  late final _privacyTap = TapGestureRecognizer()
    ..onTap = () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const LegalScreen(title: 'Política de privacidad', asset: privacyAsset)));

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_consent) return;
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
        _consentRow(context),
        const SizedBox(height: Space.lg),
        AccountButton(label: 'Crear cuenta', busy: busy, onPressed: _consent ? _submit : null),
        AccountError(serverError),
      ]);

  Widget _consentRow(BuildContext context) {
    final p = context.palette;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Transform.translate(
        offset: const Offset(-Space.md, 0), // el área táctil de 48 no corre el cuadro del margen
        child: Checkbox(
          key: const Key('signUp.consent'),
          value: _consent,
          onChanged: (v) => setState(() => _consent = v ?? false),
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: Space.md),
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Acepto la '),
              TextSpan(
                text: 'Política de privacidad',
                recognizer: _privacyTap,
                style: TextStyle(color: p.ink, fontWeight: FontWeight.w500, decoration: TextDecoration.underline),
              ),
              const TextSpan(text: ' y que mis datos se guarden fuera del Perú.'),
            ]),
            style: AppType.label.copyWith(color: p.inkMuted, fontWeight: FontWeight.w400, height: 1.5),
          ),
        ),
      ),
    ]);
  }
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
      await ref.read(authGatewayProvider).signIn(_email.text, _password.text);
      if (mounted) await connectAndFinish(context, ref, 'Entraste a tu cuenta.');
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
      if (mounted) await connectAndFinish(context, ref, 'Contraseña actualizada. Ya entraste a tu cuenta.');
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

/// D5: la cuenta y el teléfono tienen datos. "Unir" junta los dos (los
/// ajustes de la nube ganan); "Usar solo los de la nube" reemplaza lo del
/// teléfono, con confirmación.
class ChoiceScreen extends ConsumerStatefulWidget {
  const ChoiceScreen({super.key});

  @override
  ConsumerState<ChoiceScreen> createState() => _ChoiceScreenState();
}

class _ChoiceScreenState extends ConsumerState<ChoiceScreen> with _Form {
  Future<void> _apply(Future<SyncStatus> Function() action, String done) => run(() async {
        final s = await action();
        if (!mounted) return;
        switch (s.state) {
          case SyncState.offline:
            setState(() => serverError = const AuthFailure(AuthFailureKind.offline).message);
          case SyncState.needsLogin:
            SyncScreen.finish(context, syncStatusText(s)!);
          case _:
            SyncScreen.finish(context, done);
        }
      });

  Future<void> _useCloud() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Usar solo los de la nube?'),
        content: const Text('Se borrarán los datos de este teléfono y se reemplazarán por los de tu cuenta.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancelar')),
          TextButton(
              key: const Key('choice.cloud.confirm'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Usar la nube')),
        ],
      ),
    );
    if (ok == true) await _apply(ref.read(syncEngineProvider).useCloud, 'Listo. Ahora ves los datos de tu cuenta.');
  }

  @override
  Widget build(BuildContext context) => AccountScaffold(title: 'Tu cuenta ya tiene datos', children: [
        Text('En este teléfono también hay datos.', style: AppType.body.copyWith(color: context.palette.ink)),
        const SizedBox(height: Space.xl),
        AccountButton(
          label: 'Unir con los de este teléfono',
          busy: busy,
          onPressed: () => _apply(ref.read(syncEngineProvider).join, 'Listo. Tus datos se unieron con los de tu cuenta.'),
        ),
        const SizedBox(height: Space.sm),
        Center(
          child: TextLink(
            key: const Key('choice.cloud'),
            label: 'Usar solo los de la nube',
            semanticsLabel: 'Usar solo los de la nube',
            onTap: busy ? () {} : _useCloud,
          ),
        ),
        AccountError(serverError),
      ]);
}

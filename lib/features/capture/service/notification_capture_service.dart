import 'dart:async';
import 'dart:developer' as developer;

import 'package:saldo_claro/core/models/account.dart';
import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/notification/local_notification_service.dart';
import 'package:saldo_claro/core/notification/notification_listener_channel.dart';
import 'package:saldo_claro/core/services/smart_categorizer.dart';
import 'package:saldo_claro/core/utils/notification_redactor.dart';
import 'package:saldo_claro/core/utils/regex_parser.dart';
import 'package:saldo_claro/features/billing_cycles/services/billing_auto_match_service.dart';
import 'package:saldo_claro/features/dashboard/data/account_repository.dart';
import 'package:saldo_claro/features/dashboard/data/category_repository.dart';
import 'package:saldo_claro/features/dashboard/data/transaction_repository.dart';

/// Orquesta el flujo de captura automática:
/// 1. Recibe la notificación cruda del canal nativo.
/// 2. La parsea con [RegexParser].
/// 3. Resuelve la cuenta (busca en los mapeos de packages o por convención).
/// 4. Clasifica la transacción con [SmartCategorizer] (reglas + IA).
/// 5. Persiste la transacción en Supabase y actualiza el balance.
class NotificationCaptureService {
  NotificationCaptureService({
    NotificationListenerChannel? channel,
    AccountRepository? accountRepository,
    TransactionRepository? transactionRepository,
    CategoryRepository? categoryRepository,
    LocalNotificationService? localNotifications,
    BillingAutoMatchService? billingAutoMatch,
    required SmartCategorizer categorizer,
  })  : _channel = channel ?? NotificationListenerChannel.instance,
        _accountRepository = accountRepository ?? AccountRepository(),
        _transactionRepository = transactionRepository ?? TransactionRepository(),
        _categoryRepository = categoryRepository ?? CategoryRepository(),
        _localNotifications =
            localNotifications ?? LocalNotificationService.instance,
        _billingAutoMatch = billingAutoMatch,
        _categorizer = categorizer;

  final NotificationListenerChannel _channel;
  final AccountRepository _accountRepository;
  final TransactionRepository _transactionRepository;
  final CategoryRepository _categoryRepository;
  final LocalNotificationService _localNotifications;
  final BillingAutoMatchService? _billingAutoMatch;
  final SmartCategorizer _categorizer;

  StreamSubscription<RawNotification>? _subscription;

  /// Evento de control: se emite cuando una notificación se persiste o falla.
  final StreamController<CaptureResult> _results =
      StreamController<CaptureResult>.broadcast();

  Stream<CaptureResult> get results => _results.stream;

  bool _isListening = false;

  /// Inicia la captura automática de notificaciones.
  Future<void> start() async {
    if (_isListening) return;
    _isListening = true;

    final stream = _channel.listen();
    _subscription = stream.listen(_handleRaw);
  }

  Future<void> _handleRaw(RawNotification raw) async {
    try {
      // Log de diagnóstico: siempre se muestra en consola (adb logcat) con el
      // tag "flutter" cuando llega una notificación de una app financiera.
      // Los códigos de seguridad se redactan para no exponerlos ni en logs.
      developer.log(
        '[SaldoClaro] 🔔 Received pkg=${raw.packageName} '
        'title="${NotificationRedactor.redactForLog(raw.title)}" '
        'text="${NotificationRedactor.redactForLog(raw.text)}"',
        name: 'SaldoClaro.Capture',
      );

      final parsed = RegexParser.parse(
        title: raw.title,
        text: raw.text,
        packageName: raw.packageName,
      );

      if (parsed == null) {
        developer.log(
          '[SaldoClaro] ⏭️ Sin coincidencia Regex pkg=${raw.packageName}',
          name: 'SaldoClaro.Capture',
        );
        _results.add(
          CaptureResult.ignored(raw, reason: 'No se pudo interpretar la notificación'),
        );
        return;
      }

      developer.log(
        '[SaldoClaro] ✅ Parseado: ${parsed.toString()} '
        '(confianza=${parsed.confidence})',
        name: 'SaldoClaro.Capture',
      );

      // 1) Resolver la cuenta: primero por mapeo de package (apps nuevas),
      //    después por convención (Yape/BCP/Agora/Lemon).
      Account? account = await _accountRepository
          .findAccountForPackage(raw.packageName);
      if (account == null) {
        final appName = _appNameFor(raw.packageName);
        account = await _accountRepository.findByName(appName);
      }

      if (account == null) {
        _results.add(
          CaptureResult.ignored(
            raw,
            reason:
                'No hay cuenta mapeada para "${raw.packageName}". '
                'Mapeala en "Reconocimiento de apps".',
          ),
        );
        return;
      }

      // 2) Clasificar la transacción (reglas locales + IA opcional).
      //    El texto que llega a la IA NO incluye códigos de seguridad.
      final redactedRawText =
          NotificationRedactor.redactSecurityCodes('${raw.title}\n${raw.text}');
      final categories = await _categoryRepository.fetchAll(type: parsed.type);
      final classification = await _categorizer.classify(
        merchant: parsed.merchantOrPerson ?? '',
        rawText: redactedRawText,
        type: parsed.type,
        categories: categories,
      );

      // 3) Persistir. Solo se guarda el texto ya redactado (sin OTP).
      final saved = await _transactionRepository.insert(
        accountId: account.id,
        amount: parsed.amount,
        type: parsed.type,
        categoryId: classification.classified
            ? classification.categoryId
            : null,
        rawText: redactedRawText,
        merchantOrPerson: parsed.merchantOrPerson,
        sourceApp: account.name,
        source: TransactionSource.auto,
      );

      developer.log(
        '[SaldoClaro] 💾 Insertada id=${saved.id} cat=${classification.categoryName} '
        '(${classification.method})',
        name: 'SaldoClaro.Capture',
      );

      // Feedback inmediato: notificación local de confirmación (Tarea 3).
      unawaited(
        _localNotifications.showCaptureConfirmation(
          type: parsed.type,
          amount: parsed.amount,
          accountName: account.name,
          merchantOrPerson: parsed.merchantOrPerson,
        ),
      );

      // Auto-Match de ciclos de facturación: si la notificación coincide con
      // un servicio activo (p. ej. "Pago a ENOSA"), se marca como pagado y se
      // avanza automáticamente al siguiente ciclo.
      unawaited(
        _billingAutoMatch?.tryAutoMatch(
          title: raw.title,
          text: raw.text,
        ),
      );

      _results.add(
        CaptureResult.success(
          raw,
          transaction: saved,
          parsed: parsed,
          categoryName: classification.categoryName,
          categoryMethod: classification.method,
        ),
      );
    } catch (e, st) {
      developer.log(
        '[SaldoClaro] ❌ Error capturando pkg=${raw.packageName}: $e',
        name: 'SaldoClaro.Capture',
        error: e,
        stackTrace: st,
      );
      _results.add(
        CaptureResult.failed(raw, error: e.toString(), stackTrace: st),
      );
    }
  }

  String _appNameFor(String packageName) {
    switch (packageName) {
      case 'com.bcp.innovacxion.yapeApp':
        return 'Yape';
      case 'com.bcp.bank.bcp':
        return 'BCP';
      case 'pe.agora.app':
        return 'Agora';
      case 'com.lemon.lemoncash':
        return 'Lemon';
      case 'com.interbank.bond':
        return 'Interbank';
      case 'pe.com.bbva.bbvacontigo':
        return 'BBVA';
      case 'pe.plin.app':
        return 'Plin';
      default:
        // Sin convención: devuelve el package para no asociar por error una
        // app desconocida a una cuenta equivocada (mejor ignorar y pedir mapeo).
        return packageName;
    }
  }

  Future<void> dispose() async {
    _isListening = false;
    await _subscription?.cancel();
    _subscription = null;
    _channel.dispose();
    await _results.close();
  }
}

/// Resultado de un intento de captura.
class CaptureResult {
  const CaptureResult.success(
    this.raw, {
    required this.transaction,
    required this.parsed,
    this.categoryName,
    this.categoryMethod,
  })  : error = null,
        reason = null,
        stackTrace = null;

  const CaptureResult.ignored(this.raw, {required this.reason})
      : transaction = null,
        parsed = null,
        error = null,
        stackTrace = null,
        categoryName = null,
        categoryMethod = null;

  const CaptureResult.failed(this.raw, {required this.error, this.stackTrace})
      : transaction = null,
        parsed = null,
        reason = null,
        categoryName = null,
        categoryMethod = null;

  final RawNotification raw;
  final dynamic transaction;
  final ParsedTransaction? parsed;
  final String? error;
  final String? reason;
  final StackTrace? stackTrace;
  final String? categoryName;
  final String? categoryMethod;

  bool get isSuccess => transaction != null;
}

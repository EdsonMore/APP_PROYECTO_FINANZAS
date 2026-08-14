import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/models/transaction_type.dart';

/// Notificaciones locales de SaldoClaro.
///
/// Se usa para dar feedback inmediato al usuario cuando una notificación de
/// pago es capturada en segundo plano (o con la app abierta) y la transacción
/// se persiste en Supabase. También programa los recordatorios de los ciclos
/// de facturación (alerta informativa y crítica).
class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  /// Canal de alta prioridad para las confirmaciones de captura (Android).
  static const String captureChannelId = 'saldo_claro_capture';
  static const String captureChannelName = 'Confirmación de Captura';
  static const String _captureChannelDescription =
      'Confirma cada movimiento capturado automáticamente de Yape, BCP, '
      'Agora, Lemon y otras apps financieras.';

  /// Canal de recordatorios de pagos/servicios (Android).
  static const String billingChannelId = 'saldo_claro_bills';
  static const String billingChannelName = 'Recordatorios de Pagos';
  static const String _billingChannelDescription =
      'Alertas de los servicios y suscripciones próximos a vencer '
      '(luz, agua, internet, streaming, EPS, etc.).';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Inicializa el plugin, las zonas horarias y crea los canales.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Zona horaria local (Perú) para programar recordatorios exactos.
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Lima'));

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );
    await _plugin.initialize(settings: settings);

    const captureChannel = AndroidNotificationChannel(
      captureChannelId,
      captureChannelName,
      description: _captureChannelDescription,
      importance: Importance.high,
    );
    const billingChannel = AndroidNotificationChannel(
      billingChannelId,
      billingChannelName,
      description: _billingChannelDescription,
      importance: Importance.high,
    );
    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(captureChannel);
    await android?.createNotificationChannel(billingChannel);
  }

  /// Notifica una captura exitosa.
  ///
  /// Título: "✅ [Tipo: Ingreso/Gasto] Registrado"
  /// Cuerpo: "SaldoClaro: S/ [monto] en [Cuenta/Banco] - [Persona o Comercio]"
  Future<void> showCaptureConfirmation({
    required TransactionType type,
    required double amount,
    required String accountName,
    String? merchantOrPerson,
  }) async {
    if (!_initialized) return;

    final title =
        '✅ ${type.isIncome ? 'Ingreso' : 'Gasto'} Registrado';
    final merchant = merchantOrPerson?.trim();
    final body = 'SaldoClaro: S/ ${amount.toStringAsFixed(2)} en $accountName'
        '${(merchant != null && merchant.isNotEmpty) ? ' - $merchant' : ''}';

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          captureChannelId,
          captureChannelName,
          channelDescription: _captureChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Recordatorios de ciclos de facturación
  // ------------------------------------------------------------------

  /// Programa un recordatorio local para la fecha/hora indicada.
  ///
  /// Usa el modo `inexactAllowWhileIdle` para no requerir el permiso de
  /// alarma exacta (SCHEDULE_EXACT_ALARM) y que no dependa de Doze Mode.
  Future<void> scheduleBillingReminder({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    if (kIsWeb) return;

    final scheduled = tz.TZDateTime.from(when, tz.local);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          billingChannelId,
          billingChannelName,
          channelDescription: _billingChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Cancela un recordatorio programado por su [id].
  Future<void> cancelBillingReminder(int id) async {
    if (!_initialized) return;
    await _plugin.cancel(id: id);
  }

  /// Confirma de forma inmediata que el pago de un servicio fue detectado.
  Future<void> showBillingPaidNotification({
    required String serviceTitle,
    required DateTime nextDueDate,
  }) async {
    if (!_initialized) return;

    final formattedDate = '${nextDueDate.day.toString().padLeft(2, '0')}/'
        '${nextDueDate.month.toString().padLeft(2, '0')}/${nextDueDate.year}';

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: '🎉 ¡Excelente! Recibo pagado',
      body: 'Detectamos tu pago de $serviceTitle. '
          'Recibo marcado como pagado. '
          'Próximo vencimiento: $formattedDate',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          billingChannelId,
          billingChannelName,
          channelDescription: _billingChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
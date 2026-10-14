import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Lo que los recordatorios (4D) necesitan del sistema. La app usa
/// [PluginReminderNotifier]; los tests, [FakeReminderNotifier].
abstract interface class ReminderNotifier {
  /// [onTap]: payload de la notificación tocada con la app abierta.
  Future<void> init(void Function(String payload) onTap);

  /// Payload de la notificación que abrió la app (cerrada), si fue así (N7).
  Future<String?> launchPayload();
  Future<bool> permissionGranted();

  /// Android 13+: el diálogo del sistema (N6). true si quedó concedido.
  Future<bool> requestPermission();

  /// [at] en hora local; se programa como instante (N4: UTC, sin zona horaria).
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
  });
  Future<void> cancel(int id);
  Future<void> cancelAll();

  /// Ajustes de notificaciones de la app ("Abrir ajustes").
  Future<void> openSettings();
}

class PluginReminderNotifier implements ReminderNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  static const _channel = MethodChannel('saldoclaro/settings');

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init(void Function(String payload) onTap) async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload case final p?) onTap(p);
      },
    );
  }

  @override
  Future<String?> launchPayload() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    return d?.didNotificationLaunchApp == true ? d!.notificationResponse?.payload : null;
  }

  @override
  Future<bool> permissionGranted() async => await _android?.areNotificationsEnabled() ?? true;

  @override
  Future<bool> requestPermission() async => await _android?.requestNotificationsPermission() ?? true;

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
  }) =>
      _plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('reminders', 'Recordatorios', importance: Importance.defaultImportance),
        ),
        // R3: inexacta; no necesita el permiso de alarma exacta (Android 14+).
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        payload: payload,
      );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> openSettings() => _channel.invokeMethod<void>('openAppNotificationSettings');
}

/// En memoria, para tests (y la app sin plataforma).
class FakeReminderNotifier implements ReminderNotifier {
  /// id → lo programado.
  final scheduled = <int, ({DateTime at, String title, String body, String payload})>{};
  bool granted = true;

  /// Lo que contesta el "diálogo" de permiso.
  bool grantOnRequest = true;
  int requests = 0;
  int cancelAllCalls = 0;
  int settingsOpened = 0;
  String? launch;
  void Function(String payload)? onTap;

  @override
  Future<void> init(void Function(String payload) onTap) async => this.onTap = onTap;

  @override
  Future<String?> launchPayload() async => launch;

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<bool> requestPermission() async {
    requests++;
    return granted = grantOnRequest;
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
  }) async =>
      scheduled[id] = (at: at, title: title, body: body, payload: payload);

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    scheduled.clear();
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

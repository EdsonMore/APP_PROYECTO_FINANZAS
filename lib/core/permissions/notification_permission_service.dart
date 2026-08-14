import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Utilidad para comprobar y solicitar los permisos de notificaciones
/// en Android:
///
/// 1. `Notification Listener Access` (`ACTION_NOTIFICATION_LISTENER_SETTINGS`):
///    permiso del sistema que permite al `NotificationListenerService` leer
///    las notificaciones en segundo plano. NO es un runtime permission normal:
///    el usuario debe concederlo desde los Ajustes del sistema.
/// 2. `POST_NOTIFICATIONS` (Android 13+): runtime permission que, si el
///    usuario la deniega, deja el interruptor de notificaciones en gris en
///    los Ajustes de la app. Solicitar este permiso desbloquea el interruptor.
class NotificationPermissionService {
  NotificationPermissionService._();

  static final NotificationPermissionService instance =
      NotificationPermissionService._();

  static const MethodChannel _channel =
      MethodChannel('saldo_claro/permissions');

  static const String _accessEnabledMethod = 'isNotificationListenerEnabled';
  static const String _openSettingsMethod = 'openNotificationSettings';
  static const String _requestRebindMethod = 'requestRebind';
  static const String _setCaptureAllMethod = 'setCaptureAll';
  static const String _addAllowedPackageMethod = 'addAllowedPackage';

  /// Devuelve `true` si la app tiene concedido el acceso a notificaciones.
  Future<bool> isGranted() async {
    try {
      return await _channel.invokeMethod<bool>(_accessEnabledMethod) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Fuerza al sistema a re-enlazar el `NotificationListenerService`.
  ///
  /// Tras un force-stop, actualización o ahorro de batería el sistema puede
  /// dejar el listener desvinculado aunque el permiso siga activo; esto lo
  /// reconecta sin pedirle nada al usuario. Es seguro llamarlo aunque el
  /// permiso ya esté concedido.
  Future<void> requestRebind() async {
    try {
      await _channel.invokeMethod<void>(_requestRebindMethod);
    } on PlatformException {
      // No crítico: se reintenta en el siguiente arranque.
    } on MissingPluginException {
      // No crítico.
    }
  }

  /// Activa/desactiva el modo "capturar todo" del listener nativo.
  ///
  /// Se usa solo mientras se captura una notificación de prueba en
  /// "Reconocimiento de apps" para poder descubrir el package de apps que
  /// aún no están en la lista base (p. ej. Sip). En memoria: se apaga solo
  /// al reiniciar el servicio.
  Future<void> setCaptureAll(bool enabled) async {
    try {
      await _channel.invokeMethod<void>(_setCaptureAllMethod, enabled);
    } on PlatformException {
      // No crítico.
    } on MissingPluginException {
      // No crítico.
    }
  }

  /// Registra un package como "mapeado por el usuario" en el listener nativo
  /// para que siga capturando sus notificaciones después del mapeo.
  Future<void> addAllowedPackage(String packageName) async {
    try {
      await _channel.invokeMethod<void>(_addAllowedPackageMethod, packageName);
    } on PlatformException {
      // No crítico.
    } on MissingPluginException {
      // No crítico.
    }
  }

  /// Abre la pantalla del sistema donde el usuario puede conceder el permiso.
  Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>(_openSettingsMethod) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Solicita el permiso de "Notificaciones" (POST_NOTIFICATIONS, Android 13+).
  ///
  /// En Android < 13 este permiso no existe y siempre estará concedido.
  /// Si el usuario denegó de forma permanente, se abren los Ajustes de la app
  /// para que pueda reactivar el interruptor (que queda en gris) manualmente.
  Future<void> requestSystemNotifications() async {
    if (await Permission.notification.isGranted) return;

    if (await Permission.notification.isPermanentlyDenied) {
      // Denegado para siempre: solo se reactiva desde los Ajustes.
      openAppSettings();
      return;
    }

    await Permission.notification.request();
  }
}

import 'dart:async';

import 'package:flutter/services.dart';

import '../config/app_config.dart';

/// Modelo crudo de una notificación capturada por el lado nativo.
class RawNotification {
  const RawNotification({
    required this.title,
    required this.text,
    required this.packageName,
    required this.timestamp,
  });

  final String title;
  final String text;
  final String packageName;
  final DateTime timestamp;

  factory RawNotification.fromMap(Map<dynamic, dynamic> map) {
    return RawNotification(
      title: (map['title'] as String?) ?? '',
      text: (map['text'] as String?) ?? '',
      packageName: (map['packageName'] as String?) ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  String toString() => 'RawNotification(pkg: $packageName, title: $title)';
}

/// Bridge entre el EventChannel nativo (Kotlin) y Flutter.
///
/// Expone un stream con las notificaciones que el
/// `NotificationListenerService` captura en segundo plano.
class NotificationListenerChannel {
  NotificationListenerChannel._();

  static final NotificationListenerChannel instance =
      NotificationListenerChannel._();

  final EventChannel _channel = const EventChannel(AppConfig.notificationChannel);

  StreamSubscription<dynamic>? _subscription;
  StreamController<RawNotification>? _controller;

  Stream<RawNotification> get onNotification => _controller?.stream ??
      (throw StateError('Llamar a listen() antes de usar el stream.'));

  bool get isListening => _subscription != null;

  /// Inicia la escucha del canal nativo.
  Stream<RawNotification> listen() {
    if (_controller != null) return _controller!.stream;

    final controller = StreamController<RawNotification>.broadcast();
    _controller = controller;

    _subscription = _channel
        .receiveBroadcastStream()
        .listen(
          (event) {
            if (event is Map) {
              controller.add(RawNotification.fromMap(event));
            }
          },
          onError: (Object error, StackTrace stack) {
            controller.addError(error, stack);
          },
        );

    return controller.stream;
  }

  /// Detiene la escucha (opcional).
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller?.close();
    _controller = null;
  }
}

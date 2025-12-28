// lib/iot_car_helper.dart
import 'package:flutter/services.dart';

/// Helper für Kommunikation mit der IOT Car App
class IotCarHelper {
  static const platform = MethodChannel('dev.floriang.trupp_app/status');

  /// Initialisiert den Listener für Status-Änderungen AUS der IOT App
  static void initialize(Function(int status) onStatusChanged) {
    platform.setMethodCallHandler((call) async {
      if (call.method == 'statusChanged') {
        final status = call.arguments['status'] as int;
        onStatusChanged(status);
      }
    });
  }

  /// Sendet einen Status AN die IOT Car App
  static Future<void> sendStatusToIot(int status) async {
    try {
      await platform.invokeMethod('sendStatusToIot', {'status': status});
    } catch (e) {
      print('Failed to send status to IOT app: $e');
    }
  }
}
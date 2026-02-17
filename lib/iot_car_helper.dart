// lib/iot_car_helper.dart
import 'package:flutter/services.dart';

/// Helper für Kommunikation mit Android Auto / Apple CarPlay
class IotCarHelper {
  static const platform = MethodChannel('dev.floriang.trupp_app/status');

  /// Initialisiert den Listener für Status-Änderungen AUS dem Car-Display
  static void initialize(Function(int status) onStatusChanged) {
    platform.setMethodCallHandler((call) async {
      if (call.method == 'statusChanged') {
        final status = call.arguments['status'] as int;
        onStatusChanged(status);
      }
    });
  }

  /// Sendet einen Status AN das Car-Display (Android Auto / CarPlay)
  static Future<void> sendStatusToIot(int status) async {
    try {
      await platform.invokeMethod('sendStatusToIot', {'status': status});
    } catch (_) {
      // Car-Display nicht verbunden - kein Fehler
    }
  }
}

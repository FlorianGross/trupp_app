// lib/iot_car_helper.dart
import 'package:flutter/services.dart';

/// Helper für Kommunikation mit Android Auto / Apple CarPlay
class IotCarHelper {
  static const platform = MethodChannel('dev.floriang.trupp_app/status');

  /// Initialisiert den Listener für Status-Änderungen AUS dem Car-Display.
  ///
  /// [onStatusChanged] erhält neben dem Status auch `delivered`: die native
  /// Car-Schicht (CarPlay-Szene bzw. Android-Auto-Screen) sendet den Status
  /// selbst an die Leitstelle, weil sie auch dann läuft, wenn die Flutter-App
  /// gerade nicht im Vordergrund ist. `delivered == true` heißt, die Meldung
  /// ist dort bereits angekommen — die App darf sie dann NICHT erneut senden,
  /// sonst steht der Status doppelt in der Leitstelle. Bei `false` ist der
  /// native Versand endgültig fehlgeschlagen und die Offline-Queue der App
  /// übernimmt das Nachsenden.
  static void initialize(
    void Function(int status, bool delivered) onStatusChanged,
  ) {
    platform.setMethodCallHandler((call) async {
      if (call.method == 'statusChanged') {
        final args = call.arguments as Map;
        final status = args['status'] as int;
        // Fehlt das Flag (ältere native Schicht), konservativ als „nicht
        // zugestellt" behandeln — lieber einmal zu viel nachsenden als eine
        // Statusmeldung verlieren.
        final delivered = args['delivered'] as bool? ?? false;
        onStatusChanged(status, delivered);
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

  /// Zeigt im Fahrzeug-Display eine Rückfrage zu einem vorgeschlagenen Status
  /// („Ziel erreicht – 4 Ziel erreicht senden?").
  ///
  /// Bestätigt der Fahrer, läuft der Status über denselben Weg zurück wie ein
  /// normaler Druck im Display (`statusChanged` mit `delivered`-Flag) — hier
  /// wird also nichts gesendet, nur gefragt. Ist kein Display verbunden,
  /// passiert nichts.
  static Future<void> showStatusSuggestion({
    required int status,
    required String label,
  }) async {
    try {
      await platform.invokeMethod(
        'showStatusSuggestion',
        {'status': status, 'label': label},
      );
    } catch (_) {
      // Kein Car-Display verbunden - kein Fehler
    }
  }
}

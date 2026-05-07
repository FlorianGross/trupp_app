// lib/data/app_logger.dart
//
// Zentrales Logging für die TruppApp.
// Debug-Builds: gibt Nachrichten per debugPrint aus (sichtbar in Logcat / Xcode-Konsole).
// Release-Builds: no-op (dart tree-shaker entfernt kDebugMode-Blöcke).
//
// Erweiterung auf Sentry / Firebase Crashlytics:
//   Einfach die entsprechenden Aufrufe in _record() hinzufügen.
import 'package:flutter/foundation.dart';

abstract final class AppLogger {
  // ---------------------------------------------------------------------------
  // Öffentliche API
  // ---------------------------------------------------------------------------

  /// Kritischer Fehler – unerwartete Exception in einer wichtigen Operation.
  static void e(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) =>
      _record('E', tag, message, error, stackTrace);

  /// Warnung – etwas lief nicht wie erwartet, aber die App kann weitermachen.
  static void w(String tag, String message, [Object? error]) =>
      _record('W', tag, message, error, null);

  /// Info – normaler Ablauf, nützlich für Diagnose.
  static void i(String tag, String message) =>
      _record('I', tag, message, null, null);

  // ---------------------------------------------------------------------------
  // Interne Implementierung
  // ---------------------------------------------------------------------------

  static void _record(
    String level,
    String tag,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (!kDebugMode) return;

    final buf = StringBuffer()
      ..write('[$level/$tag] ')
      ..write(message);

    if (error != null) {
      buf
        ..write('\n  Error: ')
        ..write(error);
    }
    if (stackTrace != null) {
      // Nur die ersten 8 Frames ausgeben – reicht zur Diagnose
      final frames = stackTrace.toString().split('\n').take(8).join('\n');
      buf
        ..write('\n  Stack:\n')
        ..write(frames);
    }

    debugPrint(buf.toString());
  }
}

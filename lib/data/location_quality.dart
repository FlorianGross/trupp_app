// lib/data/location_quality.dart
import 'package:geolocator/geolocator.dart';

class LocationQualityFilter {
  // Schwellwerte – einige sind veränderbar damit der Service sie zur
  // Laufzeit an den aktuellen TrackingMode anpassen kann (highAccuracy
  // braucht andere Distanz-Schwelle als powerSaver).
  double maxAccuracyM;            // wird vom Service mode-abhängig gesetzt
  double minDistanceM;            // wird vom Service mode-abhängig gesetzt
  final Duration minInterval;     // z.B. 5 s (gegen Spam)
  final double maxJumpSpeedMs;    // z.B. 20 m/s (~72 km/h) – unrealistische Sprünge filtern
  final Duration heartbeatInterval;

  Position? _lastAccepted;
  DateTime? _lastSentAt;

  LocationQualityFilter({
    this.maxAccuracyM = 50.0,
    this.minDistanceM = 10.0,
    this.minInterval = const Duration(seconds: 5),
    this.maxJumpSpeedMs = 20.0,
    this.heartbeatInterval = const Duration(seconds: 30),
  });

  DateTime? get lastSentAt => _lastSentAt;

  /// Setzt die Mindestdistanz zur Laufzeit. Vom Service bei jedem Mode-Wechsel
  /// aufgerufen, damit der Filter sich zum Stream-distanceFilter passt
  /// (z.B. Stream gibt nur Updates >100 m → Filter muss nicht bei 5 m greifen).
  void setMinDistance(double meters) {
    minDistanceM = meters;
  }

  /// Setzt die maximal akzeptierte Ungenauigkeit zur Laufzeit. Vom Service
  /// mode-abhängig gesetzt, um ungenaue WLAN-/Funkzellen-Fixes auszuschließen
  /// (siehe `AdaptiveLocationSettings.getMaxAccuracy`).
  void setMaxAccuracy(double meters) {
    maxAccuracyM = meters;
  }

  /// Prüft, ob ein Fix gesendet werden soll.
  ///
  /// - [forceByHeartbeat]: überspringt nur die Mindestdistanz (der Heartbeat
  ///   soll auch bei Stillstand „lebendig" senden), NICHT die Plausibilität.
  /// - [allowResync]: überspringt Plausibilität UND Mindestdistanz, um nach
  ///   einer längeren Lücke (oder wenn ein früherer Fehl-Fix als Referenz
  ///   „klemmt") wieder aufzusetzen. Genauigkeit und Intervall gelten weiter —
  ///   der Resync akzeptiert also nur einen ausreichend genauen Fix.
  bool isGood(Position p,
      {DateTime? now, bool forceByHeartbeat = false, bool allowResync = false}) {
    final tNow = now ?? DateTime.now();

    // 1) Genauigkeit — verwirft ungenaue WLAN-/Funkzellen-Fixes.
    final acc = p.accuracy.isFinite ? p.accuracy : double.infinity;
    if (acc > maxAccuracyM) return false;

    // 2) Mindest-Intervall (Spam-Schutz).
    if (_lastSentAt != null && tNow.difference(_lastSentAt!) < minInterval) {
      return false;
    }

    if (_lastAccepted != null && !allowResync) {
      final d = Geolocator.distanceBetween(
        _lastAccepted!.latitude, _lastAccepted!.longitude,
        p.latitude, p.longitude,
      );

      // 3) Plausibilität: physikalisch unmögliche Sprünge IMMER verwerfen —
      //    auch beim Heartbeat. Ein Teleport ist unabhängig von der Quelle
      //    falsch (genau das verursacht „Standort springt, wo ich nicht bin").
      final dt =
          p.timestamp.difference(_lastAccepted!.timestamp).inMilliseconds /
              1000.0;
      if (dt > 0 && d / dt > maxJumpSpeedMs) return false;

      // 4) Mindestdistanz nur für Stream-Fixes (Heartbeat darf bei Stillstand
      //    senden).
      if (!forceByHeartbeat && d < minDistanceM) return false;
    }

    return true;
  }

  bool heartbeatDue({DateTime? now}) {
    if (_lastSentAt == null) return true;
    final tNow = now ?? DateTime.now();
    return tNow.difference(_lastSentAt!) >= heartbeatInterval;
  }

  void markSent(Position p, {DateTime? now}) {
    _lastAccepted = p;
    _lastSentAt   = now ?? DateTime.now();
  }
}

// lib/data/location_quality.dart
import 'package:geolocator/geolocator.dart';

class LocationQualityFilter {
  // Schwellwerte – einige sind veränderbar damit der Service sie zur
  // Laufzeit an den aktuellen TrackingMode anpassen kann (highAccuracy
  // braucht andere Distanz-Schwelle als powerSaver).
  final double maxAccuracyM;      // z.B. 50 m
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

  bool isGood(Position p, {DateTime? now, bool forceByHeartbeat = false}) {
    final tNow = now ?? DateTime.now();

    // 1) Genauigkeit
    final acc = p.accuracy.isFinite ? p.accuracy : double.infinity;
    if (acc > maxAccuracyM) return false;

    // 2) Intervall
    if (_lastSentAt != null && tNow.difference(_lastSentAt!) < minInterval) {
      return false;
    }
    //print("LocationQualityFilter: Passed accuracy and interval checks.");
    if (!forceByHeartbeat && _lastAccepted != null) {
      final d = Geolocator.distanceBetween(
        _lastAccepted!.latitude, _lastAccepted!.longitude,
        p.latitude, p.longitude,
      );
      if (d < minDistanceM) return false;

      final fromT = _lastAccepted!.timestamp;
      final toT   = p.timestamp;
      final dt = toT.difference(fromT).inMilliseconds / 1000.0;
      if (dt > 0) {
        final v = d / dt;
        if (v > maxJumpSpeedMs) return false;
      }
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

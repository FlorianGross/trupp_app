// lib/data/location_quality.dart
import 'package:flutter/foundation.dart';
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

  /// Cold-Start-Warm-up: direkt nach (Neu-)Start des Streams sind die ersten
  /// Fixes oft ungenau/driften, obwohl die gemeldete Genauigkeit gut aussieht.
  /// Innerhalb dieses Fensters wird eine strengere Genauigkeit verlangt.
  final Duration warmupDuration;
  final double warmupMaxAccuracyM;

  /// Adaptive Genauigkeits-Schwelle: Fixes, die deutlich schlechter als der
  /// jüngste Genauigkeits-Trend sind, werden verworfen (fängt degradierte Fixes
  /// ab, die das statische Gate durchlässt). Nur oberhalb von [adaptiveFloorM].
  final double adaptiveFactor;
  final double adaptiveFloorM;

  Position? _lastAccepted;
  DateTime? _lastSentAt;
  DateTime? _warmupStart;
  double? _accEma; // gleitender Genauigkeits-Trend (nur akzeptierte Fixes)

  LocationQualityFilter({
    this.maxAccuracyM = 50.0,
    this.minDistanceM = 10.0,
    this.minInterval = const Duration(seconds: 5),
    this.maxJumpSpeedMs = 20.0,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.warmupDuration = const Duration(seconds: 6),
    this.warmupMaxAccuracyM = 15.0,
    this.adaptiveFactor = 2.5,
    this.adaptiveFloorM = 20.0,
  });

  DateTime? get lastSentAt => _lastSentAt;

  /// Startet das Cold-Start-Warm-up neu. Vom Service bei jedem (Neu-)Start des
  /// Positions-Streams aufgerufen.
  void startWarmup({DateTime? now}) {
    _warmupStart = now ?? DateTime.now();
  }

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

    // 0) Manipulierte (gefälschte) Positionen verwerfen — aber nur im Release,
    //    damit Emulator/Debug (dort sind Fixes „mocked") weiter funktionieren.
    if (kReleaseMode && p.isMocked) return false;

    // 1) Genauigkeit — verwirft ungenaue WLAN-/Funkzellen-Fixes.
    final acc = p.accuracy.isFinite ? p.accuracy : double.infinity;
    if (acc > maxAccuracyM) return false;

    // 1a) Cold-Start-Warm-up: in den ersten Sekunden strengere Genauigkeit,
    //     um die instabilen Erst-Fixes nach GPS-Erfassung auszusortieren.
    //     Beim Resync nicht anwenden (dort geht es ums Wiederaufsetzen).
    if (!allowResync &&
        _warmupStart != null &&
        tNow.difference(_warmupStart!) < warmupDuration &&
        acc > warmupMaxAccuracyM) {
      return false;
    }

    // 1b) Adaptive Schwelle: deutlich schlechter als der jüngste Trend →
    //     verwerfen (nur oberhalb des Floors, damit gute Bedingungen nicht
    //     überstreng werden).
    if (_accEma != null &&
        acc > _accEma! * adaptiveFactor &&
        acc > adaptiveFloorM) {
      return false;
    }

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
    // Genauigkeits-Trend nachführen (nur akzeptierte Fixes).
    final acc = p.accuracy.isFinite ? p.accuracy : null;
    if (acc != null) {
      _accEma = _accEma == null ? acc : 0.8 * _accEma! + 0.2 * acc;
    }
  }
}

// lib/data/adaptive_location_settings.dart
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'deployment_state.dart';

/// Verschiedene Tracking-Modi mit unterschiedlicher Genauigkeit und Energieverbrauch
enum TrackingMode {
  highAccuracy,  // Im Einsatz, häufige Updates, hohe Genauigkeit
  balanced,      // Anfahrt/Rückweg, moderate Updates
  powerSaver,    // Bereitschaft, seltene Updates, niedrige Genauigkeit
}

/// Verwaltet adaptive GPS-Einstellungen basierend auf Kontext
class AdaptiveLocationSettings {
  static final _battery = Battery();

  /// Bestimmt den optimalen Tracking-Modus.
  /// Aktive Status (1, 3, 7) bekommen IMMER mindestens balanced,
  /// unabhängig vom Deployment-Modus.
  static Future<TrackingMode> determineMode({
    required DeploymentMode deployment,
    required int currentStatus,
  }) async {
    int batteryLevel;
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (_) {
      batteryLevel = 100; // Fallback (z.B. Simulator)
    }

    // Kritischer Akku → immer Power Saver
    if (batteryLevel < 15) {
      return TrackingMode.powerSaver;
    }

    // UHS / fester Sanitäts-Standort: Position ändert sich nicht → immer sehr
    // sparsam tracken (lange Dienste, Akku schonen), unabhängig vom Status.
    if (deployment == DeploymentMode.stationary) {
      return TrackingMode.powerSaver;
    }

    // Aktive Einsatz-Status (3 = Auftrag, 7 = Transport) → hohe Genauigkeit
    if ([3, 7].contains(currentStatus)) {
      return batteryLevel > 30 ? TrackingMode.highAccuracy : TrackingMode.balanced;
    }

    // Einsatzbereit (Status 1) → ausgewogen (immer GPS, nicht nur Funk)
    if (currentStatus == 1) {
      return TrackingMode.balanced;
    }

    // Rückweg
    if (deployment == DeploymentMode.returning) {
      return TrackingMode.balanced;
    }

    // Alle anderen Status (0, 2, 4, 5, 6, 8, 9): Power Saver
    return TrackingMode.powerSaver;
  }

  /// Erstellt LocationSettings basierend auf Tracking-Modus.
  ///
  /// Android: `forceLocationManager: false` — Fused Location Provider verwenden
  /// (energieeffizient, Sensor-Fusion). Der ältere LocationManager-Pfad ist
  /// stromhungriger und sollte nur als expliziter Fallback dienen.
  ///
  /// iOS: Accuracy wird modusabhängig gemappt — nur highAccuracy nutzt
  /// `bestForNavigation` (sehr stromhungrig), balanced fällt auf `best`,
  /// powerSaver auf `nearestTenMeters` zurück.
  static LocationSettings buildSettings(TrackingMode mode) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: _androidAccuracyFor(mode),
        distanceFilter: _getDistanceFilter(mode),
        intervalDuration: _getInterval(mode),
        // Fused Location Provider in allen Modi — kein LocationManager-Force
        forceLocationManager: false,
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: _iosAccuracyFor(mode),
        // powerSaver = Bereitschaft → generischer Activity-Type, iOS darf
        // sparsamer arbeiten. Navigation-Type nur wenn wirklich gefahren wird.
        activityType: mode == TrackingMode.powerSaver
            ? ActivityType.other
            : ActivityType.otherNavigation,
        distanceFilter: _getDistanceFilter(mode),
        // iOS darf das GPS bei Stillstand schlafen legen — außer im Einsatz
        // (highAccuracy), wo lückenloses Tracking wichtiger ist als Akku.
        // Der Heartbeat (getCurrentPosition) weckt die Ortung ohnehin
        // periodisch wieder auf.
        pauseLocationUpdatesAutomatically: mode != TrackingMode.highAccuracy,
        showBackgroundLocationIndicator: true,      // Immer Indikator zeigen
        allowBackgroundLocationUpdates: true,       // Hintergrund-Updates erlauben
      );
    } else {
      return LocationSettings(
        accuracy: _genericAccuracyFor(mode),
        distanceFilter: _getDistanceFilter(mode),
      );
    }
  }

  static LocationAccuracy _androidAccuracyFor(TrackingMode mode) {
    switch (mode) {
      case TrackingMode.highAccuracy:
        return LocationAccuracy.high;
      case TrackingMode.balanced:
        return LocationAccuracy.medium;
      case TrackingMode.powerSaver:
        return LocationAccuracy.low;
    }
  }

  /// iOS-Accuracy modusabhängig — `bestForNavigation` ist sehr stromhungrig
  /// und nur im Einsatz gerechtfertigt. `medium` entspricht auf iOS ~100m,
  /// genug für den Bereitschafts-/Heartbeat-Fall.
  static LocationAccuracy _iosAccuracyFor(TrackingMode mode) {
    switch (mode) {
      case TrackingMode.highAccuracy:
        return LocationAccuracy.bestForNavigation;
      case TrackingMode.balanced:
        return LocationAccuracy.best;
      case TrackingMode.powerSaver:
        return LocationAccuracy.medium;
    }
  }

  static LocationAccuracy _genericAccuracyFor(TrackingMode mode) {
    switch (mode) {
      case TrackingMode.highAccuracy:
        return LocationAccuracy.high;
      case TrackingMode.balanced:
        return LocationAccuracy.medium;
      case TrackingMode.powerSaver:
        return LocationAccuracy.low;
    }
  }

  /// Distanzfilter je nach Modus
  static int _getDistanceFilter(TrackingMode mode) {
    switch (mode) {
      case TrackingMode.highAccuracy:
        return 10; // 10m - hohe Genauigkeit
      case TrackingMode.balanced:
        return 25; // 25m - ausgewogen
      case TrackingMode.powerSaver:
        return 100; // 100m - sehr sparsam
    }
  }

  /// Update-Intervall je nach Modus
  static Duration _getInterval(TrackingMode mode) {
    switch (mode) {
      case TrackingMode.highAccuracy:
        return const Duration(seconds: 5);
      case TrackingMode.balanced:
        return const Duration(seconds: 15);
      case TrackingMode.powerSaver:
        return const Duration(seconds: 60);
    }
  }

  /// Heartbeat-Intervall je nach Modus
  static Duration getHeartbeatInterval(TrackingMode mode, bool isStationary) {
    if (isStationary && mode == TrackingMode.powerSaver) {
      return const Duration(minutes: 5); // Bei Stillstand sehr selten
    }

    switch (mode) {
      case TrackingMode.highAccuracy:
        return const Duration(seconds: 30);
      case TrackingMode.balanced:
        return const Duration(seconds: 60);
      case TrackingMode.powerSaver:
        return const Duration(minutes: 2);
    }
  }

  /// Accuracy für einmalige Heartbeat-GPS-Abfragen (One-Shot via
  /// `getCurrentPosition`). Wird modusabhängig gemappt, damit der Heartbeat
  /// im powerSaver-Modus nicht denselben Stromverbrauch wie ein Einsatz-Fix
  /// hat.
  static LocationAccuracy getOneShotAccuracy(TrackingMode mode) {
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return _iosAccuracyFor(mode);
    }
    return _androidAccuracyFor(mode);
  }

  /// Timeout für einmalige Heartbeat-GPS-Abfragen — bei `powerSaver` darf
  /// der Fix länger dauern (Cold-Start aus dem Sleep), im Einsatz muss er
  /// schnell kommen.
  static Duration getOneShotTimeout(TrackingMode mode) {
    switch (mode) {
      case TrackingMode.highAccuracy:
        return const Duration(seconds: 8);
      case TrackingMode.balanced:
        return const Duration(seconds: 12);
      case TrackingMode.powerSaver:
        return const Duration(seconds: 20);
    }
  }

  /// Gibt Beschreibung für UI zurück
  static String getModeDescription(TrackingMode mode) {
    switch (mode) {
      case TrackingMode.highAccuracy:
        return 'Hohe Genauigkeit';
      case TrackingMode.balanced:
        return 'Ausgewogen';
      case TrackingMode.powerSaver:
        return 'Energiesparmodus';
    }
  }
}

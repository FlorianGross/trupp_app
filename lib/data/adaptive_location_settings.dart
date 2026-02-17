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

  /// Erstellt LocationSettings basierend auf Tracking-Modus
  static LocationSettings buildSettings(TrackingMode mode) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: mode == TrackingMode.highAccuracy
            ? LocationAccuracy.high
            : LocationAccuracy.medium,  // Auch powerSaver: GPS statt nur Funk
        distanceFilter: _getDistanceFilter(mode),
        intervalDuration: _getInterval(mode),
        forceLocationManager: mode == TrackingMode.highAccuracy,
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: mode == TrackingMode.highAccuracy
            ? LocationAccuracy.best
            : LocationAccuracy.bestForNavigation,  // GPS auch im Hintergrund
        activityType: ActivityType.otherNavigation,
        distanceFilter: _getDistanceFilter(mode),
        pauseLocationUpdatesAutomatically: false,  // Nie automatisch pausieren
        showBackgroundLocationIndicator: true,      // Immer Indikator zeigen
        allowBackgroundLocationUpdates: true,       // Hintergrund-Updates erlauben
      );
    } else {
      return LocationSettings(
        accuracy: mode == TrackingMode.highAccuracy
            ? LocationAccuracy.high
            : LocationAccuracy.medium,
        distanceFilter: _getDistanceFilter(mode),
      );
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
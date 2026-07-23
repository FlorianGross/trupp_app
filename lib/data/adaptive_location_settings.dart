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

  /// Aktive Einsatz-Status: 1 = Einsatzbereit (auf Funk/Wache), 3 = Auftrag
  /// angenommen, 7 = Transport. Diese werden IMMER mit hoher Frequenz
  /// getrackt (Akku-Tradeoff bewusst akzeptiert).
  static const activeStatuses = [1, 3, 7];

  /// Aus den App-Einstellungen gesetzt (Isolate-lokal vom Service befüllt).
  ///
  /// [highFrequency] (Standard true): kürzere Update-Intervalle und kleinere
  /// Distanzfilter → häufigere Positionen, mehr Akkuverbrauch. Kann in den
  /// Einstellungen zugunsten der Akkulaufzeit abgeschaltet werden.
  static bool highFrequency = true;

  /// Bestimmt den optimalen Tracking-Modus.
  ///
  /// Aktive Status (1, 3, 7) bekommen IMMER `highAccuracy` — unabhängig vom
  /// Deployment-Modus und (oberhalb des kritischen Akkustands) auch unabhängig
  /// vom Akku. Nur bei kritischem Akku wird auf `balanced` zurückgeschaltet,
  /// statt das Gerät komplett leerzusaugen — sonst gäbe es am Ende gar kein
  /// Tracking mehr.
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

    // UHS / fester Sanitäts-Standort: Position ändert sich nicht → immer sehr
    // sparsam tracken (lange Dienste, Akku schonen), unabhängig vom Status.
    if (deployment == DeploymentMode.stationary) {
      return TrackingMode.powerSaver;
    }

    final isActive = activeStatuses.contains(currentStatus);

    // Aktive Status (1, 3, 7) → höchste Frequenz. Bei kritischem Akku (<10 %)
    // nur bis balanced zurück, damit weiterhin lückenlos getrackt wird.
    if (isActive) {
      return batteryLevel < 10 ? TrackingMode.balanced : TrackingMode.highAccuracy;
    }

    // Ab hier nur noch inaktive Status.
    // Kritischer Akku → Power Saver.
    if (batteryLevel < 15) {
      return TrackingMode.powerSaver;
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
        // WICHTIG: NIEMALS automatisch pausieren.
        //
        // Wenn iOS die Standort-Updates pausiert (bei vermutetem Stillstand),
        // wird der App-Prozess suspendiert und der Positions-Stream liefert im
        // Hintergrund NICHTS mehr — es bleibt nur der seltene, von iOS nach
        // Gutdünken vergebene Background-Fetch (`onIosBackground`). Genau das
        // führte dazu, dass im Hintergrund oft gar keine Position mehr ankam.
        // Bewusste Entscheidung: lieber Akku als kein Standort. Zusammen mit
        // `allowBackgroundLocationUpdates` + UIBackgroundModes `location`
        // bleibt der Stream so im Hintergrund durchgehend aktiv.
        pauseLocationUpdatesAutomatically: false,
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
        // NICHT `low`: das entspricht PRIORITY_LOW_POWER (reine Funkzellen-/
        // WLAN-Ortung, grob und sprunganfällig). `medium` (PRIORITY_BALANCED)
        // bezieht GPS mit ein → deutlich stabilere Position, kaum Mehrverbrauch
        // dank großem Distanzfilter im Energiesparmodus.
        return LocationAccuracy.medium;
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

  /// Distanzfilter je nach Modus. Im [highFrequency]-Modus (Standard) enger,
  /// damit auch bei langsamer Bewegung häufig Positionen kommen.
  static int _getDistanceFilter(TrackingMode mode) {
    if (highFrequency) {
      switch (mode) {
        case TrackingMode.highAccuracy:
          return 8;   // 8m - Einsatz, dichte Spur
        case TrackingMode.balanced:
          return 10;  // 10m - ausgewogen (vorher 25m)
        case TrackingMode.powerSaver:
          return 75;  // 75m - sparsam
      }
    }
    // Akkusparende Werte (Einstellung „Hohe Frequenz" aus).
    switch (mode) {
      case TrackingMode.highAccuracy:
        return 15;
      case TrackingMode.balanced:
        return 30;
      case TrackingMode.powerSaver:
        return 120;
    }
  }

  /// Update-Intervall je nach Modus.
  static Duration _getInterval(TrackingMode mode) {
    if (highFrequency) {
      switch (mode) {
        case TrackingMode.highAccuracy:
          return const Duration(seconds: 4);
        case TrackingMode.balanced:
          return const Duration(seconds: 10);
        case TrackingMode.powerSaver:
          return const Duration(seconds: 45);
      }
    }
    switch (mode) {
      case TrackingMode.highAccuracy:
        return const Duration(seconds: 8);
      case TrackingMode.balanced:
        return const Duration(seconds: 20);
      case TrackingMode.powerSaver:
        return const Duration(seconds: 90);
    }
  }

  /// Heartbeat-Intervall je nach Modus. Der Heartbeat sorgt für Positionen
  /// auch bei Stillstand (Stream liefert dann nichts). Bei [highFrequency]
  /// deutlich kürzer, damit aktive Status (1/3/7) häufig senden.
  static Duration getHeartbeatInterval(TrackingMode mode, bool isStationary) {
    if (isStationary && mode == TrackingMode.powerSaver) {
      return const Duration(minutes: 5); // Bei Stillstand sehr selten
    }

    if (highFrequency) {
      switch (mode) {
        case TrackingMode.highAccuracy:
          return const Duration(seconds: 15);
        case TrackingMode.balanced:
          return const Duration(seconds: 30);
        case TrackingMode.powerSaver:
          return const Duration(minutes: 2);
      }
    }
    switch (mode) {
      case TrackingMode.highAccuracy:
        return const Duration(seconds: 45);
      case TrackingMode.balanced:
        return const Duration(seconds: 90);
      case TrackingMode.powerSaver:
        return const Duration(minutes: 3);
    }
  }

  /// Wenn true (Standard), werden ungenaue Fixes (typisch WLAN-/Funkzellen-
  /// Ortung, ~30–100 m Streuung) verworfen — es wird nur ein „sicherer",
  /// GPS-genauer Standort gesendet. In den Einstellungen abschaltbar, falls
  /// ein grober Standort besser ist als gar keiner.
  static bool preciseLocationOnly = true;

  /// Maximal akzeptierte Ungenauigkeit (Meter) je nach Modus. Fixes mit
  /// schlechterer Accuracy werden vom Quality-Filter verworfen. Bei
  /// [preciseLocationOnly] eng genug, um reine WLAN-/Funkzellen-Ortung
  /// auszuschließen; sonst großzügig (grober Standort besser als keiner).
  static double getMaxAccuracy(TrackingMode mode) {
    if (!preciseLocationOnly) {
      switch (mode) {
        case TrackingMode.highAccuracy:
          return 50.0;
        case TrackingMode.balanced:
          return 65.0;
        case TrackingMode.powerSaver:
          return 100.0;
      }
    }
    // Nur „sichere" GPS-Fixes zulassen — WLAN-Ortung meldet meist ≥30–50 m.
    switch (mode) {
      case TrackingMode.highAccuracy:
        return 25.0;
      case TrackingMode.balanced:
        return 40.0;
      case TrackingMode.powerSaver:
        return 65.0;
    }
  }

  /// Accuracy für einmalige Heartbeat-GPS-Abfragen (One-Shot via
  /// `getCurrentPosition`). Wird modusabhängig gemappt, damit der Heartbeat
  /// im powerSaver-Modus nicht denselben Stromverbrauch wie ein Einsatz-Fix
  /// hat.
  static LocationAccuracy getOneShotAccuracy(TrackingMode mode) {
    // Heartbeat-One-Shots sind selten und sollen ZUVERLÄSSIG sein: immer
    // GPS-Genauigkeit, nie WLAN-/Funkzellen-Ortung. Genau diese groben
    // Heartbeat-Fixes waren eine Hauptursache für „Standort springt, wo ich
    // nicht bin". Der längere Timeout (getOneShotTimeout) fängt den GPS-Cold-
    // Start ab.
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return LocationAccuracy.best;
    }
    return LocationAccuracy.high;
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

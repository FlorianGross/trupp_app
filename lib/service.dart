// lib/service.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'data/edp_api.dart';
import 'data/location_quality.dart';
import 'data/location_sync_manager.dart';
import 'data/deployment_state.dart';
import 'data/adaptive_location_settings.dart';

// Globale Variablen für Service-Isolate
int _currentStatus = 0;
DeploymentMode _deploymentMode = DeploymentMode.standby;
TrackingMode _trackingMode = TrackingMode.balanced;

// Smart Heartbeat mit Bewegungserkennung
class SmartHeartbeat {
  static Position? _lastPosition;
  static DateTime? _lastMovement;
  static bool _isStationary = false;

  static Duration getHeartbeatInterval() {
    return AdaptiveLocationSettings.getHeartbeatInterval(_trackingMode, _isStationary);
  }

  static void updateMovementState(Position current) {
    if (_lastPosition == null) {
      _lastPosition = current;
      _lastMovement = DateTime.now();
      _isStationary = false;
      return;
    }

    final distance = Geolocator.distanceBetween(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
      current.latitude,
      current.longitude,
    );

    // Bewegung erkannt (>20m)
    if (distance > 20) {
      _isStationary = false;
      _lastMovement = DateTime.now();
      _lastPosition = current;
    }
    // Länger als 5 Min keine Bewegung
    else if (_lastMovement != null &&
        DateTime.now().difference(_lastMovement!) > const Duration(minutes: 5)) {
      _isStationary = true;
    }
  }

  static bool get isStationary => _isStationary;
}

const _minAccuracyMeters = 50.0;
const _minSendInterval = Duration(seconds: 5);
const _minDistanceMeters = 5.0;

final _quality = LocationQualityFilter(
  maxAccuracyM: _minAccuracyMeters,
  minDistanceM: _minDistanceMeters,
  minInterval: _minSendInterval,
  maxJumpSpeedMs: 20.0,
  heartbeatInterval: const Duration(seconds: 30),
);

Timer? _hbTimer;
Timer? _modeCheckTimer;
Timer? _flushTimer;
StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

Future<int> _readStatusFromPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt('lastStatus') ?? 0;
}

Future<bool> _hasValidConfig() async {
  return EdpApi.hasValidConfigInPrefs();
}

Future<void> _ensureFullAccuracyIfPossible() async {
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    final status = await Geolocator.getLocationAccuracy();
    if (status == LocationAccuracyStatus.reduced) {
      try {
        await Geolocator.requestTemporaryFullAccuracy(purposeKey: 'PreciseTracking');
      } catch (_) {
        /* Ignorieren */
      }
    }
  }
}

Future<void> _sendPositionIfOk(ServiceInstance service, Position pos,
    {bool forceByHeartbeat = false}) async {
  final now = DateTime.now();

  // Bewegungsstatus aktualisieren
  SmartHeartbeat.updateMovementState(pos);

  // Qualität / Drosselung
  if (!_quality.isGood(pos, now: now, forceByHeartbeat: forceByHeartbeat)) {
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Trupp App',
        content: _getNotificationContent(isWaiting: true),
      );
    }
    return;
  }

  if (!await _hasValidConfig()) {
    //print("No valid config, not sending position.");
    return;
  }

  try {
    await LocationSyncManager.instance.sendOrQueue(
      lat: pos.latitude,
      lon: pos.longitude,
      accuracy: pos.accuracy.isFinite ? pos.accuracy : null,
      status: _currentStatus,
      timestamp: pos.timestamp,
    );

    _quality.markSent(pos, now: now);

    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Trupp App',
        content: _getNotificationContent(),
      );
    }
  } catch (_) {
    //print("Error sending position, queuing.");
  }
}

String _getNotificationContent({bool isWaiting = false}) {
  final modeText = _deploymentMode == DeploymentMode.deployed
      ? 'Im Einsatz'
      : (_deploymentMode == DeploymentMode.returning ? 'Rückweg' : 'Bereitschaft');

  final trackingText = AdaptiveLocationSettings.getModeDescription(_trackingMode);

  if (isWaiting) {
    return '$modeText (Status $_currentStatus) - Warte auf GPS…';
  }

  if (SmartHeartbeat.isStationary) {
    return '$modeText (Status $_currentStatus) - Stillstand - $trackingText';
  }

  return '$modeText (Status $_currentStatus) - $trackingText';
}

Future<void> _heartbeatTick(ServiceInstance service) async {
  try {
    Position? pos = await Geolocator.getLastKnownPosition();
    pos ??= await Geolocator.getCurrentPosition(
      locationSettings: AdaptiveLocationSettings.buildSettings(_trackingMode),
    );

    await _sendPositionIfOk(service, pos, forceByHeartbeat: true);
  } catch (_) {}
}

void _scheduleNextHeartbeat(ServiceInstance service) {
  _hbTimer?.cancel();
  _hbTimer = Timer(SmartHeartbeat.getHeartbeatInterval(), () async {
    await _heartbeatTick(service);
    _scheduleNextHeartbeat(service); // Rekursiv mit neuem Intervall
  });
}

/// Callback wird von onStart gesetzt, damit _updateTrackingMode den Stream
/// bei Moduswechsel neu starten kann.
Future<void> Function()? _restartStreamCallback;

Future<void> _updateTrackingMode(ServiceInstance service) async {
  final newMode = await AdaptiveLocationSettings.determineMode(
    deployment: _deploymentMode,
    currentStatus: _currentStatus,
  );

  if (newMode != _trackingMode) {
    _trackingMode = newMode;

    // GPS-Stream mit neuen Einstellungen neu starten
    if (_restartStreamCallback != null) {
      await _restartStreamCallback!();
    }

    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Trupp App',
        content: _getNotificationContent(),
      );
    }
  }
}

void _schedulePeriodicModeCheck(ServiceInstance service) {
  _modeCheckTimer?.cancel();
  _modeCheckTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
    await _updateTrackingMode(service);

    // Auto-Stop nur Deployment-Modus zurücksetzen, Tracking bleibt aktiv
    if (await DeploymentState.shouldAutoStop(inactiveMinutes: 180)) {
      await DeploymentState.setMode(DeploymentMode.standby);
      _deploymentMode = DeploymentMode.standby;
      await _updateTrackingMode(service);
      // Tracking bleibt aktiv im Power-Saver-Modus
    }
  });
}

/// Periodischer Flush: alle 3 Minuten ausstehende Positionen an den Server senden
void _schedulePeriodicFlush() {
  _flushTimer?.cancel();
  _flushTimer = Timer.periodic(const Duration(minutes: 3), (_) async {
    try {
      await LocationSyncManager.instance.flushPendingNow(batchSize: 100);
    } catch (_) {}
  });
}

/// Connectivity-Listener: Bei Netzwerk-Wiederherstellung sofort Queue flushen
void _startConnectivityListener() {
  _connectivitySub?.cancel();
  _connectivitySub = Connectivity().onConnectivityChanged.listen((results) async {
    final hasConnection = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
    if (hasConnection) {
      // Netzwerk ist (wieder) da → sofort ausstehende Positionen senden
      try {
        await LocationSyncManager.instance.flushPendingNow(batchSize: 200);
      } catch (_) {}
    }
  });
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  await EdpApi.ensureInitialized();

  _currentStatus = await _readStatusFromPrefs();
  _deploymentMode = await DeploymentState.getMode();
  _trackingMode = await AdaptiveLocationSettings.determineMode(
    deployment: _deploymentMode,
    currentStatus: _currentStatus,
  );

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
    await service.setForegroundNotificationInfo(
      title: 'Trupp App',
      content: _getNotificationContent(),
    );
  }

  // Status-Änderungen lauschen
  service.on('statusChanged').listen((event) async {
    final s = event?['status'];
    if (s is int) {
      _currentStatus = s;
      await DeploymentState.updateActivity();
      await _updateTrackingMode(service);

      if (service is AndroidServiceInstance) {
        await service.setForegroundNotificationInfo(
          title: 'Trupp App',
          content: _getNotificationContent(),
        );
      }
    }
  });

  // Deployment-Modus-Änderungen lauschen
  service.on('updateDeploymentMode').listen((event) async {
    final mode = event?['mode'] as String?;
    if (mode != null) {
      _deploymentMode = DeploymentMode.values.firstWhere(
            (e) => e.name == mode,
        orElse: () => DeploymentMode.standby,
      );
      await _updateTrackingMode(service);

      if (service is AndroidServiceInstance) {
        await service.setForegroundNotificationInfo(
          title: 'Trupp App',
          content: _getNotificationContent(),
        );
      }
    }
  });

  StreamSubscription<Position>? sub;
  bool trackingEnabled = false;

  /// Startet den GPS-Stream mit aktuellen Einstellungen neu
  Future<void> _restartStream() async {
    await sub?.cancel();
    sub = null;

    if (!await _hasValidConfig()) return;

    final locationSettings = AdaptiveLocationSettings.buildSettings(_trackingMode);
    sub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (pos) async => _sendPositionIfOk(service, pos),
      onError: (_) {},
      cancelOnError: false,
    );
  }

  // Callback registrieren, damit _updateTrackingMode den Stream neu starten kann
  _restartStreamCallback = _restartStream;

  /// Startet oder aktualisiert den GPS-Stream mit aktuellen Einstellungen
  Future<void> startTracking() async {
    if (!await _hasValidConfig()) {
      if (service is AndroidServiceInstance) {
        await service.setForegroundNotificationInfo(
          title: 'Trupp App',
          content: 'Keine gültige Konfiguration',
        );
      }
      return;
    }

    await _ensureFullAccuracyIfPossible();
    await _updateTrackingMode(service);

    // Stream neu starten falls bereits aktiv (Mode-Wechsel)
    if (trackingEnabled) {
      await sub?.cancel();
      sub = null;
    }
    trackingEnabled = true;

    final locationSettings = AdaptiveLocationSettings.buildSettings(_trackingMode);
    sub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (pos) async => _sendPositionIfOk(service, pos),
      onError: (_) {},
      cancelOnError: false,
    );

    _scheduleNextHeartbeat(service);
    _schedulePeriodicModeCheck(service);
    _schedulePeriodicFlush();
    _startConnectivityListener();
  }

  /// Wechselt in den Energiesparmodus statt komplett zu stoppen.
  /// GPS bleibt aktiv mit reduzierter Frequenz.
  Future<void> switchToPowerSaver() async {
    _trackingMode = TrackingMode.powerSaver;
    // Stream mit neuen (sparsamen) Einstellungen neu starten
    await sub?.cancel();
    sub = null;

    if (!await _hasValidConfig()) return;

    final locationSettings = AdaptiveLocationSettings.buildSettings(TrackingMode.powerSaver);
    sub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (pos) async => _sendPositionIfOk(service, pos),
      onError: (_) {},
      cancelOnError: false,
    );

    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Trupp App',
        content: 'Hintergrund-Tracking (Status $_currentStatus) - Energiesparmodus',
      );
    }
  }

  Future<void> stopTracking() async {
    if (!trackingEnabled) return;
    trackingEnabled = false;

    await sub?.cancel();
    sub = null;

    _hbTimer?.cancel();
    _hbTimer = null;

    _modeCheckTimer?.cancel();
    _modeCheckTimer = null;

    _flushTimer?.cancel();
    _flushTimer = null;

    _connectivitySub?.cancel();
    _connectivitySub = null;

    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Trupp App',
        content: 'Standby (Status $_currentStatus)',
      );
    }
  }

  service.on('setTracking').listen((event) async {
    final enabled = event?['enabled'] == true;
    if (enabled) {
      await startTracking();
    } else {
      // Statt komplett stoppen: auf Power-Saver wechseln
      // Damit wird auch im Hintergrund weiter getrackt
      await switchToPowerSaver();
    }
  });

  service.on('stopService').listen((_) async {
    await stopTracking();
    await service.stopSelf();
  });
}

const _flushInterval = Duration(minutes: 5);

Future<bool> _shouldFlushNow() async {
  final prefs = await SharedPreferences.getInstance();
  final last = prefs.getInt('lastFlushMs') ?? 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  return (now - last) >= _flushInterval.inMilliseconds;
}

Future<void> _markFlushedNow() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('lastFlushMs', DateTime.now().millisecondsSinceEpoch);
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  try {
    DartPluginRegistrant.ensureInitialized();
    WidgetsFlutterBinding.ensureInitialized();
    await EdpApi.ensureInitialized();

    if (!await _hasValidConfig()) return true;

    _deploymentMode = await DeploymentState.getMode();
    _currentStatus = await _readStatusFromPrefs();
    _trackingMode = await AdaptiveLocationSettings.determineMode(
      deployment: _deploymentMode,
      currentStatus: _currentStatus,
    );

    // 1) aktuellen Fix holen
    Position? pos = await Geolocator.getLastKnownPosition();
    pos ??= await Geolocator.getCurrentPosition(
      locationSettings: AdaptiveLocationSettings.buildSettings(_trackingMode),
    );

    // 2) Qualität prüfen & direkt senden (nicht nur queuen)
    if (_quality.isGood(pos, now: DateTime.now(), forceByHeartbeat: true)) {
      await LocationSyncManager.instance.sendOrQueue(
        lat: pos.latitude,
        lon: pos.longitude,
        accuracy: pos.accuracy.isFinite ? pos.accuracy : null,
        status: _currentStatus,
        timestamp: pos.timestamp,
      );
      _quality.markSent(pos, now: DateTime.now());
    }

    // 3) Alle 5 Min: komplette Queue flushen (Standort-Historie übertragen)
    if (await _shouldFlushNow()) {
      await LocationSyncManager.instance.flushPendingNow(batchSize: 300);
      await _markFlushedNow();
    }
  } catch (_) {}
  return true;
}

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      foregroundServiceNotificationId: 880,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

/// Optionaler Helper für UI-Code
Future<void> stopBackgroundServiceCompletely() async {
  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke('setTracking', {'enabled': false});
    service.invoke('stopService');
  }
}
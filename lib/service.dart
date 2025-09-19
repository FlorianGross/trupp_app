// lib/service.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/edp_api.dart';
import 'data/location_quality.dart';
import 'data/location_sync_manager.dart';

const _minAccuracyMeters = 50.0;     // Fixes schlechter als 100 m werden verworfen
const _minSendInterval = Duration(seconds: 5);
int _currentStatus = 0; // <-- neu: Cache für Statuszahl
const _minDistanceMeters = 5.0;
DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
const _heartbeatInterval = Duration(seconds: 30);

final _quality = LocationQualityFilter(
  maxAccuracyM: _minAccuracyMeters,
  minDistanceM: _minDistanceMeters,
  minInterval: _minSendInterval,
  maxJumpSpeedMs: 20.0,
  heartbeatInterval: _heartbeatInterval,
);

Timer? _hbTimer;

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
      } catch (_) {/* Ignorieren */}
    }
  }
}

Future<void> _sendPositionIfOk(ServiceInstance service, Position pos, {bool forceByHeartbeat = false}) async {
  final now = DateTime.now();

  // Qualität / Drosselung
  if (!_quality.isGood(pos, now: now, forceByHeartbeat: forceByHeartbeat)) {
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Trupp App',
        content: 'Warte auf stabilen GPS-Fix …',
      );
    }
    return;
  }

  if (!await _hasValidConfig()){
    print("No valid config, not sending position.");
    return;}

  try {
    await LocationSyncManager.instance.sendOrQueue(
      lat: pos.latitude,
      lon: pos.longitude,
      accuracy: pos.accuracy.isFinite ? pos.accuracy : null,
      status: _currentStatus,
      timestamp: pos.timestamp ?? now,
    );

    _quality.markSent(pos, now: now);

    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Trupp App',
        content:
        'Status $_currentStatus – ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
      );
    }
  } catch (_) {
    print("Error sending position, queuing.");
    /* still */}
}

Future<void> _heartbeatTick(ServiceInstance service) async {
  try {
    if (!_quality.heartbeatDue()) return;

    Position? pos = await Geolocator.getLastKnownPosition();
    pos ??= await Geolocator.getCurrentPosition(
      locationSettings: _buildLocationSettings(),
    );

    await _sendPositionIfOk(service, pos, forceByHeartbeat: true);
  } catch (_) {
  }
}

LocationSettings _buildLocationSettings() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
      intervalDuration: _minSendInterval,
      forceLocationManager: true,
    );
  } else if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.best,
      activityType: ActivityType.otherNavigation,
      distanceFilter: 15,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );
  } else {
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
    );
  }
}


@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  await EdpApi.ensureInitialized();

  _currentStatus = await _readStatusFromPrefs();

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
    await service.setForegroundNotificationInfo(
      title: 'Trupp App',
      content: 'Standby (Status $_currentStatus)',
    );
  }

  service.on('statusChanged').listen((event) async {
    final s = event?['status'];
    if (s is int) {
      _currentStatus = s;
      if (service is AndroidServiceInstance) {
        await service.setForegroundNotificationInfo(
          title: 'Trupp App',
          content: 'Standby (Status $_currentStatus)',
        );
      }
    }
  });

  StreamSubscription<Position>? sub;
  bool trackingEnabled = false;

  Future<void> startTracking() async {
    if (trackingEnabled) return;
    trackingEnabled = true;

    if (!await _hasValidConfig()) {
      if (service is AndroidServiceInstance) {
        await service.setForegroundNotificationInfo(
          title: 'Trupp App',
          content: 'Keine gültige Konfiguration',
        );
      }
      trackingEnabled = false;
      return;
    }

    await _ensureFullAccuracyIfPossible();
    final locationSettings = _buildLocationSettings();

    sub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (pos) async => _sendPositionIfOk(service, pos),
      onError: (_) {},
      cancelOnError: false,
    );
    _hbTimer?.cancel();
    _hbTimer = Timer.periodic(
      const Duration(seconds: 5),
          (_) => _heartbeatTick(service),
    );
  }

  Future<void> stopTracking() async {
    if (!trackingEnabled) return;
    trackingEnabled = false;

    await sub?.cancel();
    sub = null;

    _hbTimer?.cancel();   // ← NEU
    _hbTimer = null;

    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Trupp App',
        content: 'Standby (Status $_currentStatus)',
      );
    }
  }

  service.on('setTracking').listen((event) async {
    final enabled = event?['enabled'] == true;
    // Nur Flanke behandeln
    if (enabled && !trackingEnabled) {
      await startTracking();
    } else if (!enabled && trackingEnabled) {
      await stopTracking();
    }
  });

  service.on('stopService').listen((_) async {
    await stopTracking();
    await service.stopSelf();
  });
}

const _flushInterval = Duration(minutes: 15);

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

    // 1) aktuellen Fix holen
    Position? pos = await Geolocator.getLastKnownPosition();
    pos ??= await Geolocator.getCurrentPosition(locationSettings: _buildLocationSettings());

    // 2) Qualität grob prüfen & QUEUEN (nicht live senden)
    if (_quality.isGood(pos, now: DateTime.now(), forceByHeartbeat: true)) {
      await LocationSyncManager.instance.queueOnly(
        lat: pos.latitude,
        lon: pos.longitude,
        accuracy: pos.accuracy.isFinite ? pos.accuracy : null,
        status: _currentStatus,
        timestamp: DateTime.now(),
      );
      _quality.markSent(pos, now: DateTime.now()); // nur interne Zeitanker
    }

    // 3) Alle 15 Min: komplette Queue flushen
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
        onBackground: onIosBackground
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
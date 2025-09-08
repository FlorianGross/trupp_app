// lib/service.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

const _minAccuracyMeters = 100.0;     // Fixes schlechter als 100 m werden verworfen
const _minSendInterval = Duration(seconds: 5);
int _currentStatus = 0; // <-- neu: Cache für Statuszahl
DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);


Future<int> _readStatusFromPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt('lastStatus') ?? 0;
}

Future<bool> _hasValidConfig() async {
  final prefs = await SharedPreferences.getInstance();
  final hasConfig = prefs.getBool('hasConfig') ?? false;
  final protocol = prefs.getString('protocol') ?? '';
  final serverPort = prefs.getString('server') ?? '';
  final token = prefs.getString('token') ?? '';
  final issi = prefs.getString('issi') ?? '';
  return hasConfig &&
      protocol.isNotEmpty &&
      serverPort.contains(':') &&
      token.isNotEmpty &&
      issi.isNotEmpty;
}

Future<Uri?> _buildUrl(Position pos) async {
  final prefs = await SharedPreferences.getInstance();
  final protocol = prefs.getString('protocol') ?? 'https';
  final serverPort = prefs.getString('server') ?? 'localhost:443';
  final token = prefs.getString('token') ?? '';
  final issi = prefs.getString('issi') ?? '0000';

  String host = serverPort, port = '443';
  if (serverPort.contains(':')) {
    final parts = serverPort.split(':');
    host = parts[0];
    if (parts.length > 1) port = parts[1];
  }
  final parsedPort = int.tryParse(port) ?? (protocol == 'https' ? 443 : 80);

  if (token.isEmpty || issi.isEmpty) return null;

  return Uri(
    scheme: protocol,
    host: host,
    port: parsedPort,
    pathSegments: [token, 'gpsposition'],
    queryParameters: {
      'issi': issi,
      'lat': pos.latitude.toString().replaceAll('.', ','),
      'lon': pos.longitude.toString().replaceAll('.', ','),
    },
  );
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

bool _isPoorFix(Position pos) {
  final acc = (pos.accuracy.isFinite) ? pos.accuracy : double.infinity;
  final invalidFix = !pos.isMocked &&
      (pos.latitude.abs() < 0.0001 && pos.longitude.abs() < 0.0001);
  return acc > _minAccuracyMeters || invalidFix;
}

Future<void> _sendPositionIfOk(ServiceInstance service, Position pos) async {
  final now = DateTime.now();
  if (now.difference(_lastSent) < _minSendInterval) return;
  if (_isPoorFix(pos)) {
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Trupp App',
        content: 'Warte auf guten GPS-Fix …',
      );
    }
    return;
  }

  if (!await _hasValidConfig()) return;

  final url = await _buildUrl(pos);
  if (url == null) return;

  _lastSent = now;
  try {
    await http.get(url);
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Trupp App',
        content:
        'Status $_currentStatus – Letzte Position: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
      );
    }
  } catch (_) {/* still */}
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
      // Bei Bedarf true setzen, wenn ihr das blaue Banner explizit zeigen wollt:
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
  // Plugins im Isolate initialisieren (wichtig für iOS & Flutter 3+)
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

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

    // Kontinuierlicher Stream NUR im Vordergrund / Android-FG-Service.
    // Unter iOS läuft dieser Callback auch im Vordergrund, im Hintergrund übernimmt onIosBackground ein Einmal-Ping.
    sub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (pos) async => _sendPositionIfOk(service, pos),
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<void> stopTracking() async {
    trackingEnabled = false;
    await sub?.cancel();
    sub = null;
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
      await stopTracking();
    }
  });

  service.on('stopService').listen((_) async {
    await stopTracking();
    await service.stopSelf();
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  try {
    DartPluginRegistrant.ensureInitialized();
    WidgetsFlutterBinding.ensureInitialized();

    if (!await _hasValidConfig()) return true;

    // 1) Last known bevorzugen (sofort), sonst kurzer getCurrentPosition mit Timeouts
    Position? pos = await Geolocator.getLastKnownPosition();
    pos ??= await Geolocator.getCurrentPosition(
      locationSettings: _buildLocationSettings(),
    );

    if (!_isPoorFix(pos)) {
      await _sendPositionIfOk(service, pos);
    }
  } catch (_) {
  }
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
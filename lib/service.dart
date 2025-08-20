// lib/service.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

const _minAccuracyMeters = 100.0;     // Fixes schlechter als 100 m werden verworfen
const _minSendInterval = Duration(seconds: 5);
int _currentStatus = 0; // <-- neu: Cache für Statuszahl

Future<int> _readStatusFromPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt('lastStatus') ?? 0;
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
    _currentStatus = await _readStatusFromPrefs();
    await service.setForegroundNotificationInfo(
      title: 'Trupp App',
      content: 'Standby (Status $_currentStatus)',
    );
  }

  service.on('statusChanged').listen((event) async {
    final s = event?['status'];
    if (s is int) {
      _currentStatus = s; // <-- Cache aktualisieren
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
  DateTime lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  Future<bool> hasValidConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final hasConfig = prefs.getBool('hasConfig') ?? false;
    final protocol = prefs.getString('protocol') ?? '';
    final serverPort = prefs.getString('server') ?? '';
    final token = prefs.getString('token') ?? '';
    final issi = prefs.getString('issi') ?? '';
    // Minimal-Check: Konfig gesetzt & Pflichtfelder nicht leer
    return hasConfig &&
        protocol.isNotEmpty &&
        serverPort.contains(':') &&
        token.isNotEmpty &&
        issi.isNotEmpty;
  }

  Future<void> _ensureFullAccuracyIfPossible() async {
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      final status = await Geolocator.getLocationAccuracy();
      if (status == LocationAccuracyStatus.reduced) {
        // "PreciseTracking" muss im Info.plist unter NSLocationTemporaryUsageDescriptionDictionary existieren
        try {
          await Geolocator.requestTemporaryFullAccuracy(purposeKey: 'PreciseTracking');
        } catch (_) {
          // ignorieren – User kann "Ungefähr" erzwungen haben
        }
      }
    }
  }


  Future<void> startTracking() async {
    if (trackingEnabled) return;
    trackingEnabled = true;

    // Falls keine gültige Config -> nicht starten
    if (!await hasValidConfig()) {
      if (service is AndroidServiceInstance) {
        await service.setForegroundNotificationInfo(
          title: 'Trupp App',
          content: 'Keine gültige Konfiguration',
        );
      }
      trackingEnabled = false;
      return;
    }

    late LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        intervalDuration: _minSendInterval,
        forceLocationManager: true,
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.best,
        activityType: ActivityType.otherNavigation,
        distanceFilter: 15,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: false,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50,
      );
    }
    await _ensureFullAccuracyIfPossible();
    sub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (pos) async {
        // Fix-Qualität prüfen
        final acc = (pos.accuracy.isFinite) ? pos.accuracy : double.infinity;
        final now = DateTime.now();
        final tooSoon = now.difference(lastSent) < _minSendInterval;
        final invalidFix = !pos.isMocked && (pos.latitude.abs() < 0.0001 && pos.longitude.abs() < 0.0001);
        if (tooSoon || acc > _minAccuracyMeters || invalidFix) {
          // Notification optional aktualisieren
          if (service is AndroidServiceInstance) {
            await service.setForegroundNotificationInfo(
              title: 'Trupp App',
              content: 'Warte auf guten GPS-Fix …',
            );
          }
          return;
        }

        // Vor jedem Send erneut prüfen, ob Config valide ist
        if (!await hasValidConfig()) return;

        lastSent = now;

        try {
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

          final url = Uri(
            scheme: protocol,
            host: host,
            port: parsedPort,
            pathSegments: [if (token.isNotEmpty) token, 'gpsposition'],
            queryParameters: {
              'issi': issi,
              'lat': pos.latitude.toString().replaceAll('.', ','),
              'lon': pos.longitude.toString().replaceAll('.', ','),
            },
          );

          await http.get(url);

          if (service is AndroidServiceInstance) {
            await service.setForegroundNotificationInfo(
              title: 'Trupp App',
              content: 'Status $_currentStatus – '
                  'Letzte Position: ${pos.latitude.toStringAsFixed(5)}, '
                  '${pos.longitude.toStringAsFixed(5)}',
            );
          }
        } catch (_) {
          // Fehler stillschweigend ignorieren
        }
      },
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
      onForeground: onStart,
      onBackground: (service) => false,
    ),
  );
}

// Hilfsfunktion (kannst du überall importieren):
Future<void> stopBackgroundServiceCompletely() async {
  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke('setTracking', {'enabled': false});
    service.invoke('stopService');
  }
}

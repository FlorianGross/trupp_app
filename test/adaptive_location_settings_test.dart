import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trupp_app/data/adaptive_location_settings.dart';
import 'package:trupp_app/data/deployment_state.dart';

void main() {
  // Nach jedem Test die statischen Einstellungen auf Default zurücksetzen,
  // damit sich Tests nicht gegenseitig beeinflussen.
  setUp(() {
    AdaptiveLocationSettings.highFrequency = true;
    AdaptiveLocationSettings.preciseLocationOnly = true;
  });

  group('determineMode', () {
    // Im Test-Env wirft battery_plus → Fallback batteryLevel = 100.
    test('aktive Status (1/3/7) → highAccuracy', () async {
      for (final s in [1, 3, 7]) {
        final mode = await AdaptiveLocationSettings.determineMode(
          deployment: DeploymentMode.standby,
          currentStatus: s,
        );
        expect(mode, TrackingMode.highAccuracy,
            reason: 'Status $s sollte highAccuracy sein');
      }
    });

    test('aktive Status auch im Deployment-/Rückweg-Modus → highAccuracy',
        () async {
      final mode = await AdaptiveLocationSettings.determineMode(
        deployment: DeploymentMode.returning,
        currentStatus: 3,
      );
      expect(mode, TrackingMode.highAccuracy);
    });

    test('fester Standort (stationary) bleibt powerSaver', () async {
      final mode = await AdaptiveLocationSettings.determineMode(
        deployment: DeploymentMode.stationary,
        currentStatus: 3,
      );
      expect(mode, TrackingMode.powerSaver);
    });

    test('inaktiver Status in Bereitschaft → powerSaver', () async {
      final mode = await AdaptiveLocationSettings.determineMode(
        deployment: DeploymentMode.standby,
        currentStatus: 2,
      );
      expect(mode, TrackingMode.powerSaver);
    });

    test('inaktiver Status auf Rückweg → balanced', () async {
      final mode = await AdaptiveLocationSettings.determineMode(
        deployment: DeploymentMode.returning,
        currentStatus: 2,
      );
      expect(mode, TrackingMode.balanced);
    });
  });

  group('getMaxAccuracy (nur präziser Standort / WLAN-Filter)', () {
    test('preciseLocationOnly schließt grobe WLAN-Fixes aus', () {
      AdaptiveLocationSettings.preciseLocationOnly = true;
      expect(AdaptiveLocationSettings.getMaxAccuracy(TrackingMode.highAccuracy),
          lessThanOrEqualTo(25.0));
      expect(AdaptiveLocationSettings.getMaxAccuracy(TrackingMode.balanced),
          lessThanOrEqualTo(40.0));
    });

    test('ausgeschaltet → großzügigere Schwellen (grob besser als nichts)', () {
      AdaptiveLocationSettings.preciseLocationOnly = true;
      final strict =
          AdaptiveLocationSettings.getMaxAccuracy(TrackingMode.highAccuracy);
      AdaptiveLocationSettings.preciseLocationOnly = false;
      final loose =
          AdaptiveLocationSettings.getMaxAccuracy(TrackingMode.highAccuracy);
      expect(loose, greaterThan(strict));
    });
  });

  group('getHeartbeatInterval (Frequenz-Einstellung)', () {
    test('highFrequency → kürzerer Heartbeat als Sparmodus', () {
      AdaptiveLocationSettings.highFrequency = true;
      final fast = AdaptiveLocationSettings.getHeartbeatInterval(
          TrackingMode.highAccuracy, false);
      AdaptiveLocationSettings.highFrequency = false;
      final slow = AdaptiveLocationSettings.getHeartbeatInterval(
          TrackingMode.highAccuracy, false);
      expect(fast, lessThan(slow));
    });
  });

  group('buildSettings (Android Distanzfilter)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('balanced-Distanzfilter ist 10 m bei highFrequency', () {
      AdaptiveLocationSettings.highFrequency = true;
      final settings =
          AdaptiveLocationSettings.buildSettings(TrackingMode.balanced);
      expect(settings.distanceFilter, 10);
    });
  });
}

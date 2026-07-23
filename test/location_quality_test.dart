import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trupp_app/data/location_quality.dart';

Position _pos({
  required double lat,
  required double lon,
  required double accuracy,
  required DateTime ts,
}) {
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: ts,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);
  final t10 = t0.add(const Duration(seconds: 10));

  LocationQualityFilter makeFilter() => LocationQualityFilter(
        maxAccuracyM: 25.0,
        minDistanceM: 8.0,
        minInterval: const Duration(seconds: 5),
        maxJumpSpeedMs: 55.0,
      );

  test('ungenauer Fix wird verworfen (WLAN-/Funkzellen-Ortung)', () {
    final f = makeFilter();
    final p = _pos(lat: 52.0, lon: 13.0, accuracy: 120, ts: t0);
    expect(f.isGood(p, now: t0), isFalse);
  });

  test('Teleport wird verworfen – AUCH per Heartbeat (Plausibilität gilt immer)',
      () {
    final f = makeFilter();
    f.markSent(_pos(lat: 52.0, lon: 13.0, accuracy: 10, ts: t0), now: t0);
    // ~11 km in 10 s ⇒ ~1100 m/s ≫ 55 m/s.
    final jump = _pos(lat: 52.1, lon: 13.0, accuracy: 10, ts: t10);
    expect(f.isGood(jump, now: t10), isFalse);
    expect(f.isGood(jump, now: t10, forceByHeartbeat: true), isFalse,
        reason: 'Ein Teleport darf auch als Heartbeat nicht durchrutschen');
  });

  test('Heartbeat überspringt nur die Mindestdistanz (Stillstand darf senden)',
      () {
    final f = makeFilter();
    f.markSent(_pos(lat: 52.0, lon: 13.0, accuracy: 10, ts: t0), now: t0);
    // ~1 m Bewegung (< 8 m Mindestdistanz).
    final tiny = _pos(lat: 52.00001, lon: 13.0, accuracy: 10, ts: t10);
    expect(f.isGood(tiny, now: t10), isFalse,
        reason: 'Stream-Fix unter Mindestdistanz wird verworfen');
    expect(f.isGood(tiny, now: t10, forceByHeartbeat: true), isTrue,
        reason: 'Heartbeat darf trotz kleiner Distanz senden');
  });

  test('Resync überspringt Plausibilität, aber NICHT die Genauigkeit', () {
    final f = makeFilter();
    f.markSent(_pos(lat: 52.0, lon: 13.0, accuracy: 10, ts: t0), now: t0);
    final jumpAccurate = _pos(lat: 52.1, lon: 13.0, accuracy: 10, ts: t10);
    final jumpInaccurate = _pos(lat: 52.1, lon: 13.0, accuracy: 120, ts: t10);

    // Ohne Resync: Sprung verworfen.
    expect(f.isGood(jumpAccurate, now: t10), isFalse);
    // Mit Resync: genauer Sprung akzeptiert (Referenz „klemmte").
    expect(f.isGood(jumpAccurate, now: t10, allowResync: true), isTrue);
    // Mit Resync: ungenauer Fix bleibt verworfen (kein grober WLAN-Fix).
    expect(f.isGood(jumpInaccurate, now: t10, allowResync: true), isFalse);
  });

  test('Warm-up: in den ersten Sekunden strengere Genauigkeit', () {
    final f = LocationQualityFilter(
      maxAccuracyM: 40,
      minDistanceM: 8,
      minInterval: const Duration(seconds: 5),
      maxJumpSpeedMs: 55,
      warmupDuration: const Duration(seconds: 6),
      warmupMaxAccuracyM: 15,
    );
    f.startWarmup(now: t0);
    // 25 m < maxAccuracy(40), aber > 15 m Warm-up-Grenze → verworfen.
    final p = _pos(lat: 52.0, lon: 13.0, accuracy: 25, ts: t0);
    expect(f.isGood(p, now: t0), isFalse);
    // Nach Ablauf des Warm-ups akzeptiert.
    final later = t0.add(const Duration(seconds: 7));
    final p2 = _pos(lat: 52.0, lon: 13.0, accuracy: 25, ts: later);
    expect(f.isGood(p2, now: later), isTrue);
  });

  test('Adaptive Schwelle: Fix weit über dem Genauigkeits-Trend verworfen', () {
    final f = LocationQualityFilter(
      maxAccuracyM: 60,
      minDistanceM: 8,
      minInterval: Duration.zero,
      maxJumpSpeedMs: 55,
      adaptiveFactor: 2.5,
      adaptiveFloorM: 20,
    );
    // Guten Trend (acc ~5 m) etablieren.
    for (var i = 0; i < 5; i++) {
      final ts = t0.add(Duration(seconds: i));
      final p = _pos(lat: 52.0 + i * 0.0001, lon: 13.0, accuracy: 5, ts: ts);
      expect(f.isGood(p, now: ts), isTrue);
      f.markSent(p, now: ts);
    }
    // 30 m: < maxAccuracy(60), aber > 5·2.5 und > 20 → adaptiv verworfen.
    final tsBad = t0.add(const Duration(seconds: 5));
    final bad = _pos(lat: 52.0006, lon: 13.0, accuracy: 30, ts: tsBad);
    expect(f.isGood(bad, now: tsBad), isFalse);
  });
}

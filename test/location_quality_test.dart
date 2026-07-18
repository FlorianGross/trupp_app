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
  group('LocationQualityFilter Notnagel-Fallback', () {
    late LocationQualityFilter filter;
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);

    setUp(() {
      filter = LocationQualityFilter(
        maxAccuracyM: 25.0,
        minDistanceM: 8.0,
        minInterval: const Duration(seconds: 5),
      );
    });

    test('ungenauer Fix wird von isGood verworfen', () {
      final p = _pos(lat: 52.0, lon: 13.0, accuracy: 120, ts: t0);
      expect(filter.isGood(p, now: t0), isFalse);
    });

    test('derselbe Fix ist als Notnagel akzeptabel (innerhalb Cap)', () {
      final p = _pos(lat: 52.0, lon: 13.0, accuracy: 120, ts: t0);
      expect(
        filter.isAcceptableFallback(p, now: t0, fallbackMaxAccuracyM: 150),
        isTrue,
      );
    });

    test('jenseits des Fallback-Caps wird auch der Notnagel verworfen', () {
      final p = _pos(lat: 52.0, lon: 13.0, accuracy: 200, ts: t0);
      expect(
        filter.isAcceptableFallback(p, now: t0, fallbackMaxAccuracyM: 150),
        isFalse,
      );
    });

    test('Mindest-Intervall bleibt auch im Fallback gewahrt (kein Spam)', () {
      final first = _pos(lat: 52.0, lon: 13.0, accuracy: 10, ts: t0);
      filter.markSent(first, now: t0);
      final soon = _pos(
        lat: 52.001,
        lon: 13.001,
        accuracy: 120,
        ts: t0.add(const Duration(seconds: 2)),
      );
      expect(
        filter.isAcceptableFallback(soon,
            now: t0.add(const Duration(seconds: 2)),
            fallbackMaxAccuracyM: 150),
        isFalse,
      );
    });
  });
}

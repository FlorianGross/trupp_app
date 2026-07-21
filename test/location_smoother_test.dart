import 'package:flutter_test/flutter_test.dart';
import 'package:trupp_app/data/location_smoother.dart';

void main() {
  test('erster Fix wird unverändert übernommen', () {
    final s = LocationSmoother();
    final r = s.process(lat: 52.0, lon: 13.0, accuracyM: 10, tsMs: 0);
    expect(r.lat, 52.0);
    expect(r.lon, 13.0);
    expect(r.accuracy, 10);
  });

  test('wiederholt identischer Fix im Stand → Position stabil, Genauigkeit '
      'verbessert sich', () {
    final s = LocationSmoother();
    var acc = 10.0;
    for (var i = 0; i < 8; i++) {
      final r = s.process(
        lat: 52.0,
        lon: 13.0,
        accuracyM: 10,
        tsMs: i * 1000,
        speedMs: 0,
      );
      expect(r.lat, closeTo(52.0, 1e-9));
      expect(r.lon, closeTo(13.0, 1e-9));
      acc = r.accuracy;
    }
    // Nach mehreren Messungen ist die geschätzte Ungenauigkeit kleiner als die
    // Einzel-Messung (Mehrwert der Glättung).
    expect(acc, lessThan(10.0));
  });

  test('verrauschte Fixes im Stand bleiben nahe der Mitte', () {
    final s = LocationSmoother(minProcessNoiseMs: 3.0);
    // ~0.00015° ≈ 16 m Streuung um das Zentrum, abwechselnd.
    const center = 52.0;
    var last = center;
    for (var i = 0; i < 20; i++) {
      final noisy = center + (i.isEven ? 0.00015 : -0.00015);
      final r = s.process(
        lat: noisy,
        lon: 13.0,
        accuracyM: 15,
        tsMs: i * 1000,
        speedMs: 0,
      );
      last = r.lat;
    }
    // Geglättete Position liegt deutlich näher an der Mitte als die Rohstreuung.
    expect((last - center).abs(), lessThan(0.00008));
  });

  test('bei hoher Geschwindigkeit folgt der Filter der Bewegung', () {
    final s = LocationSmoother();
    double lon = 13.0;
    var r = s.process(lat: 52.0, lon: lon, accuracyM: 5, tsMs: 0, speedMs: 60);
    for (var i = 1; i <= 8; i++) {
      lon += 0.0009; // ~60 m/s nach Osten
      r = s.process(
        lat: 52.0,
        lon: lon,
        accuracyM: 5,
        tsMs: i * 1000,
        speedMs: 60,
      );
    }
    // Der Filter darf bei schneller Fahrt kaum nachlaufen.
    expect((r.lon - lon).abs(), lessThan(0.0003)); // < ~20 m
  });

  test('reset() verwirft den Schätzwert', () {
    final s = LocationSmoother();
    s.process(lat: 52.0, lon: 13.0, accuracyM: 10, tsMs: 0);
    expect(s.hasEstimate, isTrue);
    s.reset();
    expect(s.hasEstimate, isFalse);
    // Nach reset zählt der nächste Fix wieder als erster.
    final r = s.process(lat: 48.0, lon: 11.0, accuracyM: 8, tsMs: 5000);
    expect(r.lat, 48.0);
    expect(r.lon, 11.0);
  });
}

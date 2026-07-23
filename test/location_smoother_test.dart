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

  test('Stillstand: Anker friert die Position ein (kein Drift), Genauigkeit '
      'verbessert sich', () {
    final s = LocationSmoother();
    const center = 52.0;
    var lastLat = center;
    var lastAcc = 15.0;
    for (var i = 0; i < 20; i++) {
      // ~5,5 m Jitter, abwechselnd; Geschwindigkeit ~ 0 (steht). Bewusst
      // INNERHALB des Anker-Freigaberadius (20 m) — sonst würde der Anker
      // auslösen und der Kalman übernehmen (dann testet dieser Fall nicht den
      // Anker). ±0.00005° ≈ 5,5 m, Sample-zu-Sample also ~11 m (< 20 m).
      final noisy = center + (i.isEven ? 0.00005 : -0.00005);
      final r = s.process(
        lat: noisy,
        lon: 13.0,
        accuracyM: 15,
        tsMs: i * 1000,
        speedMs: 0,
      );
      lastLat = r.lat;
      lastAcc = r.accuracy;
    }
    expect((lastLat - center).abs(), lessThan(0.00003)); // < ~3 m Drift
    expect(lastAcc, lessThan(15.0)); // Mittelung verbessert die Genauigkeit
  });

  test('Bewegung mit konstanter Geschwindigkeit wird verfolgt (kein Nachlauf)',
      () {
    final s = LocationSmoother();
    const lon0 = 13.0;
    const step = 0.0009; // ~60 m/s nach Osten
    var r = s.process(lat: 52.0, lon: lon0, accuracyM: 5, tsMs: 0, speedMs: 60);
    var lon = lon0;
    for (var i = 1; i <= 20; i++) {
      lon = lon0 + i * step;
      r = s.process(lat: 52.0, lon: lon, accuracyM: 5, tsMs: i * 1000, speedMs: 60);
    }
    // Nach Konvergenz folgt der CV-Filter praktisch verzögerungsfrei.
    expect((r.lon - lon).abs(), lessThan(0.0003)); // < ~20 m
  });

  test('einzelner Ausreißer (Spike) wird verworfen', () {
    final s = LocationSmoother();
    const lon0 = 13.0;
    const step = 0.0009;
    // Erst Geschwindigkeit einschwingen lassen.
    for (var i = 0; i <= 8; i++) {
      s.process(
        lat: 52.0,
        lon: lon0 + i * step,
        accuracyM: 5,
        tsMs: i * 1000,
        speedMs: 60,
      );
    }
    // Nächster Schritt: grober Spike (~700 m daneben) statt der Rampe.
    final expectedLon = lon0 + 9 * step;
    final r = s.process(
      lat: 52.0,
      lon: expectedLon + 0.01, // Spike
      accuracyM: 5,
      tsMs: 9 * 1000,
      speedMs: 60,
    );
    // Ausgabe bleibt nahe der erwarteten Rampe, NICHT beim Spike.
    expect((r.lon - expectedLon).abs(), lessThan(0.0003)); // < ~20 m
  });

  test('reset() verwirft den Schätzwert', () {
    final s = LocationSmoother();
    s.process(lat: 52.0, lon: 13.0, accuracyM: 10, tsMs: 0);
    expect(s.hasEstimate, isTrue);
    s.reset();
    expect(s.hasEstimate, isFalse);
    final r = s.process(lat: 48.0, lon: 11.0, accuracyM: 8, tsMs: 5000);
    expect(r.lat, 48.0);
    expect(r.lon, 11.0);
  });
}

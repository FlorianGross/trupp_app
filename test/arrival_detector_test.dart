import 'package:flutter_test/flutter_test.dart';
import 'package:trupp_app/data/arrival_detector.dart';
import 'package:trupp_app/data/arrival_target.dart';

void main() {
  // Feuerwache als Referenzpunkt; die Testkoordinaten liegen alle in der Nähe.
  const wache = ArrivalTarget(
    kind: ArrivalTargetKind.wache,
    lat: 48.1371,
    lon: 11.5754,
    label: 'Wache',
    suggestedStatus: 2,
    radiusM: 120,
  );

  const einsatz = ArrivalTarget(
    kind: ArrivalTargetKind.einsatz,
    lat: 48.1500,
    lon: 11.5800,
    label: 'Musterstraße 1',
    suggestedStatus: 4,
    radiusM: 200,
  );

  /// Verschiebt eine Koordinate um [meters] nach Norden.
  double latOffset(double lat, double meters) => lat + (meters / 111320.0);

  group('distanceMeters', () {
    test('gleicher Punkt → 0', () {
      expect(
        ArrivalDetector.distanceMeters(48.1371, 11.5754, 48.1371, 11.5754),
        closeTo(0, 0.001),
      );
    });

    test('1000 m Nordversatz → ~1000 m', () {
      final d = ArrivalDetector.distanceMeters(
          48.1371, 11.5754, latOffset(48.1371, 1000), 11.5754);
      expect(d, closeTo(1000, 5));
    });
  });

  group('Ankunft', () {
    test('Anfahrt von außen nach innen meldet Ankunft', () {
      final det = ArrivalDetector();

      // Start deutlich außerhalb (500 m) → keine Meldung, aber scharf gestellt.
      expect(
        det.evaluate(
          lat: latOffset(wache.lat, 500),
          lon: wache.lon,
          accuracyM: 10,
          targets: [wache],
        ),
        isNull,
      );

      // Ankunft im Radius.
      final event = det.evaluate(
        lat: wache.lat,
        lon: wache.lon,
        accuracyM: 10,
        targets: [wache],
      );
      expect(event, isNotNull);
      expect(event!.target.kind, ArrivalTargetKind.wache);
      expect(event.target.suggestedStatus, 2);
      expect(event.distanceM, closeTo(0, 1));
    });

    test('Start innerhalb des Radius meldet nichts', () {
      final det = ArrivalDetector();

      // Wer auf der Wache einschaltet, ist nicht „angekommen".
      expect(
        det.evaluate(
          lat: wache.lat,
          lon: wache.lon,
          accuracyM: 10,
          targets: [wache],
        ),
        isNull,
      );
    });

    test('meldet nur einmal pro Ankunft', () {
      final det = ArrivalDetector();
      det.evaluate(
          lat: latOffset(wache.lat, 500),
          lon: wache.lon,
          accuracyM: 10,
          targets: [wache]);

      expect(
        det.evaluate(
            lat: wache.lat, lon: wache.lon, accuracyM: 10, targets: [wache]),
        isNotNull,
      );
      // Weitere Fixes am selben Ort dürfen nicht erneut nachfragen.
      for (var i = 0; i < 5; i++) {
        expect(
          det.evaluate(
              lat: wache.lat, lon: wache.lon, accuracyM: 10, targets: [wache]),
          isNull,
        );
      }
    });

    test('Zappeln an der Radiusgrenze löst keine zweite Meldung aus', () {
      final det = ArrivalDetector();
      det.evaluate(
          lat: latOffset(wache.lat, 500),
          lon: wache.lon,
          accuracyM: 10,
          targets: [wache]);
      expect(
        det.evaluate(
            lat: wache.lat, lon: wache.lon, accuracyM: 10, targets: [wache]),
        isNotNull,
      );

      // Knapp raus (150 m, Radius 120, Re-Arm erst ab 180 m) und wieder rein.
      det.evaluate(
          lat: latOffset(wache.lat, 150),
          lon: wache.lon,
          accuracyM: 10,
          targets: [wache]);
      expect(
        det.evaluate(
            lat: wache.lat, lon: wache.lon, accuracyM: 10, targets: [wache]),
        isNull,
      );
    });

    test('nach echtem Verlassen wird erneut gemeldet', () {
      final det = ArrivalDetector();
      det.evaluate(
          lat: latOffset(wache.lat, 500),
          lon: wache.lon,
          accuracyM: 10,
          targets: [wache]);
      expect(
        det.evaluate(
            lat: wache.lat, lon: wache.lon, accuracyM: 10, targets: [wache]),
        isNotNull,
      );

      // Deutlich weg (über Re-Arm-Schwelle) …
      det.evaluate(
          lat: latOffset(wache.lat, 400),
          lon: wache.lon,
          accuracyM: 10,
          targets: [wache]);
      // … und zurück → das ist eine neue Ankunft.
      expect(
        det.evaluate(
            lat: wache.lat, lon: wache.lon, accuracyM: 10, targets: [wache]),
        isNotNull,
      );
    });
  });

  group('Robustheit', () {
    test('ungenaue Fixes werden ignoriert', () {
      final det = ArrivalDetector();
      det.evaluate(
          lat: latOffset(wache.lat, 500),
          lon: wache.lon,
          accuracyM: 10,
          targets: [wache]);

      // ±500 m Fix mitten im Radius darf keine Rückfrage auslösen.
      expect(
        det.evaluate(
            lat: wache.lat, lon: wache.lon, accuracyM: 500, targets: [wache]),
        isNull,
      );

      // Ein genauer Fix danach schon.
      expect(
        det.evaluate(
            lat: wache.lat, lon: wache.lon, accuracyM: 10, targets: [wache]),
        isNotNull,
      );
    });

    test('ohne Ziele passiert nichts', () {
      final det = ArrivalDetector();
      expect(
        det.evaluate(
            lat: wache.lat, lon: wache.lon, accuracyM: 10, targets: const []),
        isNull,
      );
    });

    test('Einsatzort hat Vorrang vor der Wache', () {
      // Ziel und Wache am selben Ort (Einsatz direkt an der Wache).
      const wacheGleich = ArrivalTarget(
        kind: ArrivalTargetKind.wache,
        lat: 48.1500,
        lon: 11.5800,
        label: 'Wache',
        suggestedStatus: 2,
      );
      final det = ArrivalDetector();
      det.evaluate(
          lat: latOffset(einsatz.lat, 1000),
          lon: einsatz.lon,
          accuracyM: 10,
          targets: [einsatz, wacheGleich]);

      final event = det.evaluate(
        lat: einsatz.lat,
        lon: einsatz.lon,
        accuracyM: 10,
        targets: [einsatz, wacheGleich],
      );
      expect(event, isNotNull);
      expect(event!.target.kind, ArrivalTargetKind.einsatz);
      expect(event.target.suggestedStatus, 4);
    });

    test('entfallenes Ziel setzt seinen Zustand zurück', () {
      final det = ArrivalDetector();
      det.evaluate(
          lat: latOffset(wache.lat, 500),
          lon: wache.lon,
          accuracyM: 10,
          targets: [wache]);
      expect(
        det.evaluate(
            lat: wache.lat, lon: wache.lon, accuracyM: 10, targets: [wache]),
        isNotNull,
      );

      // Ziel entfernt (Einsatz beendet) und neu gesetzt: der Wagen steht noch
      // am selben Ort → das ist keine neue Ankunft.
      det.evaluate(
          lat: wache.lat, lon: wache.lon, accuracyM: 10, targets: const []);
      expect(
        det.evaluate(
            lat: wache.lat, lon: wache.lon, accuracyM: 10, targets: [wache]),
        isNull,
      );
    });
  });

  group('ArrivalTarget.fromJson', () {
    test('Round-Trip', () {
      final json = einsatz.toJson();
      final back = ArrivalTarget.fromJson(json);
      expect(back, isNotNull);
      expect(back!.kind, ArrivalTargetKind.einsatz);
      expect(back.lat, einsatz.lat);
      expect(back.lon, einsatz.lon);
      expect(back.radiusM, einsatz.radiusM);
      expect(back.suggestedStatus, 4);
      expect(back.label, 'Musterstraße 1');
    });

    test('0/0 wird verworfen', () {
      expect(
        ArrivalTarget.fromJson({
          'kind': 'einsatz',
          'lat': 0.0,
          'lon': 0.0,
          'suggestedStatus': 4,
        }),
        isNull,
      );
    });

    test('unbekannte Sorte wird verworfen', () {
      expect(
        ArrivalTarget.fromJson({
          'kind': 'irgendwas',
          'lat': 48.1,
          'lon': 11.5,
          'suggestedStatus': 4,
        }),
        isNull,
      );
    });

    test('fehlende Pflichtfelder werden verworfen', () {
      expect(ArrivalTarget.fromJson({'kind': 'wache', 'lat': 48.1}), isNull);
    });
  });
}

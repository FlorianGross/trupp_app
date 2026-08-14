// lib/data/arrival_detector.dart
//
// Erkennt die Ankunft an einem hinterlegten Ziel (siehe arrival_target.dart)
// und liefert daraus einen Statusvorschlag.
//
// Bewusst ohne Plugin-Abhängigkeit (eigene Haversine-Distanz statt
// Geolocator.distanceBetween), damit die Logik in Unit-Tests ohne Gerät läuft.
//
// Die Fallstricke, gegen die hier abgesichert wird:
//
//  1. Ungenaue Fixes. Ein WLAN-Fix mit ±500 m „springt" gerne mal in den
//     Radius. Solche Fixes werden ignoriert, statt eine Rückfrage auszulösen,
//     die den Fahrer während der Fahrt ablenkt.
//  2. Start innerhalb des Radius. Wer auf der Wache einschaltet, ist schon da —
//     das ist keine Ankunft. Es wird nur eine echte Bewegung von außen nach
//     innen gemeldet.
//  3. Zappeln an der Radiusgrenze. Ohne Hysterese würde ein Fahrzeug, das am
//     Rand des Radius parkt, dauernd neue Vorschläge auslösen. Re-Armiert wird
//     erst deutlich außerhalb.
import 'dart:math' as math;

import 'arrival_target.dart';

class ArrivalEvent {
  final ArrivalTarget target;
  final double distanceM;

  const ArrivalEvent({required this.target, required this.distanceM});
}

class ArrivalDetector {
  /// Fixes, die ungenauer sind als das hier, werden für die Ankunfts-Erkennung
  /// verworfen — sie können den Radius nicht zuverlässig entscheiden.
  final double maxAccuracyM;

  /// Faktor auf den Radius, ab dem ein Ziel wieder „scharf" gestellt wird.
  final double rearmFactor;

  ArrivalDetector({this.maxAccuracyM = 100.0, this.rearmFactor = 1.5});

  /// Zustand je Ziel: true = zuletzt innerhalb des Radius gesehen.
  /// Fehlt der Eintrag, wurde das Ziel noch nie bewertet.
  final Map<ArrivalTargetKind, bool> _inside = {};

  /// Vergisst den Zustand eines Ziels (z. B. wenn ein neues Ziel gesetzt wird).
  void reset([ArrivalTargetKind? kind]) {
    if (kind == null) {
      _inside.clear();
    } else {
      _inside.remove(kind);
    }
  }

  /// Bewertet eine Position gegen alle [targets].
  ///
  /// Liefert das Ziel, an dem gerade eine Ankunft stattgefunden hat, sonst
  /// null. Bei mehreren passenden Zielen gewinnt das erste in [targets] —
  /// die Reihenfolge aus [ArrivalTargetStore.loadAll] stellt den Einsatzort
  /// vor die Wache.
  ArrivalEvent? evaluate({
    required double lat,
    required double lon,
    required double accuracyM,
    required List<ArrivalTarget> targets,
  }) {
    // Zustand für entfallene Ziele aufräumen, damit ein später erneut
    // gesetztes Ziel nicht mit altem „ist schon drin" startet.
    final present = targets.map((t) => t.kind).toSet();
    _inside.removeWhere((kind, _) => !present.contains(kind));

    if (!accuracyM.isFinite || accuracyM > maxAccuracyM) return null;

    ArrivalEvent? event;
    for (final target in targets) {
      final distance = distanceMeters(lat, lon, target.lat, target.lon);
      final wasInside = _inside[target.kind];
      final isInside = distance <= target.radiusM;

      if (isInside) {
        _inside[target.kind] = true;
        // Nur eine echte Bewegung von außen nach innen ist eine Ankunft.
        // wasInside == null heißt „erste Bewertung" — wer beim Einschalten
        // schon da steht, ist nicht angekommen.
        if (wasInside == false && event == null) {
          event = ArrivalEvent(target: target, distanceM: distance);
        }
      } else if (distance > target.radiusM * rearmFactor) {
        // Erst deutlich außerhalb wieder scharf stellen (Hysterese).
        _inside[target.kind] = false;
      } else if (wasInside == null) {
        // Zwischen Radius und Re-Arm-Schwelle, aber noch nie bewertet: als
        // „außerhalb" merken, sonst käme es nie zu einer ersten Ankunft.
        _inside[target.kind] = false;
      }
    }
    return event;
  }

  /// Haversine-Distanz in Metern.
  static double distanceMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusM = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusM * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;
}

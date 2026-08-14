// lib/data/arrival_target.dart
//
// Ziele für die Ankunfts-Erkennung (Geofence).
//
// Zwei Sorten, die sich im Einsatzalltag unterscheiden:
//  • einsatz — der aktuelle Einsatzort. Wird beim Ausrücken gesetzt (Pro:
//    „Als Ziel setzen" am Einsatz) und beim Einsatzende wieder gelöscht.
//  • wache — der eigene Standort. Wird einmalig in den Einstellungen
//    hinterlegt und bleibt dauerhaft bestehen.
//
// Beide werden als JSON in den SharedPreferences abgelegt, damit auch der
// Hintergrund-Isolate sie lesen kann (dort gibt es keinen gemeinsamen
// Speicher mit der UI).
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum ArrivalTargetKind { einsatz, wache }

class ArrivalTarget {
  final ArrivalTargetKind kind;
  final double lat;
  final double lon;

  /// Radius, ab dem die Ankunft gilt. Bewusst großzügig: die Einsatzadresse
  /// ist selten exakt der Punkt, an dem das Fahrzeug hält.
  final double radiusM;

  /// Klartext für die Rückfrage im Display („Ziel erreicht – Musterstraße 1").
  final String label;

  /// Status, der bei Ankunft vorgeschlagen wird (4 = Ziel erreicht,
  /// 2 = Einsatzbereit Wache).
  final int suggestedStatus;

  const ArrivalTarget({
    required this.kind,
    required this.lat,
    required this.lon,
    required this.label,
    required this.suggestedStatus,
    this.radiusM = defaultRadiusM,
  });

  static const defaultRadiusM = 150.0;

  /// Am Einsatzort ist der Halteort oft ein Stück von der gemeldeten Adresse
  /// entfernt (Zufahrt, Bereitstellungsraum) — deshalb weiter gefasst als die
  /// Wache, deren Position exakt hinterlegt ist.
  static const einsatzRadiusM = 200.0;
  static const wacheRadiusM = 120.0;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'lat': lat,
        'lon': lon,
        'radiusM': radiusM,
        'label': label,
        'suggestedStatus': suggestedStatus,
      };

  static ArrivalTarget? fromJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final lon = (j['lon'] as num?)?.toDouble();
    final status = (j['suggestedStatus'] as num?)?.toInt();
    if (lat == null || lon == null || status == null) return null;
    if (!_isPlausible(lat, lon)) return null;

    final kindName = j['kind'] as String?;
    ArrivalTargetKind? kind;
    for (final k in ArrivalTargetKind.values) {
      if (k.name == kindName) {
        kind = k;
        break;
      }
    }
    if (kind == null) return null;

    return ArrivalTarget(
      kind: kind,
      lat: lat,
      lon: lon,
      radiusM: (j['radiusM'] as num?)?.toDouble() ?? defaultRadiusM,
      label: (j['label'] as String?) ?? '',
      suggestedStatus: status,
    );
  }

  /// 0/0 ist der klassische „keine Koordinate"-Platzhalter der Leitstelle und
  /// liegt im Atlantik — ein Ziel dort wäre immer falsch.
  static bool _isPlausible(double lat, double lon) {
    if (lat == 0.0 && lon == 0.0) return false;
    if (lat.isNaN || lon.isNaN) return false;
    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }
}

abstract final class ArrivalTargetStore {
  static String _key(ArrivalTargetKind kind) => 'arrival_target_${kind.name}';

  static Future<void> save(ArrivalTarget target) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(target.kind), jsonEncode(target.toJson()));
  }

  static Future<void> clear(ArrivalTargetKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(kind));
  }

  static Future<ArrivalTarget?> load(ArrivalTargetKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_key(kind)));
  }

  /// Alle gesetzten Ziele — die Reihenfolge entscheidet bei Überschneidung:
  /// Steht die Wache zufällig im Einsatzradius, gewinnt der Einsatzort.
  static Future<List<ArrivalTarget>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    // reload(), weil der Hintergrund-Isolate sonst einen Stand von vor dem
    // Setzen des Ziels sieht (eigener Prefs-Cache pro Isolate).
    await prefs.reload();
    final targets = <ArrivalTarget>[];
    for (final kind in ArrivalTargetKind.values) {
      final t = _decode(prefs.getString(_key(kind)));
      if (t != null) targets.add(t);
    }
    return targets;
  }

  static ArrivalTarget? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return ArrivalTarget.fromJson(decoded);
    } catch (_) {
      // Kaputter Eintrag darf die Ortung nicht blockieren.
      return null;
    }
  }
}

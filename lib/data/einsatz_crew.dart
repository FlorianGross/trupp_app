// lib/data/einsatz_crew.dart
//
// „Wer ist sonst noch auf diesem Einsatz?" — die Fahrzeuge, die mit dem
// eigenen auf demselben Einsatz laufen, für die Anzeige im Fahrzeug-Display.
//
// Der Einsatz wird NICHT von Hand gewählt, sondern von der Leitstelle
// abgeleitet: Sie weiß ohnehin, auf welchem Einsatz das eigene Fahrzeug
// disponiert ist. Der Weg dorthin:
//
//   eigene ISSI (Prefs)
//     → Tetra-Endgeräte  → rufname des eigenen Geräts
//       → Einsatzmittel   → einsatznummer des eigenen Fahrzeugs
//         → alle Einsatzmittel mit derselben einsatznummer
//
// Die Zuordnung ISSI→Rufname ändert sich praktisch nie und wird deshalb
// gepuffert; die Einsatzmittel selbst werden bei jeder Abfrage frisch geholt.
//
// Die Auswertung ist bewusst von den HTTP-Aufrufen getrennt (reine Funktionen
// in [EinsatzCrewResolver]), damit sie ohne Server testbar bleibt.
import 'edp_api.dart';
import 'edp_api_pro.dart';

/// Ein Fahrzeug auf dem Einsatz, aufbereitet für die Anzeige im Auto.
class CrewMember {
  final String rufname;
  final String? status;
  final String? typ;
  final String? abschnitt;
  final int? besatzung;

  /// Das eigene Fahrzeug — wird in der Liste zuerst und markiert angezeigt.
  final bool isOwn;

  const CrewMember({
    required this.rufname,
    this.status,
    this.typ,
    this.abschnitt,
    this.besatzung,
    this.isOwn = false,
  });

  /// Zweite Zeile im Display: Status, Besatzung und Abschnitt, soweit bekannt.
  String get detail {
    final parts = <String>[];
    if (status != null && status!.isNotEmpty) parts.add('Status $status');
    if (besatzung != null && besatzung! > 0) parts.add('Bes. $besatzung');
    if (abschnitt != null && abschnitt!.isNotEmpty) parts.add(abschnitt!);
    if (parts.isEmpty && typ != null && typ!.isNotEmpty) parts.add(typ!);
    return parts.join(' • ');
  }

  Map<String, dynamic> toMap() => {
        'rufname': rufname,
        'detail': detail,
        'isOwn': isOwn,
      };
}

/// Ergebnis einer Abfrage — unterscheidet bewusst zwischen „kein Einsatz" und
/// „nicht ermittelbar", damit das Display den Unterschied anzeigen kann.
class EinsatzCrew {
  final String? einsatznummer;
  final List<CrewMember> members;

  /// Klartext, wenn keine Liste zustande kam (Anzeige im Display).
  final String? hint;

  const EinsatzCrew({
    this.einsatznummer,
    this.members = const [],
    this.hint,
  });

  bool get isEmpty => members.isEmpty;

  Map<String, dynamic> toMap() => {
        'einsatznummer': einsatznummer ?? '',
        'hint': hint ?? '',
        'members': members.map((m) => m.toMap()).toList(),
      };
}

/// Reine Auswertung ohne Netzwerk — der testbare Kern.
abstract final class EinsatzCrewResolver {
  /// Sucht den Rufnamen zur eigenen ISSI.
  static String? ownRufname(
      List<EdpTetraEndgeraet> geraete, String ownIssi) {
    if (ownIssi.isEmpty) return null;
    for (final g in geraete) {
      if (g.issi == ownIssi) {
        final r = g.rufname;
        if (r != null && r.isNotEmpty) return r;
      }
    }
    return null;
  }

  /// Die Einsatznummer, auf der das eigene Fahrzeug läuft.
  static String? ownEinsatznummer(
      List<EdpEinsatzmittel> mittel, String ownRufname) {
    if (ownRufname.isEmpty) return null;
    for (final m in mittel) {
      if (m.rufname == ownRufname) {
        final nr = m.einsatznummer;
        if (nr != null && nr.isNotEmpty) return nr;
      }
    }
    return null;
  }

  /// Alle Fahrzeuge auf [einsatznummer]; das eigene zuerst, der Rest nach
  /// Rufname. Fahrzeuge ohne Rufname werden verworfen — sie wären im Display
  /// eine leere Zeile.
  static List<CrewMember> crewFor(
    List<EdpEinsatzmittel> mittel,
    String einsatznummer, {
    String? ownRufname,
  }) {
    final members = <CrewMember>[];
    for (final m in mittel) {
      if (m.einsatznummer != einsatznummer) continue;
      if (m.rufname.isEmpty) continue;
      members.add(CrewMember(
        rufname: m.rufname,
        status: m.status,
        typ: m.typ,
        abschnitt: m.abschnitt,
        besatzung: m.besatzungGes,
        isOwn: ownRufname != null && m.rufname == ownRufname,
      ));
    }

    members.sort((a, b) {
      if (a.isOwn != b.isOwn) return a.isOwn ? -1 : 1;
      return a.rufname.compareTo(b.rufname);
    });
    return members;
  }
}

/// Holt die Daten und wendet [EinsatzCrewResolver] darauf an.
class EinsatzCrewService {
  static EinsatzCrewService? _instance;
  static EinsatzCrewService get instance =>
      _instance ??= EinsatzCrewService._();
  EinsatzCrewService._();

  /// ISSI→Rufname ist praktisch statisch — einmal auflösen reicht.
  String? _cachedOwnRufname;
  String? _cachedForIssi;

  /// Nur für Tests: gepufferte Zuordnung verwerfen.
  void resetCache() {
    _cachedOwnRufname = null;
    _cachedForIssi = null;
  }

  Future<String?> _resolveOwnRufname(EdpApiPro api, String issi) async {
    if (_cachedOwnRufname != null && _cachedForIssi == issi) {
      return _cachedOwnRufname;
    }
    final res = await api.getTetraEndgeraete();
    if (!res.ok) return null;
    final rufname = EinsatzCrewResolver.ownRufname(res.data ?? const [], issi);
    if (rufname != null) {
      _cachedOwnRufname = rufname;
      _cachedForIssi = issi;
    }
    return rufname;
  }

  /// Liefert die am aktuellen Einsatz beteiligten Fahrzeuge.
  ///
  /// Wirft nie — im Fehlerfall steht der Grund in [EinsatzCrew.hint], damit
  /// das Display etwas Sinnvolles anzeigen kann statt einer leeren Liste.
  Future<EinsatzCrew> load() async {
    try {
      final base = await EdpApi.ensureInitialized();
      if (base == null) {
        return const EinsatzCrew(hint: 'Nicht konfiguriert');
      }
      final issi = base.config.issi;
      if (issi.isEmpty) {
        return const EinsatzCrew(hint: 'Keine ISSI konfiguriert');
      }

      final api = EdpApiPro.instance ?? await EdpApiPro.initFromPrefs();
      if (api == null || base.config.proApiUrl.isEmpty) {
        return const EinsatzCrew(hint: 'Pro-API nicht konfiguriert');
      }

      final rufname = await _resolveOwnRufname(api, issi);
      if (rufname == null) {
        return const EinsatzCrew(hint: 'Eigenes Fahrzeug nicht gefunden');
      }

      final res = await api.getEinsatzmittel();
      if (!res.ok) {
        return const EinsatzCrew(hint: 'Leitstelle nicht erreichbar');
      }
      final mittel = res.data ?? const <EdpEinsatzmittel>[];

      final nummer = EinsatzCrewResolver.ownEinsatznummer(mittel, rufname);
      if (nummer == null) {
        return const EinsatzCrew(hint: 'Keinem Einsatz zugeordnet');
      }

      return EinsatzCrew(
        einsatznummer: nummer,
        members:
            EinsatzCrewResolver.crewFor(mittel, nummer, ownRufname: rufname),
      );
    } catch (_) {
      return const EinsatzCrew(hint: 'Abfrage fehlgeschlagen');
    }
  }
}

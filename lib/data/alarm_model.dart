// lib/data/alarm_model.dart
//
// Datenmodell für einen eingehenden EDP-Alarm.
// Das Backend stellt den Alarm unter GET /{token}/getalarm?issi={issi} bereit.
// Die TruppApp pollt diesen Endpoint und zeigt bei 200-Antwort eine
// Alarmbenachrichtigung an.

import 'dart:convert';

class AlarmData {
  final String enr;        // Einsatznummer
  final String signal;     // Sondersignal (bereinigt, ohne "0="-Präfix)
  final String stichwort;  // Stichwort
  final String klartext;   // Stichwort-Klartext
  final String meldung;    // Meldungstext
  final String objekt;     // Objektname
  final String strasse;    // Straße
  final String hnr;        // Hausnummer
  final String ort;        // Ort
  final String mittel;     // Einsatzmittel (bereinigt)
  final String ts;         // RFC3339-Zeitstempel des Eingangs
  final String issi;

  const AlarmData({
    required this.enr,
    required this.signal,
    required this.stichwort,
    required this.klartext,
    required this.meldung,
    required this.objekt,
    required this.strasse,
    required this.hnr,
    required this.ort,
    required this.mittel,
    required this.ts,
    required this.issi,
  });

  factory AlarmData.fromJson(Map<String, dynamic> json) {
    return AlarmData(
      enr:      json['enr']      as String? ?? '',
      signal:   json['signal']   as String? ?? '',
      stichwort: json['stichwort'] as String? ?? '',
      klartext:  json['klartext']  as String? ?? '',
      meldung:  json['meldung']  as String? ?? '',
      objekt:   json['objekt']   as String? ?? '',
      strasse:  json['strasse']  as String? ?? '',
      hnr:      json['hnr']      as String? ?? '',
      ort:      json['ort']      as String? ?? '',
      mittel:   json['mittel']   as String? ?? '',
      ts:       json['ts']       as String? ?? '',
      issi:     json['issi']     as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'enr':       enr,
    'signal':    signal,
    'stichwort': stichwort,
    'klartext':  klartext,
    'meldung':   meldung,
    'objekt':    objekt,
    'strasse':   strasse,
    'hnr':       hnr,
    'ort':       ort,
    'mittel':    mittel,
    'ts':        ts,
  };

  String toJsonString() => jsonEncode(toJson());

  static AlarmData? tryParseJsonString(String s) {
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return AlarmData.fromJson(m);
    } catch (_) {
      return null;
    }
  }

  /// Eindeutiger Schlüssel zur Deduplizierung (ENR + Timestamp).
  String get deduplicationKey => '${enr}_$ts';

  /// Kurztitel für Benachrichtigung-Header.
  String get shortTitle {
    if (stichwort.isNotEmpty) return stichwort;
    if (klartext.isNotEmpty) return klartext;
    return 'Alarm';
  }

  /// Vollständige Adresse als einzelner String.
  String get address {
    final streetPart = [strasse, hnr].where((s) => s.isNotEmpty).join(' ');
    return [streetPart, ort].where((s) => s.isNotEmpty).join(', ');
  }

  /// Google-Maps-URL für die Einsatzadresse.
  String get mapsUrl {
    final query = Uri.encodeComponent(address.isNotEmpty ? address : ort);
    return 'https://www.google.com/maps/search/?api=1&query=$query';
  }

  /// Einzeiliger Body-Text für die Benachrichtigung.
  String get notificationBody {
    final parts = <String>[];
    if (klartext.isNotEmpty) parts.add(klartext);
    if (address.isNotEmpty) parts.add(address);
    return parts.join(' – ');
  }
}

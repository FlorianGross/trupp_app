// lib/utils/formatters.dart
//
// Zentrale Datums-/Zeitformatierung — ersetzt die bisher in 6 Screens
// duplizierten privaten _fmt*/_formatTs-Helfer.

String _two(int v) => v.toString().padLeft(2, '0');

/// `HH:mm:ss`
String fmtTime(DateTime dt) => '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';

/// `HH:mm`
String fmtTimeShort(DateTime dt) => '${_two(dt.hour)}:${_two(dt.minute)}';

/// `dd.MM.yyyy`
String fmtDate(DateTime dt) => '${_two(dt.day)}.${_two(dt.month)}.${dt.year}';

/// `dd.MM HH:mm` (ohne Jahr, z.B. für kompakte Listen)
String fmtDateTimeShort(DateTime dt) {
  final l = dt.toLocal();
  return '${_two(l.day)}.${_two(l.month)} ${fmtTimeShort(l)}';
}

/// `dd.MM.yyyy HH:mm`
String fmtDateTime(DateTime dt) {
  final l = dt.toLocal();
  return '${fmtDate(l)} ${fmtTimeShort(l)}';
}

/// `HH:mm:ss` aus epoch-Millisekunden (lokale Zeit)
String fmtTimeFromMs(int ms) =>
    fmtTime(DateTime.fromMillisecondsSinceEpoch(ms).toLocal());

/// Alarm-Zeitstempel (ISO-String): heute → `HH:mm Uhr`,
/// sonst → `dd.MM. HH:mm`. Bei Parse-Fehler wird der Rohwert zurückgegeben.
String fmtAlarmTs(String ts) {
  try {
    final dt = DateTime.parse(ts).toLocal();
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${fmtTimeShort(dt)} Uhr';
    }
    return '${_two(dt.day)}.${_two(dt.month)}. ${fmtTimeShort(dt)}';
  } catch (_) {
    return ts;
  }
}

/// Alarm-Zeitstempel (ISO-String) ausführlich: `dd.MM.yyyy  HH:mm Uhr`.
String fmtAlarmTsLong(String ts) {
  try {
    final dt = DateTime.parse(ts).toLocal();
    return '${fmtDate(dt)}  ${fmtTimeShort(dt)} Uhr';
  } catch (_) {
    return ts;
  }
}

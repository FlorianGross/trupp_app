// lib/data/alarm_service.dart
//
// Verbindet die TruppApp mit der PocketBase-Collection "alarms" via
// Realtime-Subscription (SSE). Sobald EDP einen neuen Alarm-Datensatz
// für die eigene ISSI anlegt, kommt das Event in unter einer Sekunde an.
//
// PocketBase-Collection "alarms" – empfohlene Einrichtung:
//   Felder  : issi, enr, signal, stichwort, klartext, meldung,
//             objekt, strasse, hnr, ort, mittel, ts (alle Text)
//   createRule : "" (leer = jeder darf erstellen)
//                ODER einen Token-Check wenn pb_token gesetzt ist
//   listRule   : "" (leer = jeder darf lesen, Filter erfolgt clientseitig)
//   deleteRule : "@request.auth.id != ''" (optional: nur Auth-User)
//
// Der EDP Logger (Go) erstellt Datensätze via
//   POST {pb_url}/api/collections/alarms/records
// Die App subscribt auf neue Einträge mit Filter issi = "{eigene ISSI}".

import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_model.dart';
import '../alarm_notification.dart';

typedef AlarmReceivedCallback = void Function(AlarmData alarm);

class AlarmService {
  static PocketBase? _pb;
  static UnsubscribeFunc? _unsubscribe;

  /// Schlüssel in SharedPreferences für die PocketBase-URL.
  static const kPbUrlKey = 'pb_url';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Startet die Realtime-Subscription für eingehende Alarme.
  ///
  /// [pbUrl]  – PocketBase-Instanz-URL, z.B. "https://pb.example.org"
  /// [issi]   – eigene Geräte-ISSI; filtert Alarme auf dieses Gerät
  /// [onNew]  – optionaler Callback zusätzlich zur lokalen Notification
  static Future<void> start({
    required String pbUrl,
    required String issi,
    AlarmReceivedCallback? onNew,
  }) async {
    await stop(); // ggf. bestehende Subscription beenden

    _pb = PocketBase(pbUrl);

    _unsubscribe = await _pb!.collection('alarms').subscribe(
      '*',
      (event) async {
        if (event.action != 'create') return;
        final record = event.record;
        if (record == null) return;

        final alarm = AlarmData.fromJson(record.data);
        if (alarm.issi != issi) return; // Sicherheitsprüfung, falls Filter serverseitig nicht greift

        final shown = await AlarmNotificationService.show(alarm);
        if (shown) {
          onNew?.call(alarm);
        }
      },
      // Serverseitiger Filter: nur Datensätze für die eigene ISSI
      filter: 'issi = "$issi"',
    );
  }

  /// Beendet die aktive Realtime-Subscription.
  static Future<void> stop() async {
    await _unsubscribe?.call();
    _unsubscribe = null;
    _pb = null;
  }

  // ---------------------------------------------------------------------------
  // Config-Helpers
  // ---------------------------------------------------------------------------

  /// Liest die PocketBase-URL aus SharedPreferences.
  /// Gibt null zurück wenn nicht konfiguriert.
  static Future<String?> loadPbUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(kPbUrlKey) ?? '';
    return v.isNotEmpty ? v : null;
  }

  /// Speichert die PocketBase-URL in SharedPreferences.
  static Future<void> savePbUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPbUrlKey, url.trim().replaceAll(RegExp(r'/$'), ''));
  }

  /// Gibt true zurück wenn eine PocketBase-URL konfiguriert ist.
  static Future<bool> isConfigured() async {
    return (await loadPbUrl()) != null;
  }
}

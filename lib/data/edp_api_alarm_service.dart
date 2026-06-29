// lib/data/edp_api_alarm_service.dart
//
// Alarmierung über den EDP-API-Server. Da die EDP-API rein REST ist
// (keine SSE/WebSockets), fragt dieser Dienst den Endpoint regelmäßig ab:
//
//   GET /api/v1/alarmierung?issi={issi}&sinceId={lastId}
//
// Neue Datensätze werden lokal gespeichert (AlarmStore), als Benachrichtigung
// angezeigt und per Quittung bestätigt. Der höchste bereits gesehene Datensatz
// wird als Cursor (edpAlarmLastId) persistiert, sodass nach einem Neustart
// keine Alarme doppelt erscheinen.

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_model.dart';
import 'alarm_store.dart';
import 'app_logger.dart';
import 'app_prefs.dart';
import 'edp_api_pro.dart';
import '../alarm_notification.dart';

class EdpApiAlarmService {
  static Timer? _timer;
  static bool _polling = false;

  /// Standard-Polling-Intervall.
  static const Duration defaultInterval = Duration(seconds: 20);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Startet das periodische Polling für die eigene ISSI.
  ///
  /// [issi]     – eigene Geräte-ISSI.
  /// [interval] – Abfrageintervall (Default 20 s).
  /// [onNew]    – optionaler Callback je neuem Alarm (z. B. um den Haupt-Isolate
  ///              per `service.invoke('newAlarm', …)` zu informieren).
  static Future<void> start({
    required String issi,
    Duration interval = defaultInterval,
    void Function(AlarmData alarm)? onNew,
  }) async {
    await stop();
    // Sofort einmal abfragen, dann periodisch.
    await pollOnce(issi: issi, onNew: onNew);
    _timer = Timer.periodic(interval, (_) => pollOnce(issi: issi, onNew: onNew));
  }

  /// Beendet das Polling.
  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  // ---------------------------------------------------------------------------
  // Polling
  // ---------------------------------------------------------------------------

  /// Führt genau eine Abfrage aus. Auch direkt im iOS-Background-Fetch nutzbar.
  static Future<void> pollOnce({
    required String issi,
    void Function(AlarmData alarm)? onNew,
  }) async {
    if (_polling) return; // Überlappende Läufe vermeiden
    _polling = true;
    try {
      if (issi.isEmpty) return;
      final api = EdpApiPro.instance ?? await EdpApiPro.initFromPrefs();
      if (api == null) return;

      await AlarmNotificationService.initialize();

      final prefs = await SharedPreferences.getInstance();
      final lastId = prefs.getInt(AppPrefsKeys.edpAlarmLastId) ?? 0;

      final result = await api.pollAlarme(issi: issi, sinceId: lastId);
      if (!result.ok || result.data == null || result.data!.isEmpty) return;

      // Aufsteigend nach ID (Server liefert bereits so) verarbeiten.
      final alarms = result.data!..sort((a, b) => a.id.compareTo(b.id));
      var maxId = lastId;
      for (final alarm in alarms) {
        await AlarmStore.add(alarm);
        final shown = await AlarmNotificationService.show(alarm);
        if (shown) onNew?.call(alarm);

        // Empfang quittieren (best effort).
        if (alarm.id > 0) {
          unawaited(api.quittiereAlarm(alarm.id));
        }
        if (alarm.id > maxId) maxId = alarm.id;
      }

      if (maxId > lastId) {
        await prefs.setInt(AppPrefsKeys.edpAlarmLastId, maxId);
      }
    } catch (e, st) {
      AppLogger.e('EdpApiAlarmService', 'Alarm-Polling fehlgeschlagen', e, st);
    } finally {
      _polling = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Config-Helpers
  // ---------------------------------------------------------------------------

  /// True, wenn ein Pro-API-Server und eine ISSI konfiguriert sind.
  static Future<bool> isConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    final proUrl = prefs.getString(AppPrefsKeys.proApiUrl) ?? '';
    final issi = prefs.getString(AppPrefsKeys.issi) ?? '';
    return proUrl.isNotEmpty && issi.isNotEmpty;
  }
}

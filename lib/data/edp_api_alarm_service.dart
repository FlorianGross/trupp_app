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

  /// Maximale Anzahl Benachrichtigungen pro Poll. Verhindert einen
  /// Notification-Sturm, wenn nach einer Offline-Phase viele Alarme auf einmal
  /// nachgeliefert werden – ältere werden still in die Liste übernommen.
  static const int _maxNotificationsPerPoll = 3;

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
      if (!result.ok) {
        AppLogger.w('EdpApiAlarmService',
            'Poll fehlgeschlagen (HTTP ${result.statusCode})');
        return;
      }
      final data = result.data;
      if (data == null || data.isEmpty) return;

      // Aufsteigend nach ID verarbeiten (defensiv kopieren + sortieren).
      final alarms = [...data]..sort((a, b) => a.id.compareTo(b.id));

      // Bei großem Rückstau nur die neuesten als Benachrichtigung zeigen.
      final notifyFrom = alarms.length > _maxNotificationsPerPoll
          ? alarms.length - _maxNotificationsPerPoll
          : 0;
      if (notifyFrom > 0) {
        AppLogger.i('EdpApiAlarmService',
            '${alarms.length} neue Alarme – nur die letzten '
            '$_maxNotificationsPerPoll werden als Benachrichtigung gezeigt');
      }

      var maxId = lastId;
      var stored = 0;
      for (var i = 0; i < alarms.length; i++) {
        final alarm = alarms[i];
        try {
          await AlarmStore.add(alarm);
          stored++;
          if (i >= notifyFrom) {
            final shown = await AlarmNotificationService.show(alarm);
            if (shown) onNew?.call(alarm);
          } else {
            // Stiller Nachtrag in Liste/Badge ohne Benachrichtigung.
            onNew?.call(alarm);
          }
          // Empfang quittieren (best effort, blockiert den Ablauf nicht).
          if (alarm.id > 0) {
            unawaited(api.quittiereAlarm(alarm.id));
          }
        } catch (e, st) {
          AppLogger.e('EdpApiAlarmService',
              'Verarbeitung von Alarm ${alarm.id} fehlgeschlagen', e, st);
        }
        // Cursor immer fortschreiben – ein einzelner kaputter Datensatz darf
        // nicht dazu führen, dass jede Runde dieselben Alarme erneut kommen.
        if (alarm.id > maxId) maxId = alarm.id;
      }

      if (maxId > lastId) {
        await prefs.setInt(AppPrefsKeys.edpAlarmLastId, maxId);
      }
      AppLogger.i('EdpApiAlarmService',
          '$stored/${alarms.length} Alarme verarbeitet, Cursor=$maxId');
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

// lib/data/duty_end_config.dart
//
// Dienstende / automatische Abmeldung: meldet die App zu einer festgelegten
// Zeit (feste Uhrzeit oder Dauer ab jetzt) automatisch ab – d. h. beendet
// Einsatz/UHS-Standort und stoppt die Standortübertragung. Die Konfiguration
// bleibt dabei erhalten (im Gegensatz zu AutoDelete).

import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';
import 'app_prefs.dart';
import 'deployment_state.dart';

class DutyEndConfig {
  /// Geplantes Dienstende, oder `null` wenn deaktiviert.
  static Future<DateTime?> scheduledAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(AppPrefsKeys.dutyEndAtMs);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Plant das Dienstende [hours] Stunden ab jetzt.
  static Future<void> scheduleAfterHours(int hours) async {
    await _store(DateTime.now().add(Duration(hours: hours)));
  }

  /// Plant das Dienstende zur nächsten Uhrzeit [hour]:[minute]. Liegt die
  /// Uhrzeit heute bereits in der Vergangenheit, wird der morgige Tag genommen.
  static Future<void> scheduleAtTime(int hour, int minute) async {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    await _store(target);
  }

  /// Deaktiviert das automatische Dienstende.
  static Future<void> cancel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppPrefsKeys.dutyEndAtMs);
  }

  static Future<void> _store(DateTime target) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppPrefsKeys.dutyEndAtMs, target.millisecondsSinceEpoch);
  }

  /// Ist das Dienstende erreicht?
  static Future<bool> isDue() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(AppPrefsKeys.dutyEndAtMs);
    if (ms == null) return false;
    return DateTime.now().millisecondsSinceEpoch >= ms;
  }

  /// Führt die automatische Abmeldung aus, wenn das Dienstende erreicht ist.
  /// Gibt `true` zurück, wenn abgemeldet wurde.
  static Future<bool> signOffIfDue() async {
    if (!await isDue()) return false;
    await _performSignOff();
    return true;
  }

  /// Meldet ab: Einsatz/UHS beenden, Übertragung stoppen, Marker entfernen.
  static Future<void> _performSignOff() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppPrefsKeys.dutyEndAtMs);
    await DeploymentState.setMode(DeploymentMode.standby);
    await prefs.setBool(AppPrefsKeys.transmissionEnabled, false);
    AppLogger.i('DutyEnd', 'Automatische Abmeldung zum Dienstende ausgeführt');
  }
}

// lib/data/auto_delete_config.dart
//
// AutoDelete: löscht die aktive Konfiguration automatisch – entweder nach
// einer festgelegten Anzahl Stunden oder zu einer bestimmten Uhrzeit. Danach
// startet die App wieder in der Einrichtung. Sinnvoll für geteilte
// Einsatz-Geräte, die nach dem Einsatz keine Kennung mehr tragen sollen.

import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';
import 'app_prefs.dart';
import 'profile_store.dart';

class AutoDeleteConfig {
  /// Geplanter Löschzeitpunkt, oder `null` wenn AutoDelete deaktiviert ist.
  static Future<DateTime?> scheduledAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(AppPrefsKeys.autoDeleteConfigAtMs);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Plant die Löschung [hours] Stunden ab jetzt.
  static Future<void> scheduleAfterHours(int hours) async {
    final target = DateTime.now().add(Duration(hours: hours));
    await _store(target);
  }

  /// Plant die Löschung zur nächsten Uhrzeit [hour]:[minute]. Liegt die
  /// Uhrzeit heute bereits in der Vergangenheit, wird der morgige Tag genommen.
  static Future<void> scheduleAtTime(int hour, int minute) async {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    await _store(target);
  }

  /// Deaktiviert AutoDelete.
  static Future<void> cancel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppPrefsKeys.autoDeleteConfigAtMs);
  }

  static Future<void> _store(DateTime target) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        AppPrefsKeys.autoDeleteConfigAtMs, target.millisecondsSinceEpoch);
  }

  /// Ist die geplante Löschung fällig?
  static Future<bool> isDue() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(AppPrefsKeys.autoDeleteConfigAtMs);
    if (ms == null) return false;
    return DateTime.now().millisecondsSinceEpoch >= ms;
  }

  /// Prüft ob die Löschung fällig ist und führt sie in diesem Fall aus.
  /// Gibt `true` zurück, wenn die Konfiguration gelöscht wurde.
  static Future<bool> deleteIfDue() async {
    if (!await isDue()) return false;
    await _wipeConfiguration();
    return true;
  }

  /// Löscht die Konfiguration sofort und manuell (z. B. über den
  /// „Einsatz beenden"-Knopf). Wie die automatische Löschung, nur direkt
  /// ausgelöst: Konfiguration/Zugangsdaten weg, Einsatz beendet, App zurück
  /// im Einrichtungs-Zustand.
  static Future<void> wipeNow() => _wipeConfiguration();

  /// Löscht die aktive Konfiguration vollständig und setzt die App auf den
  /// Einrichtungs-Zustand zurück.
  static Future<void> _wipeConfiguration() async {
    final prefs = await SharedPreferences.getInstance();

    // AutoDelete-Marker selbst entfernen (einmalige Auslösung).
    await prefs.remove(AppPrefsKeys.autoDeleteConfigAtMs);

    // Aktives Profil (falls benannt gespeichert) aus der Profilliste löschen.
    final activeName = await ProfileStore.activeName();
    if (activeName != null && activeName.isNotEmpty) {
      try {
        await ProfileStore.delete(activeName);
      } catch (e) {
        AppLogger.w('AutoDelete', 'Profil konnte nicht gelöscht werden', e);
      }
    }

    // Flache Konfigurations-Keys entfernen → App startet in der Einrichtung.
    await prefs.remove(AppPrefsKeys.protocol);
    await prefs.remove(AppPrefsKeys.server);
    await prefs.remove(AppPrefsKeys.token);
    await prefs.remove(AppPrefsKeys.issi);
    await prefs.remove(AppPrefsKeys.trupp);
    await prefs.remove(AppPrefsKeys.leiter);
    await prefs.remove(AppPrefsKeys.proApiUrl);
    await prefs.setBool(AppPrefsKeys.hasConfig, false);

    // Übertragung und Einsatz-Zustand zurücksetzen.
    await prefs.setBool(AppPrefsKeys.transmissionEnabled, false);
    await prefs.remove(AppPrefsKeys.deploymentMode);
    await prefs.remove(AppPrefsKeys.deploymentStartMs);
    await prefs.remove(AppPrefsKeys.activeProfileExpiresMs);

    // Sicher gespeicherte Zugangsdaten/Tokens löschen.
    try {
      await SecureStore.clearTokens();
      await SecureStore.clearCredentials();
    } catch (e) {
      AppLogger.w('AutoDelete', 'Sichere Daten konnten nicht gelöscht werden', e);
    }

    AppLogger.i('AutoDelete', 'Konfiguration wurde automatisch gelöscht');
  }
}

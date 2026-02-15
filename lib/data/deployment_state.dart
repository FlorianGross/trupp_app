// lib/data/deployment_state.dart
import 'package:shared_preferences/shared_preferences.dart';

/// Unterscheidet zwischen verschiedenen Einsatzmodi der App
enum DeploymentMode {
  standby,   // Bereit, aber kein aktiver Einsatz (GPS sparsam)
  deployed,  // Aktiv im Einsatz (GPS präzise)
  returning, // Rückweg (GPS ausgewogen)
}

/// Verwaltet den aktuellen Einsatzstatus und automatische Zeitsteuerung
class DeploymentState {
  static const _keyMode = 'deployment_mode';
  static const _keyStartTime = 'deployment_start_ms';
  static const _keyLastActivity = 'last_activity_ms';

  /// Aktuellen Einsatzmodus abrufen
  static Future<DeploymentMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_keyMode) ?? 'standby';
    return DeploymentMode.values.firstWhere(
          (e) => e.name == mode,
      orElse: () => DeploymentMode.standby,
    );
  }

  /// Einsatzmodus setzen
  static Future<void> setMode(DeploymentMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, mode.name);

    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_keyLastActivity, now);

    if (mode == DeploymentMode.deployed) {
      await prefs.setInt(_keyStartTime, now);
    } else if (mode == DeploymentMode.standby) {
      await prefs.remove(_keyStartTime);
    }
  }

  /// Aktivität registrieren (z.B. bei Statuswechsel)
  static Future<void> updateActivity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastActivity, DateTime.now().millisecondsSinceEpoch);
  }

  /// Prüft ob automatischer Stop erfolgen soll (nach X Stunden ohne Aktivität)
  static Future<bool> shouldAutoStop({int inactiveMinutes = 180}) async {
    final mode = await getMode();
    if (mode != DeploymentMode.deployed) return false;

    final prefs = await SharedPreferences.getInstance();
    final lastActivity = prefs.getInt(_keyLastActivity) ?? 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastActivity;

    return elapsed > (inactiveMinutes * 60 * 1000);
  }

  /// Gibt die Einsatzdauer in Minuten zurück
  static Future<int> getDeploymentDurationMinutes() async {
    final mode = await getMode();
    if (mode != DeploymentMode.deployed) return 0;

    final prefs = await SharedPreferences.getInstance();
    final startMs = prefs.getInt(_keyStartTime) ?? 0;
    if (startMs == 0) return 0;

    final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
    return elapsed ~/ (60 * 1000);
  }

  /// Bestimmt ob GPS-Tracking aktiv sein soll.
  /// Tracking ist immer aktiv (mit adaptiver Frequenz), damit der Standort
  /// auch im Hintergrund dauerhaft übertragen wird.
  static Future<bool> shouldTrack(int currentStatus) async {
    // Immer tracken – Frequenz wird über AdaptiveLocationSettings gesteuert
    return true;
  }

  /// Prüft ob der aktuelle Status ein "aktiver Einsatz"-Status ist (hohe Frequenz)
  static bool isActiveStatus(int status) => [1, 3, 7].contains(status);
}
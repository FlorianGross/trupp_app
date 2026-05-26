// lib/data/app_prefs.dart
//
// Zentrale Stelle für alle SharedPreferences-Keys und sicherheitskritische
// Speicherung (flutter_secure_storage).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ---------------------------------------------------------------------------
// Alle SharedPreferences-Keys an einem Ort
// ---------------------------------------------------------------------------

abstract final class AppPrefsKeys {
  // EDP-Webhook-Konfiguration
  static const protocol = 'protocol';
  static const server = 'server';
  static const token = 'token';
  static const issi = 'issi';
  static const hasConfig = 'hasConfig';
  static const trupp = 'trupp';
  static const leiter = 'leiter';
  static const proApiUrl = 'pro_api_url';

  // PocketBase / Alarmierung
  static const pbUrl = 'pb_url';

  // App-Zustand
  static const onboarded = 'onboarded';
  static const darkMode = 'darkMode';
  static const unitType = 'unit_type';

  // Deployment / Einsatz
  static const deploymentMode = 'deployment_mode';
  static const deploymentStartMs = 'deployment_start_ms';
  static const standby = 'standby';
  static const autoDeactivateMinutes = 'autoDeactivateMinutes';
  static const transmissionEnabled = 'transmissionEnabled';
  static const lastStatus = 'lastStatus';

  // Hintergrundservice / Timing
  static const lastActivityMs = 'last_activity_ms';
  static const lastFlushMs = 'lastFlushMs';
  static const lastDbCleanupMs = 'lastDbCleanupMs';
  static const iosBgLastAlarmTs = 'ios_bg_last_alarm_ts';

  // Display-Verhalten
  /// Display im Einsatz dauerhaft wachhalten (Wakelock).
  /// Default true — am Halter im Fahrzeug sinnvoll, in der Tasche aber
  /// Akku-Killer, daher abschaltbar.
  static const wakelockInDeployment = 'wakelock_in_deployment';

  // Alarm
  static const alarmSeenCount = 'alarm_seen_count';
}

// ---------------------------------------------------------------------------
// Sicherer Speicher für Credentials und Tokens (Keychain / Keystore)
// ---------------------------------------------------------------------------

abstract final class SecureStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // Schlüssel – bleiben interne Implementierungsdetails
  static const _kAccessToken = 'edp_pro_access_token';
  static const _kRefreshToken = 'edp_pro_refresh_token';
  static const _kProUser = 'edp_pro_user';
  static const _kProPass = 'edp_pro_pass';

  // --- Tokens ---

  static Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _storage.write(key: _kAccessToken, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _kRefreshToken, value: refreshToken);
    }
  }

  static Future<String?> readAccessToken() =>
      _storage.read(key: _kAccessToken);

  static Future<String?> readRefreshToken() =>
      _storage.read(key: _kRefreshToken);

  static Future<void> clearTokens() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
  }

  // --- Zugangsdaten ---

  static Future<void> saveCredentials(String username, String password) async {
    await _storage.write(key: _kProUser, value: username);
    await _storage.write(key: _kProPass, value: password);
  }

  static Future<({String user, String pass})?> loadCredentials() async {
    final user = await _storage.read(key: _kProUser) ?? '';
    final pass = await _storage.read(key: _kProPass) ?? '';
    if (user.isEmpty) return null;
    return (user: user, pass: pass);
  }

  static Future<void> clearCredentials() async {
    await _storage.delete(key: _kProUser);
    await _storage.delete(key: _kProPass);
  }
}

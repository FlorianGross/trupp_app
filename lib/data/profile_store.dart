// lib/data/profile_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_prefs.dart';

/// Unterscheidet dauerhafte Konfigurationen (z. B. Fahrzeug) von temporären
/// Einsatz-Konfigurationen, die nach Ablauf automatisch gelöscht werden.
enum ProfileKind {
  permanent, // Bleibt dauerhaft gespeichert (z. B. Fahrzeug)
  temporary, // Einsatz-Profil: läuft ab und wird automatisch gelöscht
}

class AppProfile {
  final String name;
  final String protocol;
  final String server; // host:port
  final String token;
  final String issi;
  final String trupp;
  final String leiter;
  final String pbUrl;
  final ProfileKind kind;

  /// Gültigkeitsdauer in Stunden ab Aktivierung (nur für temporäre Profile).
  final int ttlHours;

  /// Standard-Profil: wird nach Ablauf eines temporären Profils automatisch
  /// wieder aktiviert. Nur für permanente Profile sinnvoll.
  final bool isDefault;

  const AppProfile({
    required this.name,
    required this.protocol,
    required this.server,
    required this.token,
    required this.issi,
    this.trupp = '',
    this.leiter = '',
    this.pbUrl = '',
    this.kind = ProfileKind.permanent,
    this.ttlHours = 8,
    this.isDefault = false,
  });

  bool get isTemporary => kind == ProfileKind.temporary;

  Map<String, dynamic> toJson() => {
        'name': name,
        AppPrefsKeys.protocol: protocol,
        AppPrefsKeys.server: server,
        AppPrefsKeys.token: token,
        AppPrefsKeys.issi: issi,
        AppPrefsKeys.trupp: trupp,
        AppPrefsKeys.leiter: leiter,
        'pbUrl': pbUrl,
        'kind': kind.name,
        'ttlHours': ttlHours,
        'isDefault': isDefault,
      };

  static AppProfile fromJson(Map<String, dynamic> j) => AppProfile(
        name: j['name'] as String? ?? '',
        protocol: j[AppPrefsKeys.protocol] as String? ?? 'https',
        server: j[AppPrefsKeys.server] as String? ?? '',
        token: j[AppPrefsKeys.token] as String? ?? '',
        issi: j[AppPrefsKeys.issi] as String? ?? '',
        trupp: j[AppPrefsKeys.trupp] as String? ?? '',
        leiter: j[AppPrefsKeys.leiter] as String? ?? '',
        pbUrl: j['pbUrl'] as String? ?? '',
        // Profile aus älteren App-Versionen haben kein kind → permanent
        kind: ProfileKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => ProfileKind.permanent,
        ),
        ttlHours: j['ttlHours'] as int? ?? 8,
        isDefault: j['isDefault'] as bool? ?? false,
      );

  bool get isValid => name.isNotEmpty && server.isNotEmpty && token.isNotEmpty && issi.isNotEmpty;

  AppProfile copyWith({
    String? name,
    String? protocol,
    String? server,
    String? token,
    String? issi,
    String? trupp,
    String? leiter,
    String? pbUrl,
    ProfileKind? kind,
    int? ttlHours,
    bool? isDefault,
  }) =>
      AppProfile(
        name: name ?? this.name,
        protocol: protocol ?? this.protocol,
        server: server ?? this.server,
        token: token ?? this.token,
        issi: issi ?? this.issi,
        trupp: trupp ?? this.trupp,
        leiter: leiter ?? this.leiter,
        pbUrl: pbUrl ?? this.pbUrl,
        kind: kind ?? this.kind,
        ttlHours: ttlHours ?? this.ttlHours,
        isDefault: isDefault ?? this.isDefault,
      );
}

/// Ergebnis einer Ablauf-Prüfung: welches Profil entfernt wurde und welches
/// Standard-Profil (falls vorhanden) stattdessen aktiviert wurde.
typedef ProfileExpiryResult = ({String expiredName, AppProfile? fallback});

class ProfileStore {
  static const _listKey = 'app_profiles_json';
  static const _activeKey = 'active_profile_name';

  static Future<List<AppProfile>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_listKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => AppProfile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String?> activeName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey);
  }

  /// Ablaufzeitpunkt des aktiven Profils, falls es temporär ist.
  static Future<DateTime?> activeExpiresAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(AppPrefsKeys.activeProfileExpiresMs);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Das als Standard markierte permanente Profil (Fallback nach Einsatz).
  static Future<AppProfile?> defaultProfile() async {
    final list = await all();
    for (final p in list) {
      if (p.isDefault && !p.isTemporary) return p;
    }
    return null;
  }

  /// Speichert ein Profil (überschreibt bei gleichem Namen).
  static Future<void> save(AppProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await all();
    // Es kann nur ein Standard-Profil geben
    if (profile.isDefault) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].isDefault && list[i].name != profile.name) {
          list[i] = list[i].copyWith(isDefault: false);
        }
      }
    }
    final idx = list.indexWhere((p) => p.name == profile.name);
    if (idx >= 0) {
      list[idx] = profile;
    } else {
      list.add(profile);
    }
    await prefs.setString(_listKey, jsonEncode(list.map((p) => p.toJson()).toList()));
  }

  static Future<void> delete(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await all();
    list.removeWhere((p) => p.name == name);
    await prefs.setString(_listKey, jsonEncode(list.map((p) => p.toJson()).toList()));
    if (await activeName() == name) {
      await prefs.remove(_activeKey);
      await prefs.remove(AppPrefsKeys.activeProfileExpiresMs);
    }
  }

  /// Aktiviert ein Profil: schreibt dessen Werte in die flachen Prefs-Keys.
  /// Temporäre Profile bekommen dabei ihre Ablaufzeit gesetzt.
  static Future<void> activate(AppProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppPrefsKeys.protocol, profile.protocol);
    await prefs.setString(AppPrefsKeys.server, profile.server);
    await prefs.setString(AppPrefsKeys.token, profile.token);
    await prefs.setString(AppPrefsKeys.issi, profile.issi);
    await prefs.setString(AppPrefsKeys.trupp, profile.trupp);
    await prefs.setString(AppPrefsKeys.leiter, profile.leiter);
    await prefs.setBool('hasConfig', true);
    // PocketBase-URL
    if (profile.pbUrl.isNotEmpty) {
      await prefs.setString(AppPrefsKeys.pbUrl, profile.pbUrl);
    } else {
      await prefs.remove(AppPrefsKeys.pbUrl);
    }
    await prefs.setString(_activeKey, profile.name);
    if (profile.isTemporary) {
      final expires = DateTime.now().add(Duration(hours: profile.ttlHours));
      await prefs.setInt(
          AppPrefsKeys.activeProfileExpiresMs, expires.millisecondsSinceEpoch);
    } else {
      await prefs.remove(AppPrefsKeys.activeProfileExpiresMs);
    }
  }

  /// Prüft ob das aktive temporäre Profil abgelaufen ist. Falls ja:
  /// löscht es aus der Profilliste und aktiviert das Standard-Profil
  /// (falls vorhanden). Ohne Standard-Profil wird die Übertragung gestoppt,
  /// damit keine Positionen mehr unter der Einsatz-Kennung gesendet werden.
  ///
  /// Gibt `null` zurück wenn nichts abgelaufen ist.
  static Future<ProfileExpiryResult?> expireTemporaryIfDue() async {
    final prefs = await SharedPreferences.getInstance();
    final expiresMs = prefs.getInt(AppPrefsKeys.activeProfileExpiresMs);
    if (expiresMs == null) return null;
    if (DateTime.now().millisecondsSinceEpoch < expiresMs) return null;

    final expiredName = prefs.getString(_activeKey) ?? '';
    await prefs.remove(AppPrefsKeys.activeProfileExpiresMs);
    await prefs.remove(_activeKey);

    // Abgelaufenes Einsatz-Profil automatisch löschen
    if (expiredName.isNotEmpty) {
      final list = await all();
      list.removeWhere((p) => p.name == expiredName && p.isTemporary);
      await prefs.setString(
          _listKey, jsonEncode(list.map((p) => p.toJson()).toList()));
    }

    final fallback = await defaultProfile();
    if (fallback != null) {
      await activate(fallback);
    } else {
      await prefs.setBool(AppPrefsKeys.transmissionEnabled, false);
    }
    return (expiredName: expiredName, fallback: fallback);
  }

  /// Liest das aktuelle Profil aus den flachen Prefs und gibt es zurück.
  static Future<AppProfile?> currentFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString(AppPrefsKeys.server) ?? '';
    final token = prefs.getString(AppPrefsKeys.token) ?? '';
    final issi = prefs.getString(AppPrefsKeys.issi) ?? '';
    if (server.isEmpty || token.isEmpty || issi.isEmpty) return null;
    final activeName = prefs.getString(_activeKey) ?? '';
    return AppProfile(
      name: activeName,
      protocol: prefs.getString(AppPrefsKeys.protocol) ?? 'https',
      server: server,
      token: token,
      issi: issi,
      trupp: prefs.getString(AppPrefsKeys.trupp) ?? '',
      leiter: prefs.getString(AppPrefsKeys.leiter) ?? '',
      pbUrl: prefs.getString(AppPrefsKeys.pbUrl) ?? '',
    );
  }
}

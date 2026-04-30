// lib/data/profile_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppProfile {
  final String name;
  final String protocol;
  final String server; // host:port
  final String token;
  final String issi;
  final String trupp;
  final String leiter;
  final String pbUrl;

  const AppProfile({
    required this.name,
    required this.protocol,
    required this.server,
    required this.token,
    required this.issi,
    this.trupp = '',
    this.leiter = '',
    this.pbUrl = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'protocol': protocol,
        'server': server,
        'token': token,
        'issi': issi,
        'trupp': trupp,
        'leiter': leiter,
        'pbUrl': pbUrl,
      };

  static AppProfile fromJson(Map<String, dynamic> j) => AppProfile(
        name: j['name'] as String? ?? '',
        protocol: j['protocol'] as String? ?? 'https',
        server: j['server'] as String? ?? '',
        token: j['token'] as String? ?? '',
        issi: j['issi'] as String? ?? '',
        trupp: j['trupp'] as String? ?? '',
        leiter: j['leiter'] as String? ?? '',
        pbUrl: j['pbUrl'] as String? ?? '',
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
      );
}

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

  /// Speichert ein Profil (überschreibt bei gleichem Namen).
  static Future<void> save(AppProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await all();
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
    }
  }

  /// Aktiviert ein Profil: schreibt dessen Werte in die flachen Prefs-Keys.
  static Future<void> activate(AppProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('protocol', profile.protocol);
    await prefs.setString('server', profile.server);
    await prefs.setString('token', profile.token);
    await prefs.setString('issi', profile.issi);
    await prefs.setString('trupp', profile.trupp);
    await prefs.setString('leiter', profile.leiter);
    await prefs.setBool('hasConfig', true);
    // PocketBase-URL
    if (profile.pbUrl.isNotEmpty) {
      await prefs.setString('pb_url', profile.pbUrl);
    } else {
      await prefs.remove('pb_url');
    }
    await prefs.setString(_activeKey, profile.name);
  }

  /// Liest das aktuelle Profil aus den flachen Prefs und gibt es zurück.
  static Future<AppProfile?> currentFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString('server') ?? '';
    final token = prefs.getString('token') ?? '';
    final issi = prefs.getString('issi') ?? '';
    if (server.isEmpty || token.isEmpty || issi.isEmpty) return null;
    final activeName = prefs.getString(_activeKey) ?? '';
    return AppProfile(
      name: activeName,
      protocol: prefs.getString('protocol') ?? 'https',
      server: server,
      token: token,
      issi: issi,
      trupp: prefs.getString('trupp') ?? '',
      leiter: prefs.getString('leiter') ?? '',
      pbUrl: prefs.getString('pb_url') ?? '',
    );
  }
}

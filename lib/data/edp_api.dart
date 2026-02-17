// lib/data/edp_api.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Bündelt die für EDP nötige Konfiguration.
@immutable
class EdpConfig {
  final String protocol; // 'http' | 'https'
  final String host; // z.B. 'example.org'
  final int port; // z.B. 443
  final String token; // Pfadsegment vor Endpoint
  final String issi; // Geräte-/Teilnehmerkennung
  final String trupp; // optional
  final String leiter; // optional

  const EdpConfig({
    required this.protocol,
    required this.host,
    required this.port,
    required this.token,
    required this.issi,
    required this.trupp,
    required this.leiter,
  });

  bool get isComplete =>
      protocol.isNotEmpty &&
      host.isNotEmpty &&
      port > 0 &&
      token.isNotEmpty &&
      issi.isNotEmpty;

  String get baseUrl => '$protocol://$host:$port';

  Map<String, String> toPrefs() => {
    'protocol': protocol,
    'server': '$host:$port', // historisch bei dir so gespeichert
    'token': token,
    'issi': issi,
    'hasConfig': 'true',
    'trupp': trupp,
    'leiter': leiter,
  };

  static Future<EdpConfig?> fromPrefs(SharedPreferences prefs) async {
    // Historisch speicherst du server als 'host:port'
    final protocol = prefs.getString('protocol') ?? '';
    final serverPort = prefs.getString('server') ?? '';
    final token = prefs.getString('token') ?? '';
    final issi = prefs.getString('issi') ?? '';
    final trupp = prefs.getString('trupp') ?? '';
    final leiter = prefs.getString('leiter') ?? '';

    if (protocol.isEmpty ||
        serverPort.isEmpty ||
        token.isEmpty ||
        issi.isEmpty) {
      return null;
    }

    var host = serverPort;
    var port = (protocol == 'https') ? 443 : 80;
    if (serverPort.contains(':')) {
      final parts = serverPort.split(':');
      host = parts[0];
      if (parts.length > 1) {
        port = int.tryParse(parts[1]) ?? port;
      }
    }
    return EdpConfig(
      protocol: protocol,
      host: host,
      port: port,
      token: token,
      issi: issi,
      trupp: trupp,
      leiter: leiter,
    );
  }
}

/// Ergebnisobjekt für EDP-Calls.
class EdpResult {
  final bool ok;
  final int statusCode;
  final String? body;
  final Object? error;

  const EdpResult.ok(this.statusCode, {this.body}) : ok = true, error = null;

  const EdpResult.err(this.statusCode, {this.body, this.error}) : ok = false;
}

/// Zentraler Client für alle EDP-Aufrufe.
class EdpApi {
  EdpConfig _config;
  final http.Client _client;
  final Duration timeout;
  final int retries;

  /// Singleton (optional): EdpApi.instance nach init*() verwenden.
  static EdpApi? _instance;

  static EdpApi get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError(
        'EdpApi wurde noch nicht initialisiert. Rufe initFromPrefs() oder initWithConfig() auf.',
      );
    }
    return inst;
  }

  static Future<EdpApi?> ensureInitialized() async {
    if (_instance != null) return _instance;
    return await initFromPrefs(); // setzt _instance falls Prefs ok
  }

  EdpApi._(
    this._config, {
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    this.retries = 3,
  }) : _client = client ?? http.Client();

  /// Initialisiert das Singleton aus SharedPreferences, falls möglich.
  static Future<EdpApi?> initFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final cfg = await EdpConfig.fromPrefs(prefs);
    if (cfg == null || !cfg.isComplete) return null;
    _instance = EdpApi._(cfg);
    return _instance;
  }

  /// Initialisiert das Singleton mit expliziter Config.
  static Future<EdpApi> initWithConfig(EdpConfig config) async {
    _instance = EdpApi._(config);
    return _instance!;
  }

  EdpConfig get config => _config;

  /// Aktualisiert die Config zur Laufzeit (z.B. nach Speichern im Setup).
  Future<void> updateConfig(EdpConfig config) async {
    _config = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('protocol', config.protocol);
    await prefs.setString('server', '${config.host}:${config.port}');
    await prefs.setString('token', config.token);
    await prefs.setString('issi', config.issi);
    await prefs.setBool('hasConfig', true);
    await prefs.setString('leiter', config.leiter);
    await prefs.setString('trupp', config.trupp);
  }

  Uri _uri(String path, Map<String, String> qp) {
    return Uri(
      scheme: _config.protocol,
      host: _config.host,
      port: _config.port,
      pathSegments: [_config.token, path],
      queryParameters: qp,
    );
  }

  String _fmt(double v) {
    // Server erwartet Komma als Dezimaltrennzeichen (wie im bestehenden Code)
    return v.toString().replaceAll('.', ',');
  }

  Future<EdpResult> _getWithRetry(Uri url) async {
    int attempt = 0;
    while (true) {
      try {
        final r = await _client.get(url).timeout(timeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          return EdpResult.ok(r.statusCode, body: r.body);
        }
        // Bei Server-Fehler (5xx) Retry, bei Client-Fehler (4xx) sofort abbrechen
        if (r.statusCode >= 500 && attempt < retries) {
          attempt++;
          await Future.delayed(Duration(seconds: 1 << attempt)); // 2s, 4s, 8s
          continue;
        }
        return EdpResult.err(r.statusCode, body: r.body);
      } on TimeoutException {
        if (attempt >= retries) {
          return const EdpResult.err(408, body: 'Timeout');
        }
        attempt++;
        await Future.delayed(Duration(seconds: 1 << attempt));
      } catch (e) {
        // Netzwerkfehler: Retry mit exponentiellem Backoff
        if (attempt >= retries) {
          return EdpResult.err(-1, error: e);
        }
        attempt++;
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }
  }

  /// Testet die Verbindung zum Server via GPS-Ping (kein Status-Seiteneffekt).
  Future<EdpResult> probe({double? lat, double? lon}) {
    if (lat != null && lon != null) {
      return sendGps(lat: lat, lon: lon);
    }
    // Fallback: GPS-Endpoint mit letzter bekannter Position (0,0 = ungültig aber Server antwortet)
    final url = _uri('gpsposition', {'issi': _config.issi, 'lat': '0', 'lon': '0'});
    return _getWithRetry(url);
  }

  /// Sendet einen Status (0..9).
  Future<EdpResult> sendStatus(int status) {
    final url = _uri('setstatus', {'issi': _config.issi, 'status': '$status'});
    return _getWithRetry(url);
  }

  /// Sendet eine GPS-Position.
  Future<EdpResult> sendGps({required double lat, required double lon}) {
    final url = _uri('gpsposition', {
      'issi': _config.issi,
      'lat': _fmt(lat),
      'lon': _fmt(lon),
    });
    return _getWithRetry(url);
  }

  /// Sendet eine kurze Textnachricht (SDS) an /incommingsds?issi=&text=
  Future<EdpResult> sendSdsText(String text) {
    final url = _uri('incommingsds', {'issi': _config.issi, 'text': text});
    return _getWithRetry(url);
  }

  /// Bequemlichkeit: ist die gespeicherte Konfiguration verwendbar?
  static Future<bool> hasValidConfigInPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final hasConfig = prefs.getBool('hasConfig') ?? false;
    final cfg = await EdpConfig.fromPrefs(prefs);
    return hasConfig && cfg != null && cfg.isComplete;
  }

  void close() => _client.close();
}

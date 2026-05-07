// lib/data/edp_api.dart
import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Bündelt die für EDP nötige Konfiguration.
@immutable
class EdpConfig {
  final String protocol; // 'http' | 'https'
  final String host;     // Webhook-Server, z.B. 'edp.example.org'
  final int port;        // Webhook-Port, z.B. 443
  final String token;    // Pfadsegment vor Webhook-Endpoint
  final String issi;     // Geräte-/Teilnehmerkennung
  final String trupp;    // optional
  final String leiter;   // optional
  /// Vollständige URL des EDP-Pro-API-Servers, z.B. 'https://api.example.org'.
  /// Wenn leer, wird der Webhook-Host als Fallback verwendet.
  final String proApiUrl;

  const EdpConfig({
    required this.protocol,
    required this.host,
    required this.port,
    required this.token,
    required this.issi,
    required this.trupp,
    required this.leiter,
    this.proApiUrl = '',
  });

  bool get isComplete =>
      protocol.isNotEmpty &&
      host.isNotEmpty &&
      port > 0 &&
      token.isNotEmpty &&
      issi.isNotEmpty;

  String get baseUrl => '$protocol://$host:$port';

  /// Basis-URI für den Pro-API-Server (ohne Pfad).
  Uri get proApiBaseUri {
    if (proApiUrl.isNotEmpty) {
      return Uri.parse(proApiUrl);
    }
    return Uri(scheme: protocol, host: host, port: port);
  }

  Map<String, String> toPrefs() => {
    'protocol': protocol,
    'server': '$host:$port',
    'token': token,
    'issi': issi,
    'hasConfig': 'true',
    'trupp': trupp,
    'leiter': leiter,
    'pro_api_url': proApiUrl,
  };

  static Future<EdpConfig?> fromPrefs(SharedPreferences prefs) async {
    final protocol = prefs.getString('protocol') ?? '';
    final serverPort = prefs.getString('server') ?? '';
    final token = prefs.getString('token') ?? '';
    final issi = prefs.getString('issi') ?? '';
    final trupp = prefs.getString('trupp') ?? '';
    final leiter = prefs.getString('leiter') ?? '';
    final proApiUrl = prefs.getString('pro_api_url') ?? '';

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
      proApiUrl: proApiUrl,
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
    await prefs.setString('pro_api_url', config.proApiUrl);
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

  /// Sendet eine SDS-Nachricht im Namen einer anderen ISSI (für Melde-Editor).
  Future<EdpResult> sendSdsForIssi(String issi, String text) {
    final url = _uri('incommingsds', {'issi': issi, 'text': text});
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

  // ---------------------------------------------------------------------------
  // Anonyme Pro-API-Endpunkte (kein JWT nötig, nutzt proApiUrl aus Config)
  // ---------------------------------------------------------------------------

  /// Baut eine URI gegen den Pro-API-Server (kein Token-Pfad, kein JWT-Header).
  Uri _proUri(String path, Map<String, String> qp) {
    final base = _config.proApiBaseUri;
    return base.replace(
      path: '/api/v1/$path',
      queryParameters: qp.isEmpty ? null : qp,
    );
  }

  /// Gibt alle TETRA-Endgeräte vom Pro-API-Server zurück (kein Login nötig).
  Future<EdpListResult<EdpTetraEndgeraet>> getTetraEndgeraete(
      {String? rufname}) async {
    try {
      final qp = <String, String>{};
      if (rufname != null && rufname.isNotEmpty) qp['rufname'] = rufname;
      final result = await _getWithRetry(_proUri('tetra-endgeraete', qp));
      if (!result.ok) {
        return EdpListResult.failure(result.statusCode, 'HTTP ${result.statusCode}');
      }
      final body = _parseJson(result.body);
      if (body == null) return EdpListResult.failure(-1, 'Ungültige JSON-Antwort');
      final raw = body['data'];
      final items = raw is List
          ? raw.map((e) => EdpTetraEndgeraet.fromJson(e as Map<String, dynamic>)).toList()
          : <EdpTetraEndgeraet>[];
      return EdpListResult.success(items);
    } catch (e) {
      return EdpListResult.failure(-1, e.toString());
    }
  }

  /// Gibt alle Einsatzmittel vom Pro-API-Server zurück (kein Login nötig).
  Future<EdpListResult<EdpEinsatzmittel>> getEinsatzmittel({
    String? status,
    String? wache,
  }) async {
    try {
      final qp = <String, String>{};
      if (status != null && status.isNotEmpty) qp['status'] = status;
      if (wache != null && wache.isNotEmpty) qp['wache'] = wache;
      final result = await _getWithRetry(_proUri('einsatzmittel', qp));
      if (!result.ok) {
        return EdpListResult.failure(result.statusCode, 'HTTP ${result.statusCode}');
      }
      final body = _parseJson(result.body);
      if (body == null) return EdpListResult.failure(-1, 'Ungültige JSON-Antwort');
      final raw = body['data'];
      final items = raw is List
          ? raw.map((e) => EdpEinsatzmittel.fromJson(e as Map<String, dynamic>)).toList()
          : <EdpEinsatzmittel>[];
      return EdpListResult.success(items);
    } catch (e) {
      return EdpListResult.failure(-1, e.toString());
    }
  }

  Map<String, dynamic>? _parseJson(String? body) {
    if (body == null) return null;
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Gemeinsame Modelle (anonym + Pro nutzbar)
// ---------------------------------------------------------------------------

class EdpTetraEndgeraet {
  final String issi;
  final String? rufname;
  final String? opta;
  final int type;

  const EdpTetraEndgeraet({
    required this.issi,
    this.rufname,
    this.opta,
    this.type = 0,
  });

  factory EdpTetraEndgeraet.fromJson(Map<String, dynamic> j) =>
      EdpTetraEndgeraet(
        issi: (j['issi'] as String?) ?? '',
        rufname: j['rufname'] as String?,
        opta: j['opta'] as String?,
        type: (j['type'] as int?) ?? 0,
      );

  String get displayLabel {
    final name = rufname?.isNotEmpty == true ? rufname! : (opta ?? '');
    return name.isNotEmpty ? '$name ($issi)' : issi;
  }
}

class EdpEinsatzmittel {
  final String rufname;
  final String? rufnameLang;
  final String? status;
  final String? typ;
  final String? einsatz;
  final String? einsatznummer;
  final int? besatzung0;
  final int? besatzung1;
  final int? besatzung2;
  final int? besatzungGes;
  final double? koordX;
  final double? koordY;
  final String? wache;
  final String? abschnitt;
  final DateTime? zeitstempel;

  const EdpEinsatzmittel({
    required this.rufname,
    this.rufnameLang,
    this.status,
    this.typ,
    this.einsatz,
    this.einsatznummer,
    this.besatzung0,
    this.besatzung1,
    this.besatzung2,
    this.besatzungGes,
    this.koordX,
    this.koordY,
    this.wache,
    this.abschnitt,
    this.zeitstempel,
  });

  factory EdpEinsatzmittel.fromJson(Map<String, dynamic> j) =>
      EdpEinsatzmittel(
        rufname: (j['rufname'] as String?) ?? '',
        rufnameLang: j['rufnameLang'] as String?,
        status: j['status'] as String?,
        typ: j['typ'] as String?,
        einsatz: j['einsatz'] as String?,
        einsatznummer: j['einsatznummer'] as String?,
        besatzung0: j['besatzung0'] as int?,
        besatzung1: j['besatzung1'] as int?,
        besatzung2: j['besatzung2'] as int?,
        besatzungGes: j['besatzungGes'] as int?,
        koordX: (j['koordX'] as num?)?.toDouble(),
        koordY: (j['koordY'] as num?)?.toDouble(),
        wache: j['wache'] as String?,
        abschnitt: j['abschnitt'] as String?,
        zeitstempel: j['zeitstempel'] != null
            ? DateTime.tryParse(j['zeitstempel'] as String)
            : null,
      );

  String get displayName =>
      rufnameLang?.isNotEmpty == true ? '${rufnameLang!} ($rufname)' : rufname;

  bool get hasCoordinates =>
      koordX != null && koordY != null && koordX != 0.0 && koordY != 0.0;
}

class EdpListResult<T> {
  final bool ok;
  final int statusCode;
  final List<T>? data;
  final String? error;

  const EdpListResult.success(this.data, {this.statusCode = 200})
      : ok = true,
        error = null;

  const EdpListResult.failure(this.statusCode, this.error)
      : ok = false,
        data = null;
}

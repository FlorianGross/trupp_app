// lib/data/edp_api_pro.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'edp_api.dart';
import 'app_prefs.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class EdpEinsatz {
  final int einsatznummer;
  final String? stichwort;
  final String? stichwortKlartext;
  final String? ort;
  final String? strasse;
  final String? hausnummer;
  final String? objektname;
  final double? koordx;
  final double? koordy;
  final String? status;
  final String? aktiv;
  final DateTime? eroeff;
  final String? meldung;
  final String? prioritaet;
  final String? meldender;
  final DateTime? meldungseingang;
  final String? bemerkung;
  final String? ortsteil;
  final String? einsatzart;

  const EdpEinsatz({
    required this.einsatznummer,
    this.stichwort,
    this.stichwortKlartext,
    this.ort,
    this.strasse,
    this.hausnummer,
    this.objektname,
    this.koordx,
    this.koordy,
    this.status,
    this.aktiv,
    this.eroeff,
    this.meldung,
    this.prioritaet,
    this.meldender,
    this.meldungseingang,
    this.bemerkung,
    this.ortsteil,
    this.einsatzart,
  });

  factory EdpEinsatz.fromJson(Map<String, dynamic> j) => EdpEinsatz(
        einsatznummer: j['einsatznummer'] as int,
        stichwort: j['stichwort'] as String?,
        stichwortKlartext: j['stichwortKlartext'] as String?,
        ort: j['ort'] as String?,
        strasse: j['strasse'] as String?,
        hausnummer: j['hausnummer'] as String?,
        objektname: j['objektname'] as String?,
        koordx: (j['koordx'] as num?)?.toDouble(),
        koordy: (j['koordy'] as num?)?.toDouble(),
        status: j['status'] as String?,
        aktiv: j['aktiv'] as String?,
        eroeff: j['eroeff'] != null
            ? DateTime.tryParse(j['eroeff'] as String)
            : null,
        meldung: j['meldung'] as String?,
        prioritaet: j['prioritaet'] as String?,
        meldender: j['meldender'] as String?,
        meldungseingang: j['meldungseingang'] != null
            ? DateTime.tryParse(j['meldungseingang'] as String)
            : null,
        bemerkung: j['bemerkung'] as String?,
        ortsteil: j['ortsteil'] as String?,
        einsatzart: j['einsatzart'] as String?,
      );

  String get adresse {
    final parts = <String>[
      if (strasse != null && strasse!.isNotEmpty) strasse!,
      if (hausnummer != null && hausnummer!.isNotEmpty) hausnummer!,
    ];
    final street = parts.join(' ');
    if (ort != null && ort!.isNotEmpty) {
      return street.isNotEmpty ? '$street, $ort' : ort!;
    }
    return street;
  }

  String get title =>
      stichwortKlartext?.isNotEmpty == true
          ? stichwortKlartext!
          : (stichwort?.isNotEmpty == true ? stichwort! : 'Einsatz $einsatznummer');

  bool get hasCoordinates =>
      koordx != null && koordy != null && koordx != 0.0 && koordy != 0.0;
}


class EdpVerlaufEintrag {
  final int id;
  final DateTime? addTimestamp;
  final String? typ;
  final String? von;
  final String? an;
  final String? eintrag;
  final String? auftrag;
  final String? abschnitt;

  const EdpVerlaufEintrag({
    required this.id,
    this.addTimestamp,
    this.typ,
    this.von,
    this.an,
    this.eintrag,
    this.auftrag,
    this.abschnitt,
  });

  factory EdpVerlaufEintrag.fromJson(Map<String, dynamic> j) =>
      EdpVerlaufEintrag(
        id: (j['id'] as int?) ?? 0,
        addTimestamp: j['addTimestamp'] != null
            ? DateTime.tryParse(j['addTimestamp'] as String)
            : null,
        typ: j['typ'] as String?,
        von: j['von'] as String?,
        an: j['an'] as String?,
        eintrag: j['eintrag'] as String?,
        auftrag: j['auftrag'] as String?,
        abschnitt: j['abschnitt'] as String?,
      );
}

class EdpEinsatzabschnitt {
  final int id;
  final int? einsatznummer;
  final String? bezeichnung;
  final String? eal;
  final String? kanal;
  final String? rufname;
  final String? zusatz;

  const EdpEinsatzabschnitt({
    required this.id,
    this.einsatznummer,
    this.bezeichnung,
    this.eal,
    this.kanal,
    this.rufname,
    this.zusatz,
  });

  factory EdpEinsatzabschnitt.fromJson(Map<String, dynamic> j) =>
      EdpEinsatzabschnitt(
        id: (j['id'] as int?) ?? 0,
        einsatznummer: j['einsatznummer'] as int?,
        bezeichnung: j['bezeichnung'] as String?,
        eal: j['eal'] as String?,
        kanal: j['kanal'] as String?,
        rufname: j['rufname'] as String?,
        zusatz: j['zusatz'] as String?,
      );
}

class EdpEmTyp {
  final String typ;
  final String? organisation;
  final int? showInRessourcen;
  final int? sortpos;

  const EdpEmTyp({
    required this.typ,
    this.organisation,
    this.showInRessourcen,
    this.sortpos,
  });

  factory EdpEmTyp.fromJson(Map<String, dynamic> j) => EdpEmTyp(
        typ: (j['typ'] as String?) ?? '',
        organisation: j['organisation'] as String?,
        showInRessourcen: j['showInRessourcen'] as int?,
        sortpos: j['sortpos'] as int?,
      );
}

class EdpProResult<T> {
  final bool ok;
  final int statusCode;
  final T? data;
  final String? error;

  const EdpProResult.success(this.data, {this.statusCode = 200})
      : ok = true,
        error = null;

  const EdpProResult.failure(this.statusCode, this.error)
      : ok = false,
        data = null;
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

class EdpApiPro {
  static EdpApiPro? _instance;
  static EdpApiPro? get instance => _instance;

  final EdpConfig _config;
  final http.Client _client;
  String? _accessToken;
  String? _refreshToken;

  // Systembenutzer für Pool-Funkgeräte und ISSI-Auswahl
  static const _kTruppAppUser = 'trupp_app';
  static const _kTruppAppPass = 'eRk6vIEGxugstl85r31HJKTm6ork7DLd';

  EdpApiPro._(this._config, {http.Client? client})
      : _client = client ?? http.Client();

  static Future<EdpApiPro> init(EdpConfig config) async {
    final inst = EdpApiPro._(config);
    // SecureStore kann beim ersten Start (Plugin noch nicht initialisiert) fehlschlagen
    try {
      inst._accessToken = await SecureStore.readAccessToken();
      inst._refreshToken = await SecureStore.readRefreshToken();
    } catch (_) {
      // Kein gespeicherter Token — Auto-Login folgt unten
    }
    _instance = inst;
    // Auto-Login mit Systembenutzer wenn kein Token vorhanden und Pro-URL konfiguriert
    if (!inst.hasToken && config.proApiUrl.isNotEmpty) {
      await inst.login(_kTruppAppUser, _kTruppAppPass);
    }
    return inst;
  }

  static Future<EdpApiPro?> initFromPrefs() async {
    try {
      final cfg = EdpApi.instance.config;
      return await init(cfg);
    } catch (_) {
      return null;
    }
  }

  bool get hasToken => _accessToken != null && _accessToken!.isNotEmpty;

  Uri _uri(String path, [Map<String, String>? qp]) {
    final base = _config.proApiBaseUri;
    return base.replace(
      path: '/api/v1/$path',
      queryParameters: (qp == null || qp.isEmpty) ? null : qp,
    );
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Future<bool> login(String username, String password) async {
    try {
      final resp = await _client
          .post(
            _uri('auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return false;
      _accessToken = data['accessToken'] as String?;
      _refreshToken = data['refreshToken'] as String?;
      if (_accessToken != null) {
        await SecureStore.saveTokens(
          accessToken: _accessToken!,
          refreshToken: _refreshToken,
        );
      }
      return _accessToken != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tryRefresh() async {
    final rt = _refreshToken;
    if (rt == null || rt.isEmpty) return false;
    try {
      final resp = await _client
          .post(
            _uri('auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': rt}),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return false;
      _accessToken = data['accessToken'] as String?;
      _refreshToken = data['refreshToken'] as String?;
      if (_accessToken != null) {
        await SecureStore.saveTokens(
          accessToken: _accessToken!,
          refreshToken: _refreshToken,
        );
      }
      return _accessToken != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureAuth() async {
    if (hasToken) return true;
    return await login(_kTruppAppUser, _kTruppAppPass);
  }

  Future<http.Response> _get(Uri uri) async {
    await _ensureAuth();
    var resp = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 401) {
      final recovered = await _tryRefresh() ||
          await login(_kTruppAppUser, _kTruppAppPass);
      if (recovered) {
        resp = await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 12));
      }
    }
    return resp;
  }

  Future<http.Response> _put(Uri uri, Map<String, dynamic> body) async {
    await _ensureAuth();
    var resp = await _client
        .put(uri, headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 401) {
      final recovered = await _tryRefresh() ||
          await login(_kTruppAppUser, _kTruppAppPass);
      if (recovered) {
        resp = await _client
            .put(uri, headers: _headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 12));
      }
    }
    return resp;
  }

  Future<EdpProResult<List<EdpEinsatz>>> getEinsaetze(
      {String? status}) async {
    try {
      final qp = <String, String>{};
      if (status != null) qp['status'] = status;
      final resp = await _get(_uri('einsaetze', qp.isEmpty ? null : qp));
      if (resp.statusCode != 200) {
        return EdpProResult.failure(
            resp.statusCode, 'HTTP ${resp.statusCode}');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = body['data'];
      final items = raw is List
          ? raw
              .map((e) => EdpEinsatz.fromJson(e as Map<String, dynamic>))
              .toList()
          : <EdpEinsatz>[];
      return EdpProResult.success(items);
    } catch (e) {
      return EdpProResult.failure(-1, e.toString());
    }
  }

  Future<EdpProResult<List<EdpEinsatzmittel>>> getEinsatzmittel({
    String? einsatznummer,
    String? status,
    String? wache,
  }) async {
    try {
      final qp = <String, String>{};
      if (einsatznummer != null && einsatznummer.isNotEmpty)
        qp['einsatznummer'] = einsatznummer;
      if (status != null && status.isNotEmpty) qp['status'] = status;
      if (wache != null && wache.isNotEmpty) qp['wache'] = wache;
      final resp =
          await _get(_uri('einsatzmittel', qp.isEmpty ? null : qp));
      if (resp.statusCode != 200) {
        return EdpProResult.failure(
            resp.statusCode, 'HTTP ${resp.statusCode}');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = body['data'];
      final items = raw is List
          ? raw
              .map((e) =>
                  EdpEinsatzmittel.fromJson(e as Map<String, dynamic>))
              .toList()
          : <EdpEinsatzmittel>[];
      return EdpProResult.success(items);
    } catch (e) {
      return EdpProResult.failure(-1, e.toString());
    }
  }

  Future<EdpProResult<List<EdpTetraEndgeraet>>> getTetraEndgeraete(
      {String? rufname}) async {
    try {
      final qp = <String, String>{};
      if (rufname != null && rufname.isNotEmpty) qp['rufname'] = rufname;
      final resp =
          await _get(_uri('tetra-endgeraete', qp.isEmpty ? null : qp));
      if (resp.statusCode != 200) {
        return EdpProResult.failure(
            resp.statusCode, 'HTTP ${resp.statusCode}');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = body['data'];
      final items = raw is List
          ? raw
              .map((e) =>
                  EdpTetraEndgeraet.fromJson(e as Map<String, dynamic>))
              .toList()
          : <EdpTetraEndgeraet>[];
      return EdpProResult.success(items);
    } catch (e) {
      return EdpProResult.failure(-1, e.toString());
    }
  }

  Future<EdpProResult<List<EdpVerlaufEintrag>>> getEinsatzverlauf(
      int einsatznummer) async {
    try {
      final resp = await _get(
          _uri('einsatzverlauf', {'einsatznummer': einsatznummer.toString()}));
      if (resp.statusCode != 200) {
        return EdpProResult.failure(
            resp.statusCode, 'HTTP ${resp.statusCode}');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = body['data'];
      final items = raw is List
          ? raw
              .map((e) =>
                  EdpVerlaufEintrag.fromJson(e as Map<String, dynamic>))
              .toList()
          : <EdpVerlaufEintrag>[];
      return EdpProResult.success(items);
    } catch (e) {
      return EdpProResult.failure(-1, e.toString());
    }
  }

  Future<EdpProResult<List<EdpEinsatzabschnitt>>> getEinsatzabschnitte(
      int einsatznummer) async {
    try {
      final resp = await _get(_uri(
          'einsatzabschnitte', {'einsatznummer': einsatznummer.toString()}));
      if (resp.statusCode != 200) {
        return EdpProResult.failure(
            resp.statusCode, 'HTTP ${resp.statusCode}');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = body['data'];
      final items = raw is List
          ? raw
              .map((e) =>
                  EdpEinsatzabschnitt.fromJson(e as Map<String, dynamic>))
              .toList()
          : <EdpEinsatzabschnitt>[];
      return EdpProResult.success(items);
    } catch (e) {
      return EdpProResult.failure(-1, e.toString());
    }
  }

  Future<EdpProResult<void>> updateBesatzung(
    String rufname, {
    required int fuehrung,
    required int unterfuehrer,
    required int mannschaft,
  }) async {
    try {
      final gesamt = fuehrung + unterfuehrer + mannschaft;
      final resp = await _put(
        _uri('einsatzmittel/${Uri.encodeComponent(rufname)}'),
        {
          'rufname': rufname,
          'besatzung0': fuehrung,
          'besatzung1': unterfuehrer,
          'besatzung2': mannschaft,
          'besatzungGes': gesamt,
        },
      );
      if (resp.statusCode == 200) return const EdpProResult.success(null);
      return EdpProResult.failure(resp.statusCode, 'HTTP ${resp.statusCode}');
    } catch (e) {
      return EdpProResult.failure(-1, e.toString());
    }
  }

  Future<EdpProResult<List<EdpEmTyp>>> getEmTypen() async {
    try {
      final resp = await _get(_uri('em-typen'));
      if (resp.statusCode != 200) {
        return EdpProResult.failure(resp.statusCode, 'HTTP ${resp.statusCode}');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = body['data'];
      final items = raw is List
          ? raw
              .map((e) => EdpEmTyp.fromJson(e as Map<String, dynamic>))
              .toList()
          : <EdpEmTyp>[];
      items.sort((a, b) => (a.sortpos ?? 99).compareTo(b.sortpos ?? 99));
      return EdpProResult.success(items);
    } catch (e) {
      return EdpProResult.failure(-1, e.toString());
    }
  }

  static Future<void> saveCredentials(
          String username, String password) =>
      SecureStore.saveCredentials(username, password);

  static Future<({String user, String pass})?> loadCredentials() =>
      SecureStore.loadCredentials();

  static Future<void> clearTokens() => SecureStore.clearTokens();
}

// lib/alarm_websocket_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:shared_preferences/shared_preferences.dart';

/// Model für Alarmierungsdaten
class AlarmData {
  final String einsatznummer;
  final String alarmzeit;
  final String stichwort;
  final String meldebild;
  final String ort;
  final String strasse;
  final String? plz;
  final List<String> einheiten;
  final String? bemerkung;
  final Koordinaten? koordinaten;

  AlarmData({
    required this.einsatznummer,
    required this.alarmzeit,
    required this.stichwort,
    required this.meldebild,
    required this.ort,
    required this.strasse,
    this.plz,
    required this.einheiten,
    this.bemerkung,
    this.koordinaten,
  });

  factory AlarmData.fromJson(Map<String, dynamic> json) {
    return AlarmData(
      einsatznummer: json['einsatznummer'] ?? '',
      alarmzeit: json['alarmzeit'] ?? '',
      stichwort: json['stichwort'] ?? '',
      meldebild: json['meldebild'] ?? '',
      ort: json['ort'] ?? '',
      strasse: json['strasse'] ?? '',
      plz: json['plz'],
      einheiten: (json['einheiten'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
          [],
      bemerkung: json['bemerkung'],
      koordinaten: json['koordinaten'] != null
          ? Koordinaten.fromJson(json['koordinaten'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'einsatznummer': einsatznummer,
      'alarmzeit': alarmzeit,
      'stichwort': stichwort,
      'meldebild': meldebild,
      'ort': ort,
      'strasse': strasse,
      'plz': plz,
      'einheiten': einheiten,
      'bemerkung': bemerkung,
      'koordinaten': koordinaten?.toJson(),
    };
  }
}

class Koordinaten {
  final double lat;
  final double lon;

  Koordinaten({required this.lat, required this.lon});

  factory Koordinaten.fromJson(Map<String, dynamic> json) {
    return Koordinaten(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'lat': lat, 'lon': lon};
  }
}

/// WebSocket Service für Alarmierungen
class AlarmWebSocketService {
  static final AlarmWebSocketService _instance =
  AlarmWebSocketService._internal();
  factory AlarmWebSocketService() => _instance;
  AlarmWebSocketService._internal();

  WebSocketChannel? _channel;
  final _alarmController = StreamController<AlarmData>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  String? _serverUrl;
  String? _deviceId;
  List<String> _einheiten = [];

  bool _isConnected = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 5);

  /// Stream für eingehende Alarmierungen
  Stream<AlarmData> get alarmStream => _alarmController.stream;

  /// Stream für Verbindungsstatus
  Stream<bool> get connectionStream => _connectionController.stream;

  /// Aktueller Verbindungsstatus
  bool get isConnected => _isConnected;

  /// Initialisiert den Service mit Server-URL und Geräte-ID
  Future<void> initialize({
    required String serverUrl,
    required String deviceId,
    required List<String> einheiten,
  }) async {
    _serverUrl = serverUrl;
    _deviceId = deviceId;
    _einheiten = einheiten;

    // Konfiguration speichern
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alarm_server_url', serverUrl);
    await prefs.setString('alarm_device_id', deviceId);
    await prefs.setStringList('alarm_einheiten', einheiten);
  }

  /// Lädt gespeicherte Konfiguration
  Future<bool> loadConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString('alarm_server_url');
    _deviceId = prefs.getString('alarm_device_id');
    _einheiten = prefs.getStringList('alarm_einheiten') ?? [];

    return _serverUrl != null && _deviceId != null;
  }

  /// Verbindet mit dem Alarmierungsserver
  Future<void> connect() async {
    if (_serverUrl == null || _deviceId == null) {
      throw Exception('Service nicht initialisiert. Rufe initialize() auf.');
    }

    if (_isConnected) {
      print('Alarm-Service: Bereits verbunden');
      return;
    }

    try {
      print('Alarm-Service: Verbinde mit $_serverUrl...');

      // WebSocket URL erstellen
      final wsUrl = _serverUrl!.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');

      _channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl/ws'),
      );

      // Registrierungsnachricht senden
      final registration = {
        'device_id': _deviceId,
        'einheiten': _einheiten,
      };

      _channel!.sink.add(jsonEncode(registration));

      // Auf Nachrichten hören
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionController.add(true);

      // Ping-Timer starten
      _startPingTimer();

      print('Alarm-Service: ✅ Verbunden');
    } catch (e) {
      print('Alarm-Service: ❌ Verbindungsfehler: $e');
      _isConnected = false;
      _connectionController.add(false);
      _scheduleReconnect();
    }
  }

  /// Verarbeitet eingehende Nachrichten
  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      // Prüfe auf Bestätigungsnachricht
      if (data['status'] == 'connected') {
        print('Alarm-Service: Verbindung bestätigt: ${data['client_id']}');
        return;
      }

      // Parse Alarmierung
      final alarm = AlarmData.fromJson(data);
      _alarmController.add(alarm);

      print('Alarm-Service: 🚨 Neue Alarmierung: ${alarm.einsatznummer}');
    } catch (e) {
      print('Alarm-Service: Fehler beim Verarbeiten: $e');
    }
  }

  /// Behandelt Verbindungsfehler
  void _onError(dynamic error) {
    print('Alarm-Service: WebSocket Fehler: $error');
    _isConnected = false;
    _connectionController.add(false);
    _scheduleReconnect();
  }

  /// Behandelt Verbindungsende
  void _onDone() {
    print('Alarm-Service: Verbindung geschlossen');
    _isConnected = false;
    _connectionController.add(false);
    _pingTimer?.cancel();

    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  /// Plant automatischen Wiederverbindungsversuch
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('Alarm-Service: Maximale Wiederverbindungsversuche erreicht');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectAttempts++;
      print('Alarm-Service: Wiederverbindung $_reconnectAttempts/$_maxReconnectAttempts...');
      connect();
    });
  }

  /// Startet Ping-Timer für Keep-Alive
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected && _channel != null) {
        try {
          _channel!.sink.add(jsonEncode({'type': 'ping'}));
        } catch (e) {
          print('Alarm-Service: Ping fehlgeschlagen: $e');
        }
      }
    });
  }

  /// Trennt die Verbindung
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();

    await _channel?.sink.close(status.goingAway);
    _channel = null;

    _isConnected = false;
    _connectionController.add(false);

    print('Alarm-Service: Verbindung getrennt');
  }

  /// Aktualisiert die zugeordneten Einheiten
  Future<void> updateEinheiten(List<String> einheiten) async {
    _einheiten = einheiten;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('alarm_einheiten', einheiten);

    // Reconnect um neue Zuordnung zu aktivieren
    if (_isConnected) {
      await disconnect();
      _shouldReconnect = true;
      await connect();
    }
  }

  /// Gibt Ressourcen frei
  void dispose() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _alarmController.close();
    _connectionController.close();
  }
}

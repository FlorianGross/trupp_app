import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'Keypad.dart';

class StatusOverview extends StatefulWidget {
  @override
  State<StatusOverview> createState() => _StatusOverviewState();
}

class _StatusOverviewState extends State<StatusOverview> {
  String trupp = '';
  String leiter = '';
  String issi = '';
  String protocol = 'https';
  String server = '';
  String port = '';
  String token = '';

  int? selectedStatus;
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _initLocation();
    await _loadConfig();

    // Status 3 setzen und GPS starten
    _onStatusPressed(3);
  }


  Future<void> _initLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showErrorDialog("Standortdienste sind deaktiviert. Bitte aktivieren.");
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showErrorDialog("Standortberechtigung wurde abgelehnt.");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showErrorDialog("Standortberechtigung dauerhaft verweigert. Bitte in den Einstellungen ändern.");
      return;
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Fehler"),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("OK")),
        ],
      ),
    );
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      protocol = prefs.getString('protocol') ?? 'https';
      server = prefs.getString('server') ?? 'localhost';
      token = prefs.getString('token') ?? '';
      trupp = prefs.getString('trupp') ?? 'Unbekannt';
      leiter = prefs.getString('leiter') ?? 'Unbekannt';
      issi = prefs.getString('issi') ?? '0000';

      if (server.contains(":")) {
        final parts = server.split(":");
        server = parts[0];
        port = parts[1];
      } else {
        port = protocol == 'https' ? '443' : '80';
      }
    });
  }

  Uri _buildUri(String path, Map<String, String> params) {
    return Uri.parse('$protocol://$server:$port/$token/$path')
        .replace(queryParameters: params);
  }

  Future<void> _sendStatus(int status) async {
    final url = _buildUri("setstatus", {
      "issi": issi,
      "status": "$status",
    });

    try {
      final response = await http.get(url);
      print("Status gesendet: ${response.statusCode}");

      if (!mounted) return;

      if (response.statusCode == 200) {
        _showSnackbar("Status $status erfolgreich gesendet ✅", success: true);
        setState(() {
          selectedStatus = status;
        });
      } else {
        _showSnackbar("Fehler beim Senden von Status $status ❌ (Code: ${response.statusCode})", success: false);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackbar("Fehler beim Senden von Status $status ❌", success: false);
      print("Fehler beim Senden des Status: $e");
    }
  }

  void _showSnackbar(String message, {required bool success}) {
    final snackBar = SnackBar(
      content: Text(message),
      backgroundColor: success ? Colors.green : Colors.red,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }


  Future<void> _sendLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();

      final latitude = position.latitude.toString().replaceAll('.', ',');
      final longitude = position.longitude.toString().replaceAll('.', ',');

      final url = _buildUri("gpsposition", {
        "issi": issi,
        "lat": latitude,
        "lon": longitude,
      });

      final response = await http.get(url);
      print("Position gesendet: ${response.statusCode}");
    } catch (e) {
      print("Fehler beim Senden der Position: $e");
    }
  }

  void _onStatusPressed(int status) {
    _sendStatus(status);

    _locationTimer?.cancel();

    if ([1, 3, 7].contains(status)) {
      _sendLocation();
      _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _sendLocation();
      });
    } else {
      _locationTimer?.cancel();
      _sendLocation();
    }
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Konfiguration zurücksetzen?"),
        content: const Text("Alle gespeicherten Daten werden gelöscht."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Abbrechen"),
          ),
          TextButton(
            onPressed: () async {
              // Send Status 6

              await _sendStatus(6);

              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              Navigator.of(context).pop(); // Dialog
              Navigator.of(context).pop(); // Drawer
              Navigator.pushReplacementNamed(context, '/');
            },
            child: const Text("Zurücksetzen", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }


  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Widget _buildSettingsDrawer(BuildContext context) {
    final fullServer = '$protocol://$server:$port';

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: ListView(
            children: [
              const Text(
                "Aktuelle Konfiguration",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Divider(height: 20),
              _configRow("Server", fullServer),
              _configRow("Token", token),
              _configRow("ISSI", issi),
              _configRow("Trupp", trupp),
              _configRow("Ansprechpartner", leiter),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text("Konfiguration zurücksetzen"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _confirmLogout(context),
              )
            ],
          ),
        ),
      ),
    );
  }


  Widget _configRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(value, overflow: TextOverflow.ellipsis),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Statusübersicht"),
        backgroundColor: Colors.red.shade800,
        centerTitle: true,
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: _buildSettingsDrawer(context),
      body: Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.group, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Trupp: $trupp', style: const TextStyle(fontSize: 18))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.person, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Ansprechpartner: $leiter', style: const TextStyle(fontSize: 18))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            selectedStatus != null ? 'Aktueller Status: $selectedStatus' : 'Kein Status gewählt',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          Expanded(child: Container()), // leerer Füller oben
          Align(
            alignment: Alignment.bottomCenter,
            child: Keypad(
              onPressed: _onStatusPressed,
              selectedStatus: selectedStatus,
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

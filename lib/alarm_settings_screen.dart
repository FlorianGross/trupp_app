// lib/screens/alarm_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'alarm_websocket_service.dart';

class AlarmSettingsScreen extends StatefulWidget {
  const AlarmSettingsScreen({super.key});

  @override
  State<AlarmSettingsScreen> createState() => _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends State<AlarmSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _deviceIdController = TextEditingController();
  final _alarmService = AlarmWebSocketService();

  List<String> _selectedEinheiten = [];
  bool _isLoading = false;
  bool _isConnected = false;

  // Beispiel-Einheiten - Ersetze mit deinen tatsächlichen Einheiten
  final List<String> _verfuegbareEinheiten = [
    'Trupp 1',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _setupConnectionListener();
  }

  void _setupConnectionListener() {
    _alarmService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
        });
      }
    });
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final hasConfig = await _alarmService.loadConfiguration();
    if (hasConfig) {
      final prefs = await SharedPreferences.getInstance();
      _serverUrlController.text = prefs.getString('alarm_server_url') ?? '';
      _deviceIdController.text = prefs.getString('alarm_device_id') ?? '';
      _selectedEinheiten = prefs.getStringList('alarm_einheiten') ?? [];
    } else {
      // Standardwerte
      _serverUrlController.text = 'http://192.168.1.100:8080';
      _deviceIdController.text = _generateDeviceId();
    }

    setState(() => _isLoading = false);
  }

  String _generateDeviceId() {
    return 'TRUPP_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _saveAndConnect() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _alarmService.initialize(
        serverUrl: _serverUrlController.text.trim(),
        deviceId: _deviceIdController.text.trim(),
        einheiten: _selectedEinheiten,
      );

      await _alarmService.connect();

      if (mounted) {
        showPlatformDialog(
          context: context,
          builder: (context) => PlatformAlertDialog(
            title: const Text('Erfolg'),
            content: const Text('✅ Erfolgreich mit Alarmserver verbunden'),
            actions: [
              PlatformDialogAction(
                onPressed: () {
                  Navigator.pop(context); // Dialog schließen
                  Navigator.pop(context); // Settings schließen
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showPlatformDialog(
          context: context,
          builder: (context) => PlatformAlertDialog(
            title: const Text('Fehler'),
            content: Text('❌ Verbindungsfehler:\n$e'),
            actions: [
              PlatformDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _alarmService.initialize(
        serverUrl: _serverUrlController.text.trim(),
        deviceId: _deviceIdController.text.trim(),
        einheiten: _selectedEinheiten,
      );

      await _alarmService.connect();

      await Future.delayed(const Duration(seconds: 2));

      if (_alarmService.isConnected) {
        await _alarmService.disconnect();
        if (mounted) {
          showPlatformDialog(
            context: context,
            builder: (context) => PlatformAlertDialog(
              title: const Text('Test erfolgreich'),
              content: const Text('✅ Verbindung zum Server funktioniert'),
              actions: [
                PlatformDialogAction(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } else {
        throw Exception('Verbindung konnte nicht hergestellt werden');
      }
    } catch (e) {
      if (mounted) {
        showPlatformDialog(
          context: context,
          builder: (context) => PlatformAlertDialog(
            title: const Text('Test fehlgeschlagen'),
            content: Text('❌ $e'),
            actions: [
              PlatformDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Alarmierungs-Einstellungen'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Verbindungsstatus
              if (_isConnected)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green[700]),
                      const SizedBox(width: 8),
                      const Text(
                        'Mit Alarmserver verbunden',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              if (_isConnected) const SizedBox(height: 16),

              // Server-Konfiguration
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cloud, color: Colors.red[700]),
                          const SizedBox(width: 8),
                          const Text(
                            'Server-Konfiguration',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _serverUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Server-URL',
                          hintText: 'http://192.168.1.100:8080',
                          prefixIcon: Icon(Icons.link),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.url,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte Server-URL eingeben';
                          }
                          if (!value.startsWith('http://') &&
                              !value.startsWith('https://')) {
                            return 'URL muss mit http:// oder https:// beginnen';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Geräte-ID
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.devices, color: Colors.red[700]),
                          const SizedBox(width: 8),
                          const Text(
                            'Geräte-Identifikation',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _deviceIdController,
                        decoration: const InputDecoration(
                          labelText: 'Geräte-ID',
                          hintText: 'TRUPP_123456',
                          prefixIcon: Icon(Icons.smartphone),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Bitte Geräte-ID eingeben';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Einheiten-Zuordnung
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.group, color: Colors.red[700]),
                          const SizedBox(width: 8),
                          const Text(
                            'Einheiten-Zuordnung',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Wähle die Einheiten aus, für die du alarmiert werden möchtest:',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ..._verfuegbareEinheiten.map((einheit) {
                        final isSelected = _selectedEinheiten.contains(einheit);
                        return CheckboxListTile(
                          title: Text(einheit),
                          value: isSelected,
                          activeColor: Colors.red[700],
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                _selectedEinheiten.add(einheit);
                              } else {
                                _selectedEinheiten.remove(einheit);
                              }
                            });
                          },
                        );
                      }).toList(),
                      if (_selectedEinheiten.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.warning, color: Colors.orange),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Keine Einheit = Alle Alarmierungen empfangen',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _testConnection,
                      icon: const Icon(Icons.wifi_find),
                      label: const Text('Verbindung testen'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveAndConnect,
                  icon: const Icon(Icons.save),
                  label: const Text('Speichern & Verbinden'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }
}

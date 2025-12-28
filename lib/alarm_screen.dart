import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import '../alarm_websocket_service.dart';
import 'alarm_settings_screen.dart';

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  final _alarmService = AlarmWebSocketService();
  AlarmData? _currentAlarm;
  bool _isConnected = false;
  bool _isInitialized = false; // NEU
  final List<AlarmData> _alarmHistory = [];

  @override
  void initState() {
    super.initState();
    _checkInitialization();
    _setupListeners();
  }

  // NEU: Prüfe ob Service initialisiert ist
  Future<void> _checkInitialization() async {
    final initialized = await _alarmService.loadConfiguration();
    setState(() {
      _isInitialized = initialized;
      _isConnected = _alarmService.isConnected;
    });
  }

  void _setupListeners() {
    // Alarmierungen empfangen
    _alarmService.alarmStream.listen((alarm) {
      setState(() {
        _currentAlarm = alarm;
        _alarmHistory.insert(0, alarm);
        if (_alarmHistory.length > 50) {
          _alarmHistory.removeLast();
        }
      });
    });

    // Verbindungsstatus
    _alarmService.connectionStream.listen((connected) {
      setState(() {
        _isConnected = connected;
      });
    });
  }

  Future<void> _openNavigation(AlarmData alarm) async {
    if (alarm.koordinaten != null) {
      final lat = alarm.koordinaten!.lat;
      final lon = alarm.koordinaten!.lon;
      final url = Uri.parse('geo:$lat,$lon');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    } else {
      // Fallback: Adresse als Ziel
      final address = '${alarm.strasse}, ${alarm.ort}';
      final url = Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    }
  }

  void _showAlarmDetails(AlarmData alarm) {
    showPlatformDialog(
      context: context,
      builder: (context) => PlatformAlertDialog(
        title: Row(
          children: [
            Icon(Icons.emergency, color: Colors.red.shade800, size: 24),
            const SizedBox(width: 8),
            const Expanded(child: Text('Einsatz-Details')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Einsatznummer', alarm.einsatznummer),
              _buildDetailRow('Alarmzeit', alarm.alarmzeit),
              _buildDetailRow('Stichwort', alarm.stichwort),
              _buildDetailRow('Meldebild', alarm.meldebild),
              _buildDetailRow('Straße', alarm.strasse),
              _buildDetailRow('Ort', alarm.ort),
              if (alarm.plz != null) _buildDetailRow('PLZ', alarm.plz!),
              if (alarm.bemerkung != null && alarm.bemerkung!.isNotEmpty)
                _buildDetailRow('Bemerkung', alarm.bemerkung!),
              if (alarm.koordinaten != null) ...[
                const Divider(),
                _buildDetailRow(
                  'Koordinaten',
                  '${alarm.koordinaten!.lat.toStringAsFixed(6)}, ${alarm.koordinaten!.lon.toStringAsFixed(6)}',
                ),
              ],
              if (alarm.einheiten.isNotEmpty) ...[
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Alarmierte Einheiten:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                ...alarm.einheiten.map((e) => Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Text('• $e', style: const TextStyle(fontSize: 13)),
                )),
              ],
            ],
          ),
        ),
        actions: [
          PlatformDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('SCHLIESSEN'),
          ),
          PlatformDialogAction(
            onPressed: () {
              Navigator.pop(context);
              _openNavigation(alarm);
            },
            child: const Text('NAVIGATION'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 15),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // NEU: Zeige Setup-Screen wenn nicht konfiguriert
    if (!_isInitialized) {
      return PlatformScaffold(
        appBar: PlatformAppBar(
          title: const Text('Alarmierungen'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emergency_outlined, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 24),
                Text(
                  'Alarmserver nicht konfiguriert',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Bitte konfiguriere die Verbindung zum Alarmierungsserver.',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AlarmSettingsScreen(),
                      ),
                    ).then((_) => _checkInitialization());
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('JETZT EINRICHTEN'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Normal Screen (wie vorher)
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Alarmierungen'),
        trailingActions: [
          PlatformIconButton(
            icon: Icon(_isConnected ? Icons.cloud_done : Icons.cloud_off),
            onPressed: () async {
              if (!_isConnected) {
                try {
                  await _alarmService.connect();
                } catch (e) {
                  if (mounted) {
                    showPlatformDialog(
                      context: context,
                      builder: (context) => PlatformAlertDialog(
                        title: const Text('Verbindungsfehler'),
                        content: Text('$e'),
                        actions: [
                          PlatformDialogAction(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  }
                }
              }
            },
          ),
          PlatformIconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AlarmSettingsScreen(),
                ),
              ).then((_) => _checkInitialization());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Verbindungsstatus-Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _isConnected ? Colors.green : Colors.red[700],
            child: Row(
              children: [
                Icon(
                  _isConnected ? Icons.check_circle : Icons.error,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  _isConnected
                      ? '✅ Verbunden mit Alarmserver'
                      : '❌ Nicht verbunden',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Aktuelle Alarmierung
          if (_currentAlarm != null)
            _buildCurrentAlarmCard()
          else
            _buildNoAlarmCard(),

          const SizedBox(height: 16),

          // Historie Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.history, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Text(
                  'Verlauf',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Alarmierungs-Historie
          Expanded(
            child: _buildAlarmHistory(),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentAlarmCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      color: Colors.red[50],
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[700],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emergency,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AKTUELLE ALARMIERUNG',
                        style: TextStyle(
                          color: Colors.red[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _currentAlarm!.einsatznummer,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow(Icons.warning, 'Stichwort', _currentAlarm!.stichwort),
            _buildInfoRow(Icons.description, 'Meldebild', _currentAlarm!.meldebild),
            _buildInfoRow(Icons.location_on, 'Einsatzort', '${_currentAlarm!.strasse}, ${_currentAlarm!.ort}'),
            _buildInfoRow(Icons.access_time, 'Alarmzeit', _currentAlarm!.alarmzeit),
            if (_currentAlarm!.bemerkung != null && _currentAlarm!.bemerkung!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentAlarm!.bemerkung!,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showAlarmDetails(_currentAlarm!),
                    icon: const Icon(Icons.info),
                    label: const Text('Details'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openNavigation(_currentAlarm!),
                    icon: const Icon(Icons.navigation),
                    label: const Text('Navigation'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoAlarmCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Colors.green[700],
            ),
            const SizedBox(height: 16),
            Text(
              'Keine aktive Alarmierung',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Bereit für Einsätze',
              style: TextStyle(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmHistory() {
    if (_alarmHistory.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Keine vergangenen Alarmierungen',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _alarmHistory.length,
      itemBuilder: (context, index) {
        final alarm = _alarmHistory[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.grey[300],
              child: Icon(Icons.history, color: Colors.grey[700]),
            ),
            title: Text(
              alarm.stichwort,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${alarm.alarmzeit} • ${alarm.ort}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAlarmDetails(alarm),
          ),
        );
      },
    );
  }
}
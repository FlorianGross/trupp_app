import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'StatusOverview.dart';


class ConfigScreen extends StatefulWidget {
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final hostController = TextEditingController();
  final portController = TextEditingController(text: '443');
  final tokenController = TextEditingController();
  final truppController = TextEditingController();
  final leiterController = TextEditingController();
  final issiController = TextEditingController();

  String _selectedProtocol = 'https';

  Future<void> _saveConfig() async {
    if (_formKey.currentState!.validate()) {
      final rawHost = hostController.text.trim();

      // HTTP(S) & Port Strippen, evtl. Slash am Ende entfernen
      final uri = Uri.tryParse(rawHost.startsWith('http') ? rawHost : '$_selectedProtocol://$rawHost');
      if (uri == null || uri.host.isEmpty) {
        _showErrorDialog('Ungültige Serveradresse');
        return;
      }

      final cleanedHost = uri.host;
      final port = int.tryParse(portController.text.trim()) ?? (_selectedProtocol == 'https' ? 443 : 80);
      final finalUrl = '$cleanedHost:$port';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server', finalUrl);
      await prefs.setString('protocol', _selectedProtocol);
      await prefs.setString('token', tokenController.text.trim());
      await prefs.setString('trupp', truppController.text.trim());
      await prefs.setString('leiter', leiterController.text.trim());
      await prefs.setString('issi', issiController.text.trim());
      await prefs.setBool('hasConfig', true);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => StatusOverview()),
      );
    }
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Fehler'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('OK'))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Konfiguration')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Protokoll
              DropdownButtonFormField<String>(
                value: _selectedProtocol,
                decoration: const InputDecoration(labelText: 'Protokoll'),
                items: const [
                  DropdownMenuItem(value: 'http', child: Text('http')),
                  DropdownMenuItem(value: 'https', child: Text('https')),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedProtocol = value!;
                    if (_selectedProtocol == 'https') {
                      portController.text = '443';
                    } else {
                      portController.text = '80';
                    }
                  });
                },
              ),
              const SizedBox(height: 12),

              // Host/URL
              TextFormField(
                controller: hostController,
                decoration: const InputDecoration(
                  labelText: 'EDP Server (ohne http, z. B. test.local)',
                ),
                validator: (v) => v!.isEmpty ? 'Pflichtfeld' : null,
              ),
              const SizedBox(height: 12),

              // Port
              TextFormField(
                controller: portController,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),

              // Token
              TextFormField(
                controller: tokenController,
                decoration: const InputDecoration(labelText: 'Token'),
                validator: (v) => v!.isEmpty ? 'Pflichtfeld' : null,
              ),
              const SizedBox(height: 12),

              // ISSI
              TextFormField(
                controller: issiController,
                decoration: const InputDecoration(labelText: 'ISSI (optional)'),
              ),
              const SizedBox(height: 12),

              // Truppname
              TextFormField(
                controller: truppController,
                decoration: const InputDecoration(labelText: 'Truppname'),
              ),
              const SizedBox(height: 12),

              // Ansprechpartner
              TextFormField(
                controller: leiterController,
                decoration: const InputDecoration(labelText: 'Ansprechpartner'),
              ),
              const SizedBox(height: 24),

              // Button
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                onPressed: _saveConfig,
                label: const Text('Speichern und fortfahren'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
                  foregroundColor: Colors.white,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

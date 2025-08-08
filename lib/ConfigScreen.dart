import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
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
        platformPageRoute(
          context: context,
          builder: (_) => StatusOverview(),
        ),
      );
    }
  }

  void _showErrorDialog(String msg) {
    showPlatformDialog(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: const Text('Fehler'),
        content: Text(msg),
        actions: [
          PlatformDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Konfiguration'),
        material: (_, __) => MaterialAppBarData(
          backgroundColor: Colors.red.shade800,
        ),
        cupertino: (_, __) => CupertinoNavigationBarData(
          backgroundColor: Colors.red.shade800,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
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
                    portController.text = (_selectedProtocol == 'https') ? '443' : '80';
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: hostController,
                decoration: const InputDecoration(
                  labelText: 'EDP Server (ohne http, z. B. test.local)',
                ),
                validator: (v) => v!.isEmpty ? 'Pflichtfeld' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: portController,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: tokenController,
                decoration: const InputDecoration(labelText: 'Token'),
                validator: (v) => v!.isEmpty ? 'Pflichtfeld' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: issiController,
                decoration: const InputDecoration(labelText: 'ISSI'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: truppController,
                decoration: const InputDecoration(labelText: 'Truppname'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: leiterController,
                decoration: const InputDecoration(labelText: 'Ansprechpartner'),
              ),
              const SizedBox(height: 24),
              PlatformElevatedButton(
                onPressed: _saveConfig,
                child: const Text('Speichern und fortfahren'),
                material: (_, __) => MaterialElevatedButtonData(
                  icon: const Icon(Icons.save),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
                  ),
                ),
                cupertino: (_, __) => CupertinoElevatedButtonData(
                  color: Colors.red.shade800,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

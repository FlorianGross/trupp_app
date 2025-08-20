// lib/screens/ConfigScreen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'StatusOverview.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

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
  bool _autoSaveAfterScan = true;

  @override
  void dispose() {
    hostController.dispose();
    portController.dispose();
    tokenController.dispose();
    truppController.dispose();
    leiterController.dispose();
    issiController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (_formKey.currentState!.validate()) {
      final rawHost = hostController.text.trim();

      final uri = Uri.tryParse(
          rawHost.startsWith('http') ? rawHost : '$_selectedProtocol://$rawHost');
      if (uri == null || uri.host.isEmpty) {
        _showErrorDialog('Ungültige Serveradresse');
        return;
      }

      final cleanedHost = uri.host;
      final port = int.tryParse(portController.text.trim()) ??
          (_selectedProtocol == 'https' ? 443 : 80);
      final finalUrl = '$cleanedHost:$port';

      // Test if Configuration is working (Send Get-Request and if != 403 save, else show Error)

      var url = Uri(
        scheme: _selectedProtocol,
        host: cleanedHost,
        port: port,
        pathSegments: [tokenController.text.trim(), "setstatus"],
        queryParameters: {'issi': issiController.text.trim(), 'status': "1"},
      );

      try {
        final r = await http.get(url);

        if (r.statusCode == 403) {
          _showErrorDialog('Ungültige Konfiguration: Zugriff verweigert (403)');
          return;
        } else if (r.statusCode != 200) {
          _showErrorDialog(
              'Fehler beim Testen der Konfiguration: ${r.statusCode} ${r
                  .reasonPhrase}');
          return;
        }
      }catch (e) {
        _showErrorDialog('Überprüfen Sie die Konfiguration / Internetverbindung');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server', finalUrl);
      await prefs.setString('protocol', _selectedProtocol);
      await prefs.setString('token', tokenController.text.trim());
      await prefs.setString('trupp', truppController.text.trim());
      await prefs.setString('leiter', leiterController.text.trim());
      await prefs.setString('issi', issiController.text.trim());
      await prefs.setBool('hasConfig', true);



      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        platformPageRoute(
          context: context,
          builder: (_) => const StatusOverview(),
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

  void _showInfoSnack(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _buildProtocolSelector() {
    if (isMaterial(context)) {
      return DropdownButtonFormField<String>(
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
      );
    } else {
      return PlatformElevatedButton(
        child: Text('Protokoll: $_selectedProtocol (ändern)'),
        onPressed: () => _showProtocolCupertinoPicker(context),
      );
    }
  }

  void _showProtocolCupertinoPicker(BuildContext context) {
    showPlatformModalSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: SizedBox(
            height: 200,
            child: CupertinoPicker(
              itemExtent: 40,
              scrollController: FixedExtentScrollController(
                initialItem: _selectedProtocol == 'https' ? 1 : 0,
              ),
              onSelectedItemChanged: (index) {
                setState(() {
                  _selectedProtocol = index == 0 ? 'http' : 'https';
                  portController.text =
                  _selectedProtocol == 'https' ? '443' : '80';
                });
              },
              children: const [
                Text('http'),
                Text('https'),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- QR / Deep-Link: truppapp://config?... ----------
  // Erwartete Query-Parameter:
  // protocol, server, port, token, issi, trupp, leiter
  Future<void> _applyConfigFromUri(Uri uri) async {
    if (uri.scheme != 'truppapp' || uri.host != 'config') {
      throw Exception('Unbekannter Link (erwartet: truppapp://config)');
    }

    final q = uri.queryParameters;
    final protocol = q['protocol']?.trim();
    final server = q['server']?.trim();
    final portStr = q['port']?.trim();
    final token = q['token']?.trim() ?? '';
    final issi = q['issi']?.trim() ?? '';
    final trupp = q['trupp']?.trim() ?? '';
    final leiter = q['leiter']?.trim() ?? '';

    if (protocol == null || server == null) {
      throw Exception('Fehlende Parameter: protocol/server');
    }

    final port = int.tryParse(portStr ?? '') ?? (protocol == 'https' ? 443 : 80);

    setState(() {
      _selectedProtocol = (protocol == 'http') ? 'http' : 'https';
      hostController.text = server;
      portController.text = '$port';
      tokenController.text = token;
      truppController.text = trupp;
      leiterController.text = leiter;
      issiController.text = issi;
    });

    _showInfoSnack('Konfiguration übernommen');
    if (_autoSaveAfterScan) {
      await _saveConfig();
    }
  }

  void _openScannerSheet() {
    showPlatformModalSheet(
      context: context,
      builder: (_) {
        bool handled = false;
        return SafeArea(
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                const SizedBox(height: 8),
                const Text('QR-Code scannen',
                    style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: MobileScanner(
                        onDetect: (capture) async {
                          if (handled) return;
                          final code = capture.barcodes.firstOrNull?.rawValue;
                          if (code == null) return;
                          try {
                            final uri = Uri.parse(code);
                            handled = true;
                            if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop(); // Sheet schließen
                            }
                            await _applyConfigFromUri(uri);
                          } catch (e) {
                            _showErrorDialog('Fehler beim Lesen des QR-Codes: $e');
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Nach Scan automatisch speichern'),
                    PlatformSwitch(
                      value: _autoSaveAfterScan,
                      onChanged: (v) => setState(() => _autoSaveAfterScan = v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Konfiguration'),
        material: (_, __) => MaterialAppBarData(
          backgroundColor: Colors.red.shade800,
          actions: [
            // QR-Import auch über AppBar erreichbar
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Per QR übernehmen',
              onPressed: _openScannerSheet,
            ),
          ],
        ),
        cupertino: (_, __) => CupertinoNavigationBarData(
          backgroundColor: Colors.red.shade800,
          trailing: GestureDetector(
            onTap: _openScannerSheet,
            child: const Icon(CupertinoIcons.qrcode_viewfinder),
          ),
        ),
      ),
      body: Material( // nötig für InputThemes
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                // QR-Import Card
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.qr_code, color: Colors.red.shade800),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Konfiguration per QR-Code übernehmen',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        PlatformElevatedButton(
                          onPressed: _openScannerSheet,
                          child: const Text('Per QR übernehmen'),
                          material: (_, __) => MaterialElevatedButtonData(
                            icon: const Icon(Icons.qr_code_scanner),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade800,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          cupertino: (_, __) => CupertinoElevatedButtonData(
                            color: Colors.red.shade800,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                _buildProtocolSelector(),
                const SizedBox(height: 12),
                PlatformTextFormField(
                  controller: hostController,
                  validator: (v) => v == null || v.isEmpty ? 'Pflichtfeld' : null,
                  material: (_, __) => MaterialTextFormFieldData(
                    decoration:
                    const InputDecoration(labelText: 'EDP Server (z. B. test.local)'),
                  ),
                  cupertino: (_, __) => CupertinoTextFormFieldData(
                    placeholder: 'EDP Server (z. B. test.local)',
                  ),
                ),
                const SizedBox(height: 12),
                PlatformTextFormField(
                  controller: portController,
                  keyboardType: TextInputType.number,
                  material: (_, __) => MaterialTextFormFieldData(
                    decoration: const InputDecoration(labelText: 'Port'),
                  ),
                  cupertino: (_, __) => CupertinoTextFormFieldData(
                    placeholder: 'Port',
                  ),
                ),
                const SizedBox(height: 12),
                PlatformTextFormField(
                  controller: tokenController,
                  validator: (v) => v == null || v.isEmpty ? 'Pflichtfeld' : null,
                  material: (_, __) => MaterialTextFormFieldData(
                    decoration: const InputDecoration(labelText: 'Token'),
                  ),
                  cupertino: (_, __) => CupertinoTextFormFieldData(
                    placeholder: 'Token',
                  ),
                ),
                const SizedBox(height: 12),
                PlatformTextFormField(
                  controller: issiController,
                  material: (_, __) => MaterialTextFormFieldData(
                    decoration: const InputDecoration(labelText: 'ISSI'),
                  ),
                  cupertino: (_, __) => CupertinoTextFormFieldData(
                    placeholder: 'ISSI',
                  ),
                ),
                const SizedBox(height: 12),
                PlatformTextFormField(
                  controller: truppController,
                  material: (_, __) => MaterialTextFormFieldData(
                    decoration: const InputDecoration(labelText: 'Truppname'),
                  ),
                  cupertino: (_, __) => CupertinoTextFormFieldData(
                    placeholder: 'Truppname',
                  ),
                ),
                const SizedBox(height: 12),
                PlatformTextFormField(
                  controller: leiterController,
                  material: (_, __) => MaterialTextFormFieldData(
                    decoration: const InputDecoration(labelText: 'Ansprechpartner'),
                  ),
                  cupertino: (_, __) => CupertinoTextFormFieldData(
                    placeholder: 'Ansprechpartner',
                  ),
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
      ),
    );
  }
}

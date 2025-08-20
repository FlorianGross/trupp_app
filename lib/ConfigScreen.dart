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
  bool _autoSaveAfterScan = false;

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

  @override
  void initState() {
    super.initState();

    if (widget is ConfigScreenWithPrefill) {
      final uri = (widget as ConfigScreenWithPrefill).initialDeepLink;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _applyConfigFromUri(uri); // deine Methode
        } catch (e) {
          _showErrorDialog('DeepLink ungültig: $e');
        }
      });
    }
  }

  bool _showAllErrors =
      false; // nach erstem fehlgeschlagenen Speichern alle Fehler zeigen

  bool _isMissing(TextEditingController c) => c.text.trim().isEmpty;

  InputDecoration _materialDecoration(String label, {required bool missing}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      // zarte Rot-Tönung wenn fehlt, sonst neutral
      fillColor: missing ? Colors.red.shade50 : Colors.grey.shade50,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: missing ? Colors.red.shade200 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: missing ? Colors.red : Colors.red.shade800,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  // Für Cupertino: den Hintergrund einfärben – CupertinoTextField hat kein errorBorder.
  // Wir wrappen unten den Field-Builder in einen Container mit Farbe.
  BoxDecoration _cupertinoBox({required bool missing}) {
    return BoxDecoration(
      color: missing ? const Color(0xffffebee) : const Color(0xfff5f5f5),
      // #ffebee ≈ red-50
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: missing ? Colors.red : const Color(0xffe0e0e0)),
    );
  }

  Widget _requiredField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    final missing = _isMissing(controller);

    // Autovalidate: nur auf User-Interaktion – oder immer wenn _showAllErrors true
    final autoMode =
        _showAllErrors
            ? AutovalidateMode.always
            : AutovalidateMode.onUserInteraction;

    validator(String? v) =>
        (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null;

    if (isMaterial(context)) {
      return PlatformTextFormField(
        controller: controller,
        autovalidateMode: autoMode,
        validator: validator,
        keyboardType: keyboardType,
        material:
            (_, __) => MaterialTextFormFieldData(
              decoration: _materialDecoration(label, missing: missing),
            ),
      );
    } else {
      // Cupertino: Container färbt, Feld bleibt clean
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF616161)),
            ),
          ),
          Container(
            decoration: _cupertinoBox(missing: missing),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: PlatformTextFormField(
              controller: controller,
              autovalidateMode: autoMode,
              validator: validator,
              keyboardType: keyboardType,
              cupertino:
                  (_, __) => CupertinoTextFormFieldData(
                    decoration:
                        null, // keine eigene Box, wir nutzen den Container
                  ),
              material:
                  (_, __) => MaterialTextFormFieldData(
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
            ),
          ),
          if (_showAllErrors && missing)
            const Padding(
              padding: EdgeInsets.only(left: 4, top: 4),
              child: Text(
                'Pflichtfeld',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      );
    }
  }

  Widget _optionalField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    final missing = _isMissing(
      controller,
    ); // nur zur Hintergrundfarbe, nicht als Fehler
    if (isMaterial(context)) {
      return PlatformTextFormField(
        controller: controller,
        keyboardType: keyboardType,
        material:
            (_, __) => MaterialTextFormFieldData(
              decoration: _materialDecoration(label, missing: false),
            ),
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF616161)),
            ),
          ),
          Container(
            decoration: _cupertinoBox(missing: false),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: PlatformTextFormField(
              controller: controller,
              keyboardType: keyboardType,
              cupertino:
                  (_, __) => CupertinoTextFormFieldData(decoration: null),
              material:
                  (_, __) => MaterialTextFormFieldData(
                    decoration: InputDecoration(border: InputBorder.none),
                  ),
            ),
          ),
        ],
      );
    }
  }

  Future<void> _saveConfig() async {
    if (_formKey.currentState!.validate()) {
      final rawHost = hostController.text.trim();

      final uri = Uri.tryParse(
        rawHost.startsWith('http') ? rawHost : '$_selectedProtocol://$rawHost',
      );
      if (uri == null || uri.host.isEmpty) {
        _showErrorDialog('Ungültige Serveradresse');
        return;
      }

      final cleanedHost = uri.host;
      final port =
          int.tryParse(portController.text.trim()) ??
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
            'Fehler beim Testen der Konfiguration: ${r.statusCode} ${r.reasonPhrase}',
          );
          return;
        }
      } catch (e) {
        _showErrorDialog(
          'Überprüfen Sie die Konfiguration / Internetverbindung',
        );
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
      builder:
          (_) => PlatformAlertDialog(
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
              children: const [Text('http'), Text('https')],
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

    final port =
        int.tryParse(portStr ?? '') ?? (protocol == 'https' ? 443 : 80);

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
                const Text(
                  'QR-Code scannen',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
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
                            _showErrorDialog(
                              'Fehler beim Lesen des QR-Codes: $e',
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
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
        material:
            (_, __) => MaterialAppBarData(
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
        cupertino:
            (_, __) => CupertinoNavigationBarData(
              backgroundColor: Colors.red.shade800,
              trailing: GestureDetector(
                onTap: _openScannerSheet,
                child: const Icon(CupertinoIcons.qrcode_viewfinder),
              ),
            ),
      ),
      body: Material(
        // nötig für InputThemes
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
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        PlatformElevatedButton(
                          onPressed: _openScannerSheet,
                          child: const Text('Per QR übernehmen'),
                          material:
                              (_, __) => MaterialElevatedButtonData(
                                icon: const Icon(Icons.qr_code_scanner),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade800,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                          cupertino:
                              (_, __) => CupertinoElevatedButtonData(
                                color: Colors.red.shade800,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                _buildProtocolSelector(),
                const SizedBox(height: 12),
                _requiredField(
                  label: 'EDP Server* (z. B. test.local)',
                  controller: hostController,
                ),

                const SizedBox(height: 12),

                _requiredField(
                  label: 'Port*',
                  controller: portController,
                  keyboardType: TextInputType.number,
                ),

                const SizedBox(height: 12),

                _requiredField(label: 'Token*', controller: tokenController),

                const SizedBox(height: 12),

                _requiredField(label: 'ISSI*', controller: issiController),

                const SizedBox(height: 12),

                _optionalField(label: 'Truppname', controller: truppController),

                const SizedBox(height: 12),

                _optionalField(
                  label: 'Ansprechpartner',
                  controller: leiterController,
                ),
                Text(
                  'Die Konfiguration wird im Gerät gespeichert. \n * Pflichtfelder',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 24),
                PlatformElevatedButton(
                  onPressed: _saveConfig,
                  child: const Text('Speichern und fortfahren'),
                  material:
                      (_, __) => MaterialElevatedButtonData(
                        icon: const Icon(Icons.save),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade800,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  cupertino:
                      (_, __) => CupertinoElevatedButtonData(
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

class ConfigScreenWithPrefill extends ConfigScreen {
  final Uri initialDeepLink;

  const ConfigScreenWithPrefill({super.key, required this.initialDeepLink});
}

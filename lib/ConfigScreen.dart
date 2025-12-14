// lib/screens/ConfigScreen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'StatusOverview.dart';
import 'data/edp_api.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final hostController = TextEditingController();
  final portController = TextEditingController(text: '443');
  final tokenController = TextEditingController();
  final truppController = TextEditingController();
  final leiterController = TextEditingController();
  final issiController = TextEditingController();

  String _selectedProtocol = 'https';
  bool _autoSaveAfterScan = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void dispose() {
    hostController.dispose();
    portController.dispose();
    tokenController.dispose();
    truppController.dispose();
    leiterController.dispose();
    issiController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();

    if (widget is ConfigScreenWithPrefill) {
      final uri = (widget as ConfigScreenWithPrefill).initialDeepLink;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _applyConfigFromUri(uri);
        } catch (e) {
          _showErrorDialog('DeepLink ungültig: $e');
        }
      });
    }
  }

  bool _showAllErrors = false;
  bool _isMissing(TextEditingController c) => c.text.trim().isEmpty;

  InputDecoration _materialDecoration(String label, {required bool missing}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: missing ? Colors.red.shade50 : Colors.grey.shade50,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: missing ? Colors.red.shade200 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: missing ? Colors.red : Colors.red.shade800,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  BoxDecoration _cupertinoBox({required bool missing}) {
    return BoxDecoration(
      color: missing ? const Color(0xffffebee) : const Color(0xfff5f5f5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: missing ? Colors.red : const Color(0xffe0e0e0)),
    );
  }

  Widget _requiredField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    final missing = _isMissing(controller);
    final autoMode = _showAllErrors
        ? AutovalidateMode.always
        : AutovalidateMode.onUserInteraction;

    String? validator(String? v) =>
        (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null;

    if (isMaterial(context)) {
      return PlatformTextFormField(
        controller: controller,
        autovalidateMode: autoMode,
        validator: validator,
        keyboardType: keyboardType,
        onChanged: (_) => setState(() {}),
        material: (_, __) => MaterialTextFormFieldData(
          decoration: _materialDecoration(label, missing: missing),
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
              style: const TextStyle(fontSize: 13, color: Color(0xFF616161), fontWeight: FontWeight.w500),
            ),
          ),
          Container(
            decoration: _cupertinoBox(missing: missing),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: PlatformTextFormField(
              controller: controller,
              autovalidateMode: autoMode,
              validator: validator,
              keyboardType: keyboardType,
              onChanged: (_) => setState(() {}),
              cupertino: (_, __) => CupertinoTextFormFieldData(decoration: null),
              material: (_, __) => MaterialTextFormFieldData(
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
    if (isMaterial(context)) {
      return PlatformTextFormField(
        controller: controller,
        keyboardType: keyboardType,
        material: (_, __) => MaterialTextFormFieldData(
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
              style: const TextStyle(fontSize: 13, color: Color(0xFF616161), fontWeight: FontWeight.w500),
            ),
          ),
          Container(
            decoration: _cupertinoBox(missing: false),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: PlatformTextFormField(
              controller: controller,
              keyboardType: keyboardType,
              cupertino: (_, __) => CupertinoTextFormFieldData(decoration: null),
              material: (_, __) => MaterialTextFormFieldData(
                decoration: const InputDecoration(border: InputBorder.none),
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
      final port = int.tryParse(portController.text.trim()) ??
          (_selectedProtocol == 'https' ? 443 : 80);

      final config = EdpConfig(
        protocol: _selectedProtocol,
        host: cleanedHost,
        port: port,
        token: tokenController.text.trim(),
        issi: issiController.text.trim(),
        trupp: truppController.text.trim(),
        leiter: leiterController.text.trim(),
      );

      try {
        final api = await EdpApi.initWithConfig(config);
        final probe = await api.probe();
        if (!probe.ok) {
          _showErrorDialog(
            'Verbindung fehlgeschlagen (HTTP ${probe.statusCode}). Bitte Server und Token prüfen.',
          );
          return;
        }

        await api.updateConfig(config);
        _showInfoSnack('Konfiguration gespeichert');

        if (mounted) {
          Navigator.of(context).pushReplacement(
            platformPageRoute(
              context: context,
              builder: (_) => const StatusOverview(),
            ),
          );
        }
      } catch (e) {
        _showErrorDialog('Fehler beim Speichern: $e');
      }
    } else {
      setState(() => _showAllErrors = true);
      _showInfoSnack('Bitte alle Pflichtfelder ausfüllen');
    }
  }

  Widget _buildProtocolSelector() {
    if (isMaterial(context)) {
      return Card(
        elevation: 0,
        color: Colors.grey.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Text('Protokoll:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              SegmentedButton<String>(
                selected: {_selectedProtocol},
                onSelectionChanged: (Set<String> s) {
                  setState(() {
                    _selectedProtocol = s.first;
                    portController.text = _selectedProtocol == 'https' ? '443' : '80';
                  });
                },
                segments: const [
                  ButtonSegment(value: 'http', label: Text('HTTP')),
                  ButtonSegment(value: 'https', label: Text('HTTPS')),
                ],
                style: ButtonStyle(
                  backgroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(MaterialState.selected)) {
                      return Colors.red.shade800;
                    }
                    return Colors.white;
                  }),
                  foregroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(MaterialState.selected)) {
                      return Colors.white;
                    }
                    return Colors.red.shade800;
                  }),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              'Protokoll',
              style: TextStyle(fontSize: 13, color: Color(0xFF616161), fontWeight: FontWeight.w500),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xfff5f5f5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xffe0e0e0)),
            ),
            padding: const EdgeInsets.all(4),
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: _selectedProtocol,
              backgroundColor: Colors.transparent,
              thumbColor: Colors.red.shade800,
              children: const {
                'http': Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('HTTP', style: TextStyle(fontSize: 14)),
                ),
                'https': Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('HTTPS', style: TextStyle(fontSize: 14)),
                ),
              },
              onValueChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    _selectedProtocol = value;
                    portController.text = _selectedProtocol == 'https' ? '443' : '80';
                  });
                }
              },
            ),
          ),
        ],
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
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showInfoSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 16,
          left: 16,
          right: 16,
        ),
      ),
    );
  }

  Future<void> _applyConfigFromUri(Uri uri) async {
    final protocol = uri.queryParameters['protocol'] ?? 'https';
    final server = uri.queryParameters['server'] ?? '';
    final portStr = uri.queryParameters['port'];
    final token = uri.queryParameters['token'] ?? '';
    final trupp = uri.queryParameters['trupp'] ?? '';
    final leiter = uri.queryParameters['leiter'] ?? '';
    final issi = uri.queryParameters['issi'] ?? '';

    if (server.isEmpty || token.isEmpty || issi.isEmpty) {
      _showErrorDialog('QR-Code unvollständig (Server, Token oder ISSI fehlen).');
      return;
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
          child: Container(
            height: 450,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'QR-Code scannen',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: MobileScanner(
                        onDetect: (capture) async {
                          if (handled) return;
                          final code = capture.barcodes.firstOrNull?.rawValue;
                          if (code == null) return;
                          try {
                            final uri = Uri.parse(code);
                            handled = true;
                            if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop();
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
                const SizedBox(height: 20),
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
      backgroundColor: Colors.grey[100],
      appBar: PlatformAppBar(
        title: const Text('Konfiguration'),
        material: (_, __) => MaterialAppBarData(
          backgroundColor: Colors.red.shade800,
          elevation: 0,
          centerTitle: true,
          actions: [
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
            child: const Icon(CupertinoIcons.qrcode_viewfinder, color: Colors.white),
          ),
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.grey[100],
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  Card(
                    elevation: 2,
                    shadowColor: Colors.black26,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.qr_code, color: Colors.red.shade800, size: 28),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Konfiguration per QR-Code',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          PlatformElevatedButton(
                            onPressed: _openScannerSheet,
                            child: const Text('QR-Code scannen'),
                            material: (_, __) => MaterialElevatedButtonData(
                              icon: const Icon(Icons.qr_code_scanner),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade800,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            cupertino: (_, __) => CupertinoElevatedButtonData(
                              color: Colors.red.shade800,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Manuelle Konfiguration',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  _buildProtocolSelector(),
                  const SizedBox(height: 16),
                  _requiredField(
                    label: 'EDP Server* (z. B. test.local)',
                    controller: hostController,
                  ),
                  const SizedBox(height: 16),
                  _requiredField(
                    label: 'Port*',
                    controller: portController,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  _requiredField(label: 'Token*', controller: tokenController),
                  const SizedBox(height: 16),
                  _requiredField(label: 'ISSI*', controller: issiController),
                  const SizedBox(height: 16),
                  _optionalField(label: 'Truppname', controller: truppController),
                  const SizedBox(height: 16),
                  _optionalField(
                    label: 'Ansprechpartner',
                    controller: leiterController,
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'Die Konfiguration wird sicher im Gerät gespeichert.\n* Pflichtfelder',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  PlatformElevatedButton(
                    onPressed: _saveConfig,
                    child: const Text('Speichern und fortfahren'),
                    material: (_, __) => MaterialElevatedButtonData(
                      icon: const Icon(Icons.save),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade800,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    cupertino: (_, __) => CupertinoElevatedButtonData(
                      color: Colors.red.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
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
// lib/screens/ConfigScreen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'status_overview_screen.dart';
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
      if (uri == null) {
        _showErrorDialog('Host konnte nicht geparst werden.');
        return;
      }

      var h = uri.host.isNotEmpty ? uri.host : rawHost;
      var p = portController.text.trim();
      if (h.contains(':')) {
        final s = h.split(':');
        h = s[0];
        if (s.length > 1) p = s[1];
      }

      final cfg = EdpConfig(
        protocol: _selectedProtocol,
        host: h,
        port: int.tryParse(p) ?? 443,
        token: tokenController.text.trim(),
        issi: issiController.text.trim(),
        trupp: truppController.text.trim(),
        leiter: leiterController.text.trim(),
      );

      if (!cfg.isComplete) {
        setState(() => _showAllErrors = true);
        _showErrorDialog('Bitte alle Pflichtfelder ausfüllen.');
        return;
      }

      try {
        final api = await EdpApi.initWithConfig(cfg);
        final result = await api.probe();
        if (!result.ok) {
          _showErrorDialog(
            'Server nicht erreichbar (HTTP ${result.statusCode}).\n'
                'Trotzdem speichern?',
            onRetry: () async {
              await api.updateConfig(cfg);
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  platformPageRoute(
                    context: context,
                    builder: (_) => const StatusOverview(),
                  ),
                      (_) => false,
                );
              }
            },
          );
          return;
        }

        await api.updateConfig(cfg);
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            platformPageRoute(
              context: context,
              builder: (_) => const StatusOverview(),
            ),
                (_) => false,
          );
        }
      } catch (e) {
        _showErrorDialog('Fehler beim Speichern: $e');
      }
    } else {
      setState(() => _showAllErrors = true);
    }
  }

  void _showErrorDialog(String msg, {VoidCallback? onRetry}) {
    showPlatformDialog(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: const Text('Fehler'),
        content: Text(msg),
        actions: [
          if (onRetry != null)
            PlatformDialogAction(
              child: const Text('Abbrechen'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          PlatformDialogAction(
            child: Text(onRetry != null ? 'Trotzdem speichern' : 'OK'),
            onPressed: () {
              Navigator.of(context).pop();
              onRetry?.call();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _applyConfigFromUri(Uri uri) async {
    hostController.text = uri.queryParameters['server'] ?? '';
    portController.text = uri.queryParameters['port'] ?? '443';
    tokenController.text = uri.queryParameters['token'] ?? '';
    truppController.text = uri.queryParameters['trupp'] ?? '';
    leiterController.text = uri.queryParameters['leiter'] ?? '';
    issiController.text = uri.queryParameters['issi'] ?? '';
    final proto = uri.queryParameters['protocol'];
    if (proto != null) _selectedProtocol = proto;

    if (_autoSaveAfterScan) {
      await _saveConfig();
    }
  }

  Widget _buildProtocolSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Protokoll',
            style: TextStyle(fontSize: 13, color: Color(0xFF616161), fontWeight: FontWeight.w500),
          ),
        ),
        PlatformWidget(
          material: (_, __) => SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'https', label: Text('HTTPS')),
              ButtonSegment(value: 'http', label: Text('HTTP')),
            ],
            selected: {_selectedProtocol},
            onSelectionChanged: (s) => setState(() => _selectedProtocol = s.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.red.shade800;
                }
                return Colors.grey.shade200;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return Colors.black87;
              }),
            ),
          ),
          cupertino: (_, __) => CupertinoSlidingSegmentedControl<String>(
            groupValue: _selectedProtocol,
            onValueChanged: (v) => setState(() => _selectedProtocol = v ?? 'https'),
            children: const {
              'https': Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('HTTPS'),
              ),
              'http': Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('HTTP'),
              ),
            },
            thumbColor: Colors.red.shade800,
            backgroundColor: CupertinoColors.systemGrey5,
          ),
        ),
      ],
    );
  }

  void _openScannerSheet() {
    showPlatformModalSheet(
      context: context,
      builder: (_) {
        bool handled = false;
        return PlatformWidget(
          material: (_, __) => Container(
            height: MediaQuery.of(context).size.height * 0.75,
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
          cupertino: (_, __) => Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: const BoxDecoration(
              color: CupertinoColors.systemBackground,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey3,
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
      backgroundColor: isMaterial(context) ? Colors.grey[100] : CupertinoColors.systemGroupedBackground,
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
          child: PlatformWidget(
            material: (_, __) => Material(
              color: Colors.grey[100],
              child: _buildForm(),
            ),
            cupertino: (_, __) => Container(
              color: CupertinoColors.systemGroupedBackground,
              child: _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildQRCard(),
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
    );
  }

  Widget _buildQRCard() {
    return PlatformWidget(
      material: (_, __) => Card(
        elevation: 2,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: _buildQRCardContent(),
      ),
      cupertino: (_, __) => Container(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _buildQRCardContent(),
      ),
    );
  }

  Widget _buildQRCardContent() {
    return Padding(
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
                child: Icon(
                  isMaterial(context) ? Icons.qr_code : CupertinoIcons.qrcode,
                  color: Colors.red.shade800,
                  size: 28,
                ),
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
    );
  }
}

class ConfigScreenWithPrefill extends ConfigScreen {
  final Uri initialDeepLink;

  const ConfigScreenWithPrefill({super.key, required this.initialDeepLink});
}
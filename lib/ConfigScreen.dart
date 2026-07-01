// lib/screens/ConfigScreen.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'home_shell.dart';
import 'data/edp_api.dart';
import 'data/edp_api_pro.dart';
import 'data/alarm_service.dart';
import 'data/profile_store.dart';
import 'pro/pro_dashboard_screen.dart';
import 'pro/issi_picker_screen.dart';
import 'data/app_logger.dart';
import 'theme/brand_colors.dart';

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
  final pbUrlController = TextEditingController();
  final proApiUrlController = TextEditingController();

  String _selectedProtocol = 'https';
  bool _showManualConfig = false;
  bool _autoSaveAfterScan = false;
  bool _showAllErrors = false;
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
    pbUrlController.dispose();
    proApiUrlController.dispose();
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

    _loadExistingConfig();

    AlarmService.loadPbUrl().then((url) {
      if (url != null && mounted) pbUrlController.text = url;
    });

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

  Future<void> _loadExistingConfig() async {
    try {
      final api = EdpApi.instance;
      final cfg = api.config;
      if (!cfg.isComplete) return;
      if (!mounted) return;
      setState(() {
        hostController.text = cfg.host;
        portController.text = cfg.port.toString();
        _selectedProtocol = cfg.protocol;
        tokenController.text = cfg.token;
        issiController.text = cfg.issi;
        truppController.text = cfg.trupp;
        leiterController.text = cfg.leiter;
        proApiUrlController.text = cfg.proApiUrl;
      });
    } catch (e, st) {
      AppLogger.w('ConfigScreen', 'Bestehende Config konnte nicht geladen werden', e);
    }
  }

  bool get _hasConfig =>
      hostController.text.trim().isNotEmpty &&
      tokenController.text.trim().isNotEmpty;

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

  Widget _requiredField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    final missing = _isMissing(controller);
    final autoMode = _showAllErrors
        ? AutovalidateMode.always
        : AutovalidateMode.onUserInteraction;
    return TextFormField(
      controller: controller,
      autovalidateMode: autoMode,
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      decoration: _materialDecoration(label, missing: missing),
    );
  }

  Widget _optionalField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: _materialDecoration(label, missing: false),
    );
  }

  Widget _issiField() {
    final missing = _isMissing(issiController);
    final autoMode = _showAllErrors
        ? AutovalidateMode.always
        : AutovalidateMode.onUserInteraction;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: issiController,
            autovalidateMode: autoMode,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: _materialDecoration('ISSI*', missing: missing),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 56,
          child: OutlinedButton.icon(
            onPressed: () async {
              final api = EdpApiPro.instance;
              if (api == null || !api.hasToken) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                        'Bitte zuerst Pro-Funktionen einrichten (Karte unten)'),
                    backgroundColor: Theme.of(context).brand.warning,
                  ),
                );
                return;
              }
              final result = await Navigator.push<IssiPickerResult>(
                context,
                MaterialPageRoute(
                    builder: (_) => const IssiPickerScreen()),
              );
              if (result != null && mounted) {
                setState(() {
                  issiController.text = result.issi;
                  if (result.trupp.isNotEmpty) {
                    truppController.text = result.trupp;
                  }
                  if (result.leiter.isNotEmpty) {
                    leiterController.text = result.leiter;
                  }
                });
              }
            },
            icon: const Icon(Icons.radio, size: 18),
            label: const Text('Server', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
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
        proApiUrl: proApiUrlController.text.trim(),
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
              await AlarmService.savePbUrl(pbUrlController.text.trim());
              await _autoSaveProfile(cfg);
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeShell()),
                  (_) => false,
                );
              }
            },
          );
          return;
        }

        await api.updateConfig(cfg);
        await AlarmService.savePbUrl(pbUrlController.text.trim());
        await _autoSaveProfile(cfg);
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeShell()),
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

  /// Speichert die aktuelle Konfiguration automatisch als Profil. Der Name
  /// wird aus Truppname + ISSI zusammengesetzt, damit Profile pro Einheit
  /// eindeutig sind und beim erneuten Speichern überschrieben werden.
  Future<void> _autoSaveProfile(EdpConfig cfg) async {
    final issi = cfg.issi.trim();
    if (issi.isEmpty) return;
    final trupp = cfg.trupp.trim();
    final name = trupp.isNotEmpty ? '$trupp ($issi)' : 'ISSI $issi';
    final profile = AppProfile(
      name: name,
      protocol: cfg.protocol,
      server: '${cfg.host}:${cfg.port}',
      token: cfg.token,
      issi: issi,
      trupp: trupp,
      leiter: cfg.leiter,
      pbUrl: pbUrlController.text.trim(),
    );
    try {
      await ProfileStore.save(profile);
    } catch (e) {
      AppLogger.w('ConfigScreen', 'Auto-Save als Profil fehlgeschlagen', e);
    }
  }

  Future<void> _saveAsProfile() async {
    final server = '${hostController.text.trim()}:${portController.text.trim()}';
    if (server.trim() == ':' ||
        tokenController.text.trim().isEmpty ||
        issiController.text.trim().isEmpty) {
      _showErrorDialog('Bitte zuerst alle Pflichtfelder ausfüllen.');
      return;
    }

    final nameResult = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Profilname'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration:
                const InputDecoration(hintText: 'z. B. FF Musterstadt'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
                child: const Text('Abbrechen'),
                onPressed: () => Navigator.pop(ctx)),
            TextButton(
                child: const Text('Speichern'),
                onPressed: () => Navigator.pop(ctx, ctrl.text)),
          ],
        );
      },
    );

    final profileName = nameResult?.trim() ?? '';
    if (profileName.isEmpty) return;

    final profile = AppProfile(
      name: profileName,
      protocol: _selectedProtocol,
      server: server,
      token: tokenController.text.trim(),
      issi: issiController.text.trim(),
      trupp: truppController.text.trim(),
      leiter: leiterController.text.trim(),
      pbUrl: pbUrlController.text.trim(),
    );
    await ProfileStore.save(profile);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profil "$profileName" gespeichert'),
          backgroundColor: Theme.of(context).brand.success,
        ),
      );
    }
  }

  void _showErrorDialog(String msg, {VoidCallback? onRetry}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fehler'),
        content: Text(msg),
        actions: [
          if (onRetry != null)
            TextButton(
              child: const Text('Abbrechen'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          TextButton(
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
    setState(() {
      hostController.text = uri.queryParameters['server'] ?? '';
      portController.text = uri.queryParameters['port'] ?? '443';
      tokenController.text = uri.queryParameters['token'] ?? '';
      truppController.text = uri.queryParameters['trupp'] ?? '';
      leiterController.text = uri.queryParameters['leiter'] ?? '';
      issiController.text = uri.queryParameters['issi'] ?? '';
      if (uri.queryParameters.containsKey('pb_url')) {
        pbUrlController.text = uri.queryParameters['pb_url']!;
      }
      if (uri.queryParameters.containsKey('pro_api_url')) {
        proApiUrlController.text = uri.queryParameters['pro_api_url']!;
      }
      final proto = uri.queryParameters['protocol'];
      if (proto != null) _selectedProtocol = proto;
      // Auto-expand form so user can review what was filled in
      _showManualConfig = true;
    });

    // Auto-login to Pro if credentials are embedded in the QR
    final edpUser = uri.queryParameters['edp_user'];
    final edpPass = uri.queryParameters['edp_pass'];
    if (edpUser != null && edpPass != null && edpUser.isNotEmpty) {
      try {
        final cfg = EdpConfig(
          protocol: _selectedProtocol,
          host: hostController.text.trim(),
          port: int.tryParse(portController.text.trim()) ?? 443,
          token: tokenController.text.trim(),
          issi: issiController.text.trim(),
          trupp: truppController.text.trim(),
          leiter: leiterController.text.trim(),
          proApiUrl: proApiUrlController.text.trim(),
        );
        final proApi = await EdpApiPro.init(cfg);
        final ok = await proApi.login(edpUser, edpPass);
        if (ok) {
          await EdpApiPro.saveCredentials(edpUser, edpPass);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Pro-API automatisch verbunden'),
                backgroundColor: Theme.of(context).brand.success,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } catch (_) {}
    }

    if (_autoSaveAfterScan) {
      await _saveConfig();
    }
  }

  Widget _buildProtocolSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Protokoll',
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500),
          ),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'https', label: Text('HTTPS')),
            ButtonSegment(value: 'http', label: Text('HTTP')),
          ],
          selected: {_selectedProtocol},
          onSelectionChanged: (s) =>
              setState(() => _selectedProtocol = s.first),
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
      ],
    );
  }

  void _openScannerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        bool handled = false;
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
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
                        final code =
                            capture.barcodes.firstOrNull?.rawValue;
                        if (code == null) return;
                        try {
                          final uri = Uri.parse(code);
                          handled = true;
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                          await _applyConfigFromUri(uri);
                        } catch (e) {
                          _showErrorDialog(
                              'Fehler beim Lesen des QR-Codes: $e');
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Konfiguration'),
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
      body: SafeArea(
        bottom: true,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.grey[100],
            child: _buildForm(),
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
          const SizedBox(height: 16),
          _buildManualToggle(),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            child: _showManualConfig
                ? _buildManualConfigSection()
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          _buildProCard(),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildProCard() {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProDashboardScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.workspace_premium,
                    color: cs.primary, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pro-Funktionen',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Einsatzliste, EDP-Bestand, ISSI-Auswahl',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQRCard() {
    return Card(
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Builder(builder: (context) {
                  final brand = Theme.of(context).brand;
                  final accent = _hasConfig
                      ? brand.success
                      : Theme.of(context).colorScheme.primary;
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _hasConfig ? Icons.check_circle : Icons.qr_code,
                      color: accent,
                      size: 28,
                    ),
                  );
                }),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hasConfig
                            ? 'Konfiguriert'
                            : 'Gerät einrichten',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      if (_hasConfig)
                        Text(
                          '${hostController.text}:${portController.text}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600),
                        )
                      else
                        Text(
                          'QR-Code vom Administrator scannen',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _openScannerSheet,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(_hasConfig ? 'Neu einscannen' : 'QR-Code scannen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualToggle() {
    return OutlinedButton.icon(
      onPressed: () =>
          setState(() => _showManualConfig = !_showManualConfig),
      icon: Icon(
        _showManualConfig ? Icons.keyboard_arrow_up : Icons.settings,
        size: 20,
      ),
      label: Text(_showManualConfig
          ? 'Manuell konfigurieren – schließen'
          : 'Manuell konfigurieren'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.grey.shade700,
        side: BorderSide(color: Colors.grey.shade400),
        minimumSize: const Size.fromHeight(48),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildManualConfigSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            'EDP-Webhook-Server',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'GPS-Tracking und Statusmeldungen (Webhook-Schnittstelle).',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
        _buildProtocolSelector(),
        const SizedBox(height: 16),
        _requiredField(
          label: 'Webhook-Server* (z. B. edp.example.org)',
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
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Geräteprofil',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800),
          ),
        ),
        _issiField(),
        const SizedBox(height: 16),
        _optionalField(label: 'Truppname', controller: truppController),
        const SizedBox(height: 16),
        _optionalField(
            label: 'Ansprechpartner', controller: leiterController),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            'EDP-Pro-API (optional)',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Separater EDP-Pro-API-Server – ausschließlich für ISSI-Auswahl (Tetra-Endgeräte, Fahrzeugabfrage).',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ),
        _optionalField(
          label: 'EDP-Pro-API-URL (z. B. https://api.example.org)',
          controller: proApiUrlController,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            'Bereitschafts-App / Alarmierung (optional)',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'PocketBase-Server der Bereitschafts-App – für Echtzeit-Alarmierungen.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ),
        _optionalField(
          label: 'Bereitschafts-App-URL (z. B. https://pb.example.org)',
          controller: pbUrlController,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '* Pflichtfelder',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _saveConfig,
          icon: const Icon(Icons.save),
          label: const Text('Speichern und fortfahren'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _saveAsProfile,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Als Profil speichern'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.primary,
            side: BorderSide(color: Theme.of(context).colorScheme.primary),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class ConfigScreenWithPrefill extends ConfigScreen {
  final Uri initialDeepLink;

  const ConfigScreenWithPrefill({super.key, required this.initialDeepLink});
}

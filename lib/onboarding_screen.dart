// lib/onboarding_screen.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';

import 'data/edp_api.dart';
import 'data/edp_api_pro.dart';
import 'data/alarm_service.dart';
import 'data/unit_type_store.dart';
import 'pro/issi_picker_screen.dart';
import 'status_overview_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _isAnimating = false;

  // Config state (from QR or manual form)
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '443');
  final _tokenCtrl = TextEditingController();
  final _issiCtrl = TextEditingController();
  final _truppCtrl = TextEditingController();
  final _leiterCtrl = TextEditingController();
  final _pbUrlCtrl = TextEditingController();
  String _protocol = 'https';
  bool _showManualForm = false;
  bool _configReady = false;  // host + token filled in
  bool _isSaving = false;

  // Pro API available for ISSI lookup
  bool _proApiConnected = false;

  // Unit type
  UnitType? _selectedUnitType;

  // Permission states
  bool _locationGranted = false;
  bool _bgLocationGranted = false;
  bool _notifGranted = false;
  bool _batteryOptDisabled = false;

  // Pages determined at runtime (Android-only battery page)
  late final List<_PageKey> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      _PageKey.welcome,
      _PageKey.issi,
      _PageKey.location,
      _PageKey.bgLocation,
      _PageKey.notifications,
      if (!kIsWeb && Platform.isAndroid) _PageKey.battery,
      _PageKey.unitType,
      _PageKey.done,
    ];
    _checkPermissions();
    _checkProApi();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _tokenCtrl.dispose();
    _issiCtrl.dispose();
    _truppCtrl.dispose();
    _leiterCtrl.dispose();
    _pbUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    try {
      final locPerm = await Geolocator.checkPermission();
      _locationGranted = locPerm == LocationPermission.whileInUse ||
          locPerm == LocationPermission.always;
      _bgLocationGranted = locPerm == LocationPermission.always;
      if (!kIsWeb && Platform.isAndroid) {
        final notif = await Permission.notification.status;
        _notifGranted = notif.isGranted;
        final batOpt =
            await DisableBatteryOptimization.isBatteryOptimizationDisabled;
        _batteryOptDisabled = batOpt ?? false;
      } else {
        _notifGranted = true;
        _batteryOptDisabled = true;
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _checkProApi() {
    final api = EdpApiPro.instance;
    if (api != null && api.hasToken) {
      setState(() => _proApiConnected = true);
    }
  }

  void _nextPage() {
    if (_isAnimating) return;
    final next = _currentPage + 1;
    if (next < _pages.length) {
      _isAnimating = true;
      _pageController
          .animateToPage(next,
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeInOut)
          .then((_) => _isAnimating = false);
    }
  }

  void _prevPage() {
    if (_isAnimating) return;
    final prev = _currentPage - 1;
    if (prev >= 0) {
      _isAnimating = true;
      _pageController
          .animateToPage(prev,
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeInOut)
          .then((_) => _isAnimating = false);
    }
  }

  // Opens the QR scanner bottom sheet
  void _openScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QrScannerSheet(
        onScanned: (uri) async {
          await _applyConfigFromUri(uri);
          if (mounted) _nextPage();
        },
      ),
    );
  }

  Future<void> _applyConfigFromUri(Uri uri) async {
    final host = uri.queryParameters['server'] ?? '';
    final port = uri.queryParameters['port'] ?? '443';
    final token = uri.queryParameters['token'] ?? '';
    final issi = uri.queryParameters['issi'] ?? '';
    final trupp = uri.queryParameters['trupp'] ?? '';
    final leiter = uri.queryParameters['leiter'] ?? '';
    final pbUrl = uri.queryParameters['pb_url'] ?? '';
    final proto = uri.queryParameters['protocol'] ?? 'https';

    setState(() {
      _hostCtrl.text = host;
      _portCtrl.text = port;
      _tokenCtrl.text = token;
      _issiCtrl.text = issi;
      _truppCtrl.text = trupp;
      _leiterCtrl.text = leiter;
      _pbUrlCtrl.text = pbUrl;
      _protocol = proto;
      _configReady = host.isNotEmpty && token.isNotEmpty;
    });

    // Try auto-login to Pro API if credentials embedded in QR
    final edpUser = uri.queryParameters['edp_user'];
    final edpPass = uri.queryParameters['edp_pass'];
    if (edpUser != null &&
        edpPass != null &&
        edpUser.isNotEmpty &&
        host.isNotEmpty &&
        token.isNotEmpty) {
      try {
        final cfg = EdpConfig(
          protocol: proto,
          host: host,
          port: int.tryParse(port) ?? 443,
          token: token,
          issi: issi,
          trupp: trupp,
          leiter: leiter,
        );
        final proApi = await EdpApiPro.init(cfg);
        final ok = await proApi.login(edpUser, edpPass);
        if (ok) {
          await EdpApiPro.saveCredentials(edpUser, edpPass);
          if (mounted) setState(() => _proApiConnected = true);
        }
      } catch (_) {}
    }
  }

  // Saves the full config (called from ISSI step "Weiter")
  Future<bool> _persistConfig() async {
    final host = _hostCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    if (host.isEmpty || token.isEmpty) return false;

    setState(() => _isSaving = true);
    try {
      final cfg = EdpConfig(
        protocol: _protocol,
        host: host,
        port: int.tryParse(_portCtrl.text.trim()) ?? 443,
        token: token,
        issi: _issiCtrl.text.trim(),
        trupp: _truppCtrl.text.trim(),
        leiter: _leiterCtrl.text.trim(),
      );
      await EdpApi.initWithConfig(cfg);
      await AlarmService.savePbUrl(_pbUrlCtrl.text.trim());
      if (mounted) setState(() => _isSaving = false);
      return true;
    } catch (_) {
      if (mounted) setState(() => _isSaving = false);
      return false;
    }
  }

  Future<void> _finishOnboarding() async {
    if (_selectedUnitType != null) {
      await UnitTypeStore.save(_selectedUnitType!);
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const StatusOverview()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _ProgressHeader(
              currentPage: _currentPage,
              totalPages: _pages.length,
              onBack: _currentPage > 0 ? _prevPage : null,
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: _pages.map(_buildPage).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_PageKey key) {
    switch (key) {
      case _PageKey.welcome:
        return _WelcomePage(
          showManualForm: _showManualForm,
          onToggleManual: () =>
              setState(() => _showManualForm = !_showManualForm),
          onScanQR: _openScanner,
          protocol: _protocol,
          onProtocolChanged: (p) => setState(() => _protocol = p),
          hostCtrl: _hostCtrl,
          portCtrl: _portCtrl,
          tokenCtrl: _tokenCtrl,
          truppCtrl: _truppCtrl,
          leiterCtrl: _leiterCtrl,
          pbUrlCtrl: _pbUrlCtrl,
          isSaving: _isSaving,
          configReady: _configReady,
          onFieldChanged: () => setState(() {
            _configReady = _hostCtrl.text.trim().isNotEmpty &&
                _tokenCtrl.text.trim().isNotEmpty;
          }),
          onNext: () {
            if (_hostCtrl.text.trim().isEmpty ||
                _tokenCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Bitte Server und Token ausfüllen.'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            setState(() => _configReady = true);
            _nextPage();
          },
        );

      case _PageKey.issi:
        return _IssiPage(
          issiCtrl: _issiCtrl,
          proApiConnected: _proApiConnected,
          isSaving: _isSaving,
          onPickFromServer: () async {
            final api = EdpApiPro.instance;
            if (api == null || !api.hasToken) return;
            final issi = await Navigator.push<String>(
              context,
              MaterialPageRoute(builder: (_) => const IssiPickerScreen()),
            );
            if (issi != null && mounted) {
              setState(() => _issiCtrl.text = issi);
            }
          },
          onNext: () async {
            final ok = await _persistConfig();
            if (ok && mounted) _nextPage();
          },
        );

      case _PageKey.location:
        return _PermissionPage(
          icon: Icons.location_on_rounded,
          iconColor: Colors.blue.shade600,
          iconBg: Colors.blue.shade50,
          title: 'Standort-Berechtigung',
          subtitle: 'GPS-Koordinaten im Einsatz',
          description:
              'TruppApp überträgt deinen Standort zusammen mit Status-Meldungen. '
              'So sieht der Einsatzleiter die Position aller Einheiten in Echtzeit.',
          granted: _locationGranted,
          grantedLabel: 'Standort-Zugriff erteilt',
          buttonLabel: 'Standort erlauben',
          onRequest: () async {
            final p = await Geolocator.requestPermission();
            setState(() {
              _locationGranted = p == LocationPermission.whileInUse ||
                  p == LocationPermission.always;
              _bgLocationGranted = p == LocationPermission.always;
            });
          },
          onNext: _nextPage,
          skippable: true,
        );

      case _PageKey.bgLocation:
        return _PermissionPage(
          icon: Icons.my_location_rounded,
          iconColor: Colors.teal.shade600,
          iconBg: Colors.teal.shade50,
          title: 'Hintergrund-Ortung',
          subtitle: 'Kontinuierliches Tracking',
          description:
              'Damit TruppApp auch bei gesperrtem Bildschirm oder '
              'beim Wechsel in andere Apps tracken kann, wird Hintergrund-Ortung benötigt.',
          granted: _bgLocationGranted,
          grantedLabel: 'Hintergrund-Ortung erteilt',
          buttonLabel: 'Immer erlauben',
          onRequest: () async {
            if (!kIsWeb && Platform.isAndroid) {
              final p = await Permission.locationAlways.request();
              setState(() => _bgLocationGranted = p.isGranted);
            } else {
              await Geolocator.openLocationSettings();
            }
          },
          onNext: _nextPage,
          skippable: true,
        );

      case _PageKey.notifications:
        return _PermissionPage(
          icon: Icons.notifications_active_rounded,
          iconColor: Colors.orange.shade700,
          iconBg: Colors.orange.shade50,
          title: 'Alarmbenachrichtigungen',
          subtitle: 'Auch bei gesperrtem Bildschirm',
          description:
              'Lass dich durch Push-Benachrichtigungen über eingehende Alarmierungen '
              'informieren – auch wenn die App im Hintergrund läuft.',
          granted: _notifGranted,
          grantedLabel: 'Benachrichtigungen erteilt',
          buttonLabel: 'Benachrichtigungen erlauben',
          onRequest: () async {
            if (!kIsWeb && Platform.isAndroid) {
              final p = await Permission.notification.request();
              setState(() => _notifGranted = p.isGranted);
            } else {
              setState(() => _notifGranted = true);
            }
          },
          onNext: _nextPage,
          skippable: true,
        );

      case _PageKey.battery:
        return _BatteryPage(
          optimizationDisabled: _batteryOptDisabled,
          onDisable: () async {
            await DisableBatteryOptimization
                .showDisableBatteryOptimizationSettings();
            final isDisabled =
                await DisableBatteryOptimization.isBatteryOptimizationDisabled;
            if (mounted) setState(() => _batteryOptDisabled = isDisabled ?? false);
          },
          onNext: _nextPage,
        );

      case _PageKey.unitType:
        return _UnitTypePage(
          selected: _selectedUnitType,
          onSelected: (ut) => setState(() => _selectedUnitType = ut),
          onNext: _nextPage,
        );

      case _PageKey.done:
        return _DonePage(
          host: _hostCtrl.text.trim().isNotEmpty
              ? _hostCtrl.text.trim()
              : null,
          unitType: _selectedUnitType,
          onFinish: _finishOnboarding,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Page key enum
// ---------------------------------------------------------------------------

enum _PageKey {
  welcome,
  issi,
  location,
  bgLocation,
  notifications,
  battery,
  unitType,
  done,
}

// ---------------------------------------------------------------------------
// Progress Header
// ---------------------------------------------------------------------------

class _ProgressHeader extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final VoidCallback? onBack;

  const _ProgressHeader({
    required this.currentPage,
    required this.totalPages,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 4),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: onBack != null
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: onBack,
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.grey.shade600,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(totalPages, (i) {
                final active = i == currentPage;
                final done = i < currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: done
                        ? Colors.red.shade300
                        : active
                            ? Colors.red.shade800
                            : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${currentPage + 1}/$totalPages',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QR Scanner Bottom Sheet
// ---------------------------------------------------------------------------

class _QrScannerSheet extends StatefulWidget {
  final Future<void> Function(Uri uri) onScanned;

  const _QrScannerSheet({required this.onScanned});

  @override
  State<_QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<_QrScannerSheet> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 20),
          Icon(Icons.qr_code_scanner_rounded,
              size: 36, color: Colors.red.shade800),
          const SizedBox(height: 8),
          Text(
            'QR-Code scannen',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Halte die Kamera auf den Konfigurations-QR-Code\ndes Administrators.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: MobileScanner(
                  onDetect: (capture) async {
                    if (_handled) return;
                    final code = capture.barcodes.firstOrNull?.rawValue;
                    if (code == null) return;
                    try {
                      final uri = Uri.parse(code);
                      _handled = true;
                      if (context.mounted) Navigator.of(context).pop();
                      await widget.onScanned(uri);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('QR-Code ungültig: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 0 – Welcome / Setup
// ---------------------------------------------------------------------------

class _WelcomePage extends StatelessWidget {
  final bool showManualForm;
  final VoidCallback onToggleManual;
  final VoidCallback onScanQR;
  final String protocol;
  final ValueChanged<String> onProtocolChanged;
  final TextEditingController hostCtrl;
  final TextEditingController portCtrl;
  final TextEditingController tokenCtrl;
  final TextEditingController truppCtrl;
  final TextEditingController leiterCtrl;
  final TextEditingController pbUrlCtrl;
  final bool isSaving;
  final bool configReady;
  final VoidCallback onFieldChanged;
  final VoidCallback onNext;

  const _WelcomePage({
    required this.showManualForm,
    required this.onToggleManual,
    required this.onScanQR,
    required this.protocol,
    required this.onProtocolChanged,
    required this.hostCtrl,
    required this.portCtrl,
    required this.tokenCtrl,
    required this.truppCtrl,
    required this.leiterCtrl,
    required this.pbUrlCtrl,
    required this.isSaving,
    required this.configReady,
    required this.onFieldChanged,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          // Logo / App icon area
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Colors.red.shade800,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.shade200,
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.emergency_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Willkommen bei\nTruppApp',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Einrichtung in wenigen Schritten',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 32),

          // Primary: QR code
          ElevatedButton.icon(
            onPressed: onScanQR,
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 26),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Mit QR-Code einrichten',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(60),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 2,
            ),
          ),

          const SizedBox(height: 16),

          // Divider
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade200)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'oder',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade200)),
            ],
          ),

          const SizedBox(height: 16),

          // Secondary: Manual
          OutlinedButton.icon(
            onPressed: onToggleManual,
            icon: Icon(
              showManualForm
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.settings_rounded,
              size: 20,
            ),
            label: Text(
              showManualForm
                  ? 'Manuelle Einstellungen schließen'
                  : 'Manuell konfigurieren',
              style: const TextStyle(fontSize: 15),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              side: BorderSide(color: Colors.grey.shade300),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),

          // Animated manual form
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: showManualForm
                ? _ManualConfigForm(
                    protocol: protocol,
                    onProtocolChanged: onProtocolChanged,
                    hostCtrl: hostCtrl,
                    portCtrl: portCtrl,
                    tokenCtrl: tokenCtrl,
                    truppCtrl: truppCtrl,
                    leiterCtrl: leiterCtrl,
                    pbUrlCtrl: pbUrlCtrl,
                    onFieldChanged: onFieldChanged,
                  )
                : const SizedBox.shrink(),
          ),

          if (showManualForm || configReady) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: isSaving ? null : onNext,
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.arrow_forward_rounded),
              label: const Text(
                'Weiter',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manual Config Form (embedded in welcome page)
// ---------------------------------------------------------------------------

class _ManualConfigForm extends StatelessWidget {
  final String protocol;
  final ValueChanged<String> onProtocolChanged;
  final TextEditingController hostCtrl;
  final TextEditingController portCtrl;
  final TextEditingController tokenCtrl;
  final TextEditingController truppCtrl;
  final TextEditingController leiterCtrl;
  final TextEditingController pbUrlCtrl;
  final VoidCallback onFieldChanged;

  const _ManualConfigForm({
    required this.protocol,
    required this.onProtocolChanged,
    required this.hostCtrl,
    required this.portCtrl,
    required this.tokenCtrl,
    required this.truppCtrl,
    required this.leiterCtrl,
    required this.pbUrlCtrl,
    required this.onFieldChanged,
  });

  InputDecoration _dec(String label, {bool required = false}) {
    return InputDecoration(
      labelText: required ? '$label *' : label,
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade800, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('Server & Zugangsdaten'),
          const SizedBox(height: 12),
          // Protocol
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'https', label: Text('HTTPS')),
              ButtonSegment(value: 'http', label: Text('HTTP')),
            ],
            selected: {protocol},
            onSelectionChanged: (s) => onProtocolChanged(s.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.red.shade800;
                }
                return Colors.grey.shade100;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return Colors.black87;
              }),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: hostCtrl,
            onChanged: (_) => onFieldChanged(),
            decoration: _dec('EDP Server (z. B. test.local)', required: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: portCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => onFieldChanged(),
            decoration: _dec('Port', required: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: tokenCtrl,
            onChanged: (_) => onFieldChanged(),
            decoration: _dec('Token', required: true),
          ),
          const SizedBox(height: 20),
          _SectionLabel('Geräteprofil (optional)'),
          const SizedBox(height: 12),
          TextField(
            controller: truppCtrl,
            decoration: _dec('Truppname'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: leiterCtrl,
            decoration: _dec('Ansprechpartner'),
          ),
          const SizedBox(height: 20),
          _SectionLabel('Alarmierung (optional)'),
          const SizedBox(height: 12),
          TextField(
            controller: pbUrlCtrl,
            keyboardType: TextInputType.url,
            decoration: _dec('PocketBase-URL (z. B. https://pb.example.org)'),
          ),
          const SizedBox(height: 6),
          Text(
            'Wenn gesetzt, empfängt dieses Gerät EDP-Alarmierungen in Echtzeit.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text(
            '* Pflichtfelder',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 1 – ISSI selection
// ---------------------------------------------------------------------------

class _IssiPage extends StatelessWidget {
  final TextEditingController issiCtrl;
  final bool proApiConnected;
  final bool isSaving;
  final VoidCallback onPickFromServer;
  final Future<void> Function() onNext;

  const _IssiPage({
    required this.issiCtrl,
    required this.proApiConnected,
    required this.isSaving,
    required this.onPickFromServer,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.radio_rounded,
                  size: 44, color: Colors.indigo.shade600),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'ISSI auswählen',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Wähle das TETRA-Endgerät für dieses Gerät.\nDie ISSI identifiziert deine Einheit im Funknetz.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: Colors.grey.shade500, height: 1.5),
          ),
          const SizedBox(height: 32),

          if (proApiConnected) ...[
            // Server pick
            ElevatedButton.icon(
              onPressed: onPickFromServer,
              icon: const Icon(Icons.dns_rounded, size: 20),
              label: const Text(
                'Vom EDP-Pro Server abrufen',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Divider(color: Colors.grey.shade200)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'oder manuell',
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 12),
                  ),
                ),
                Expanded(child: Divider(color: Colors.grey.shade200)),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Manual ISSI entry
          TextField(
            controller: issiCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'ISSI-Nummer eingeben',
              hintText: 'z. B. 123456789',
              prefixIcon:
                  Icon(Icons.dialpad_rounded, color: Colors.indigo.shade400),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: Colors.indigo.shade700, width: 2),
              ),
            ),
          ),

          const Spacer(),

          // Weiter
          ElevatedButton(
            onPressed: isSaving ? null : () async => await onNext(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text(
                    'Weiter',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Permission slide page (reused for location, bgLocation, notifications)
// ---------------------------------------------------------------------------

class _PermissionPage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String description;
  final bool granted;
  final String grantedLabel;
  final String buttonLabel;
  final Future<void> Function() onRequest;
  final VoidCallback onNext;
  final bool skippable;

  const _PermissionPage({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.granted,
    required this.grantedLabel,
    required this.buttonLabel,
    required this.onRequest,
    required this.onNext,
    this.skippable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 50, color: iconColor),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: iconColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade700,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Status indicator
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: granted
                ? Container(
                    key: const ValueKey('granted'),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: Colors.green.shade600, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          grantedLabel,
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : ElevatedButton.icon(
                    key: const ValueKey('not-granted'),
                    onPressed: () async => await onRequest(),
                    icon: Icon(icon, size: 20),
                    label: Text(
                      buttonLabel,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: iconColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
          ),

          const Spacer(),

          Row(
            children: [
              if (skippable && !granted) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onNext,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade500,
                      side: BorderSide(color: Colors.grey.shade200),
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Überspringen'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Weiter',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Battery Optimization page (Android only)
// ---------------------------------------------------------------------------

class _BatteryPage extends StatelessWidget {
  final bool optimizationDisabled;
  final Future<void> Function() onDisable;
  final VoidCallback onNext;

  const _BatteryPage({
    required this.optimizationDisabled,
    required this.onDisable,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.battery_charging_full_rounded,
                  size: 50, color: Colors.amber.shade700),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Akku-Optimierung',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Für zuverlässiges Hintergrund-Tracking',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.amber.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              'Android schränkt Apps im Hintergrund ein, um Akku zu sparen. '
              'Damit TruppApp dich im Einsatz zuverlässig trackt, '
              'sollte die Akku-Optimierung für TruppApp deaktiviert sein.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15, color: Colors.grey.shade700, height: 1.6),
            ),
          ),
          const SizedBox(height: 24),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: optimizationDisabled
                ? Container(
                    key: const ValueKey('ok'),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: Colors.green.shade600, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Optimierung deaktiviert',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : ElevatedButton.icon(
                    key: const ValueKey('not-ok'),
                    onPressed: () async => await onDisable(),
                    icon: const Icon(Icons.battery_saver_rounded, size: 20),
                    label: const Text(
                      'Akku-Optimierung deaktivieren',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
          ),

          const Spacer(),

          Row(
            children: [
              if (!optimizationDisabled) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onNext,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade500,
                      side: BorderSide(color: Colors.grey.shade200),
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Überspringen'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Weiter',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page – Unit Type selection
// ---------------------------------------------------------------------------

class _UnitTypePage extends StatelessWidget {
  final UnitType? selected;
  final ValueChanged<UnitType> onSelected;
  final VoidCallback onNext;

  const _UnitTypePage({
    required this.selected,
    required this.onSelected,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text(
            'Welchen Modus nutzt du?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Du kannst die Auswahl jederzeit im Menü ändern.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: UnitType.values.map((ut) {
                return _UnitTypeCard(
                  unitType: ut,
                  isSelected: selected == ut,
                  onTap: () => onSelected(ut),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: selected != null ? onNext : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade200,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              selected != null ? 'Weiter' : 'Modus auswählen',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitTypeCard extends StatelessWidget {
  final UnitType unitType;
  final bool isSelected;
  final VoidCallback onTap;

  const _UnitTypeCard({
    required this.unitType,
    required this.isSelected,
    required this.onTap,
  });

  Color get _color {
    switch (unitType) {
      case UnitType.erfahren:
        return Colors.red.shade700;
      case UnitType.rettungshunde:
        return Colors.orange.shade700;
      case UnitType.helfer:
        return Colors.blue.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected ? _color.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? _color : Colors.grey.shade200,
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _color.withOpacity(0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(unitType.icon, color: _color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unitType.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: isSelected ? _color : Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      unitType.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isSelected
                    ? Icon(Icons.check_circle_rounded,
                        key: const ValueKey('checked'),
                        color: _color,
                        size: 26)
                    : Icon(Icons.circle_outlined,
                        key: const ValueKey('unchecked'),
                        color: Colors.grey.shade300,
                        size: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Done page
// ---------------------------------------------------------------------------

class _DonePage extends StatelessWidget {
  final String? host;
  final UnitType? unitType;
  final Future<void> Function() onFinish;

  const _DonePage({
    this.host,
    this.unitType,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.shade100,
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(Icons.check_circle_rounded,
                  size: 58, color: Colors.green.shade600),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Alles bereit!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'TruppApp ist eingerichtet und bereit für den Einsatz.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15, color: Colors.grey.shade500, height: 1.5),
          ),
          const SizedBox(height: 28),

          // Summary card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                if (host != null)
                  _SummaryRow(
                      icon: Icons.dns_rounded,
                      label: 'Server',
                      value: host!),
                if (host != null && unitType != null)
                  Divider(height: 20, color: Colors.grey.shade200),
                if (unitType != null)
                  _SummaryRow(
                      icon: unitType!.icon,
                      label: 'Modus',
                      value: unitType!.label),
              ],
            ),
          ),

          const Spacer(),

          ElevatedButton.icon(
            onPressed: () async => await onFinish(),
            icon: const Icon(Icons.rocket_launch_rounded, size: 22),
            label: const Text(
              'App starten',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(58),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.grey.shade600,
        letterSpacing: 0.5,
      ),
    );
  }
}

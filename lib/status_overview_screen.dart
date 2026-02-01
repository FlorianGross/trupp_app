// lib/screens/status_overview_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:trupp_app/system_check_screen.dart';
import 'ConfigScreen.dart';
import 'keypad_widget.dart';
import 'data/edp_api.dart';
import 'data/gpx_exporter.dart';
import 'data/location_queue.dart';
import 'data/location_sync_manager.dart';
import 'data/deployment_state.dart';
import 'data/adaptive_location_settings.dart';

class StatusOverview extends StatefulWidget {
  const StatusOverview({super.key});

  @override
  State<StatusOverview> createState() => _StatusOverviewState();
}

class _StatusOverviewState extends State<StatusOverview> with SingleTickerProviderStateMixin {
  // Config
  String protocol = 'https', server = 'localhost', port = '443', token = '';
  String trupp = 'Unbekannt', leiter = 'Unbekannt', issi = '0000';

  static const _kBgPromptShownKey = 'bgPromptShown';

  // UI/Status
  int? selectedStatus;
  int? _lastPersistentStatus;
  Timer? _tempStatusTimer;
  Timer? _statsRefreshTimer;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _showMessageField = false; // Collapsible message field

  // Deployment & Tracking State
  DeploymentMode _deploymentMode = DeploymentMode.standby;
  TrackingMode _trackingMode = TrackingMode.balanced;
  int _batteryLevel = 100;

  // Stats
  Map<String, int> _stats = {'pending': 0, 'total': 0};

  bool get _trackingDesired =>
      [1, 3, 7].contains(_lastPersistentStatus ?? selectedStatus ?? -1);

  // Hintergrund-Tracking-Indikator
  bool _bgTrackingActive = false;

  // Kurzstatus 0/9/5 → nach 5s zurück
  bool _isTempStatus(int s) => s == 0 || s == 9 || s == 5;
  static const Map<int, Duration> _tempDurations = {
    0: Duration(seconds: 5),
    9: Duration(seconds: 5),
    5: Duration(seconds: 5),
  };

  // Sende-Drossel
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _sendInterval = Duration(seconds: 2);

  final TextEditingController _infoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
    _initialize();
  }

  @override
  void dispose() {
    _tempStatusTimer?.cancel();
    _statsRefreshTimer?.cancel();
    _infoCtrl.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadConfig();
    await _loadDeploymentState();
    await _updateBatteryLevel();
    await _ensureNotificationPermission();
    await _checkLocationServicesSilently();

    final prefs = await SharedPreferences.getInstance();
    final firstRun = !(prefs.getBool('onboarded') ?? false);
    if (firstRun) {
      await _firstRunPermissionFlow();
      await prefs.setBool('onboarded', true);
    }

    final last = prefs.getInt('lastStatus') ?? 1;
    final shouldTrack = await DeploymentState.shouldTrack(last);
    final canTrack = shouldTrack ? await _hasBackgroundPermission() : false;

    await _setBackgroundTracking(shouldTrack && canTrack);
    await _onPersistentStatus(last, notify: false);

    // Stats regelmäßig aktualisieren
    _statsRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshStats();
    });
    await _refreshStats();
  }

  Future<void> _loadDeploymentState() async {
    _deploymentMode = await DeploymentState.getMode();
    final status = await _getCurrentStatus();
    _trackingMode = await AdaptiveLocationSettings.determineMode(
      deployment: _deploymentMode,
      currentStatus: status,
    );
    setState(() {});
  }

  Future<int> _getCurrentStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('lastStatus') ?? 1;
  }

  Future<void> _updateBatteryLevel() async {
    try {
      final battery = Battery();
      _batteryLevel = await battery.batteryLevel;
      setState(() {});
    } catch (_) {}
  }

  Future<void> _refreshStats() async {
    final stats = await LocationSyncManager.instance.getStats();
    if (mounted) {
      setState(() => _stats = stats);
    }
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final sp = prefs.getString('protocol') ?? protocol;
    final sv = prefs.getString('server') ?? server;
    final tk = prefs.getString('token') ?? token;
    final tr = prefs.getString('trupp') ?? trupp;
    final lt = prefs.getString('leiter') ?? leiter;
    final iss = prefs.getString('issi') ?? issi;
    String host = sv;
    String prt = '';
    if (host.contains(':')) {
      final parts = host.split(':');
      host = parts[0];
      prt = parts.length > 1 ? parts[1] : '';
    }
    if (prt.isEmpty) prt = sp == 'https' ? '443' : '80';
    setState(() {
      protocol = sp;
      server = host;
      port = prt;
      token = tk;
      trupp = tr;
      leiter = lt;
      issi = iss;
    });
  }

  Future<void> _ensureNotificationPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        _showInfoDialog(
          title: 'Hinweis',
          msg: 'Benachrichtigungen sind deaktiviert. Ohne Benachrichtigung kann die Standortübertragung im Hintergrund beendet werden.',
        );
      }
    }
  }

  Future<void> _checkLocationServicesSilently() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _showInfoDialog(
        title: 'Standortdienste deaktiviert',
        msg: 'Bitte Standortdienste aktivieren, damit Position gesendet werden kann.',
      );
    }
  }

  Future<bool> _hasWhileInUsePermission() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  Future<bool> _hasBackgroundPermission() async {
    final p = await Geolocator.checkPermission();

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return p == LocationPermission.always;
    }
    final bg = await Permission.locationAlways.status;
    if (bg.isGranted) return true;
    return p == LocationPermission.always;
  }

  Future<void> _firstRunPermissionFlow() async {
    await _showPrePermissionInfo(
      title: 'Standortzugriff benötigt',
      msg: 'Der Standort wird zusammen mit jedem Status an den EDP-Server übertragen. '
          'Bitte erlaube „Beim Verwenden der App", damit Statusmeldungen korrekt gesendet werden.',
    );

    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }

    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      _showSnackbar('Standortberechtigung nicht erteilt.', success: false);
    }
  }

  Future<bool> _requestWhileInUseWithRationale() async {
    final proceed = await _showRationale(
      title: 'Standortzugriff erforderlich',
      msg: 'Der Standort wird zusammen mit jedem Status an den EDP-Server übertragen. '
          'Bitte erlaube mindestens „Beim Verwenden der App".',
    );

    if (!proceed) return false;

    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }

    if (p == LocationPermission.whileInUse || p == LocationPermission.always) {
      return true;
    }

    if (p == LocationPermission.deniedForever) {
      _showInfoDialog(
        title: 'Berechtigung verweigert',
        msg: 'Bitte in den Systemeinstellungen aktivieren.',
      );
    } else {
      _showSnackbar('Standortberechtigung nicht erteilt.', success: false);
    }
    return false;
  }

  Future<bool> _requestBackgroundWithRationale() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool(_kBgPromptShownKey) ?? false;
    if (!shown) {
      await prefs.setBool(_kBgPromptShownKey, true);

      final proceed = await _showRationale(
        title: 'Hintergrundortung',
        msg: 'Damit deine Position auch bei geschlossener App gesendet wird, '
            'benötigt die App „Immer"-Berechtigung.',
      );
      if (!proceed) return false;
    }

    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied || p == LocationPermission.whileInUse) {
      p = await Geolocator.requestPermission();
    }

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await Future.delayed(const Duration(milliseconds: 300));
      p = await Geolocator.checkPermission();

      if (p == LocationPermission.always) return true;

      if (p == LocationPermission.deniedForever) {
        _showInfoDialog(
          title: 'Berechtigung nötig',
          msg: 'Bitte in den Systemeinstellungen auf „Immer" setzen.',
        );
      } else if (p == LocationPermission.whileInUse) {
        _showInfoDialog(
          title: 'Hintergrund-Ortung',
          msg: 'Du hast "Beim Verwenden der App" ausgewählt. '
              'Für Hintergrund-Ortung bitte in den Einstellungen auf "Immer" ändern.',
        );
      }
      return false;
    } else {
      final bg = await Permission.locationAlways.request();
      if (bg.isGranted) return true;
      if (bg.isPermanentlyDenied) {
        _showInfoDialog(
          title: 'Berechtigung nötig',
          msg: 'Bitte in den Systemeinstellungen „Immer erlauben" auswählen.',
        );
      }
      return false;
    }
  }

  Future<void> _setBackgroundTracking(bool enabled) async {
    final svc = FlutterBackgroundService();

    if (enabled && !await svc.isRunning()) {
      await svc.startService();
    }

    if (await svc.isRunning()) {
      svc.invoke('setTracking', {'enabled': enabled});
    }

    setState(() => _bgTrackingActive = enabled);
  }

  Future<void> _onPersistentStatus(int st, {bool notify = true}) async {
    _lastPersistentStatus = st;
    selectedStatus = st;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastStatus', st);
    await DeploymentState.updateActivity();

    final svc = FlutterBackgroundService();
    if (await svc.isRunning()) {
      svc.invoke('statusChanged', {'status': st});
    }

    final shouldTrack = await DeploymentState.shouldTrack(st);
    if (shouldTrack && !await _hasBackgroundPermission()) {
      await _offerBackgroundPermission(st);
      return;
    }

    await _setBackgroundTracking(shouldTrack);

    if (notify) {
      try {
        await EdpApi.instance.sendStatus(st);

        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 5),
            ),
          );
          await LocationSyncManager.instance.sendOrQueue(
            lat: position.latitude,
            lon: position.longitude,
            accuracy: position.accuracy,
            status: st,
            timestamp: position.timestamp ?? DateTime.now(),
          );
        } catch (gpsError) {
          //print('GPS-Fehler bei Status-Änderung: $gpsError');
        }

        await LocationSyncManager.instance.flushPendingNow();
        _lastSent = DateTime.now();
        _showSnackbar('Status $st gesendet', success: true);
      } catch (_) {
        _showSnackbar('Status $st gespeichert (offline)', success: false);
      }
    }

    setState(() {});
  }

  Future<void> _onTempStatus(int st) async {
    selectedStatus = st;
    setState(() {});

    _tempStatusTimer?.cancel();
    _tempStatusTimer = Timer(_tempDurations[st]!, () async {
      if (_lastPersistentStatus != null && selectedStatus == st) {
        selectedStatus = _lastPersistentStatus;
        setState(() {});
      }
    });

    try {
      // Status senden
      await EdpApi.instance.sendStatus(st);

      // WICHTIG: Auch bei Temp-Status IMMER GPS senden
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );
        await LocationSyncManager.instance.sendOrQueue(
          lat: position.latitude,
          lon: position.longitude,
          accuracy: position.accuracy,
          status: st,
          timestamp: position.timestamp ?? DateTime.now(),
        );
      } catch (gpsError) {
        //print('GPS-Fehler bei Temp-Status: $gpsError');
      }

      // Automatische SDS bei Status 0 (DRINGEND) und Status 5 (Sprechwunsch)
      if (st == 0 || st == 5) {
        try {
          final sdsText = st == 0
              ? 'DRINGEND! $trupp benötigt sofortige Unterstützung!'
              : 'Sprechwunsch von $trupp - Bitte melden!';

          await EdpApi.instance.sendSdsText(sdsText);
          //print('Automatische SDS gesendet: $sdsText');
        } catch (sdsError) {
          //print('SDS-Fehler bei Status $st: $sdsError');
          // SDS-Fehler ist nicht kritisch, Status wurde trotzdem gesendet
        }
      }

      _lastSent = DateTime.now();
      _showSnackbar('Status $st gesendet', success: true);
    } catch (_) {
      _showSnackbar('Status $st gespeichert (offline)', success: false);
    }
  }

  Future<void> _onStatusPressed(int st) async {
    if (!await _hasWhileInUsePermission()) {
      final granted = await _requestWhileInUseWithRationale();
      if (!granted) {
        _showSnackbar('Standort nötig zum Senden', success: false);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (_isTempStatus(st)) {
      await _onTempStatus(st);
    } else {
      await _onPersistentStatus(st);
    }
  }

  Future<void> _offerBackgroundPermission(int st) async {
    final res = await showPlatformDialog<bool>(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: const Text('Hintergrundortung'),
        content: const Text(
          'Damit bei Status 1, 3 und 7 auch bei geschlossener App der Standort gesendet wird, '
              'benötigt die App die „Immer"-Berechtigung.\n\nJetzt anfragen?',
        ),
        actions: [
          PlatformDialogAction(
            child: const Text('Später'),
            onPressed: () => Navigator.pop(context, false),
          ),
          PlatformDialogAction(
            child: const Text('Erlauben'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (res == true) {
      final granted = await _requestBackgroundWithRationale();
      if (granted) {
        await _setBackgroundTracking(true);
        _showSnackbar('Hintergrundortung aktiv', success: true);
      } else {
        _showSnackbar('Status $st nur im Vordergrund', success: false);
      }
    } else {
      _showSnackbar('Status $st nur im Vordergrund', success: false);
    }

    try {
      await EdpApi.instance.sendStatus(st);
      await LocationSyncManager.instance.flushPendingNow();
      setState(() {});
    } catch (_) {}
  }

  Future<void> _toggleDeploymentMode() async {
    final newMode = _deploymentMode == DeploymentMode.deployed
        ? DeploymentMode.standby
        : DeploymentMode.deployed;

    await DeploymentState.setMode(newMode);
    _deploymentMode = newMode;

    final svc = FlutterBackgroundService();
    if (await svc.isRunning()) {
      svc.invoke('updateDeploymentMode', {'mode': newMode.name});
    }

    await _loadDeploymentState();
    _showSnackbar(
      newMode == DeploymentMode.deployed ? 'Einsatz gestartet' : 'Einsatz beendet',
      success: true,
    );
  }

  Future<void> _sendSds(String text) async {
    try {
      final res = await EdpApi.instance.sendSdsText(text);
      if (res.ok) {
        _showSnackbar('Nachricht gesendet', success: true);
      } else {
        _showSnackbar('Fehler: ${res.statusCode}', success: false);
      }
    } catch (e) {
      _showSnackbar('Fehler: $e', success: false);
    }
  }

  Future<void> _exportGpx() async {
    try {
      final path = await GpxExporter.exportAllFixesToGpx();
      await Share.shareXFiles([XFile(path)], text: 'GPX-Export');
    } catch (e) {
      _showSnackbar('Export fehlgeschlagen: $e', success: false);
    }
  }

  Future<void> _clearQueue() async {
    final confirm = await showPlatformDialog<bool>(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: const Text('Warteschlange löschen?'),
        content: const Text('Alle gespeicherten Positionen werden gelöscht.'),
        actions: [
          PlatformDialogAction(
            child: const Text('Abbrechen'),
            onPressed: () => Navigator.pop(context, false),
          ),
          PlatformDialogAction(
            child: const Text('Löschen'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await LocationQueue.instance.deleteAll();
      await _refreshStats();
      _showSnackbar('Warteschlange geleert', success: true);
    }
  }

  void _showSnackbar(String msg, {bool success = true}) {
    if (isMaterial(context)) {
      final color = success ? Colors.green : Colors.red;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: color,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      final overlay = Overlay.of(context);
      final overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: success ? CupertinoColors.systemGreen : CupertinoColors.systemRed,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    success ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.exclamationmark_triangle_fill,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      msg,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      overlay.insert(overlayEntry);
      Future.delayed(const Duration(seconds: 2), () {
        overlayEntry.remove();
      });
    }
  }

  void _showInfoDialog({required String title, required String msg}) {
    showPlatformDialog(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          PlatformDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showPrePermissionInfo({
    required String title,
    required String msg,
  }) async {
    await showPlatformDialog(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          PlatformDialogAction(
            child: const Text('Verstanden'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<bool> _showRationale({
    required String title,
    required String msg,
  }) async {
    final res = await showPlatformDialog<bool>(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          PlatformDialogAction(
            child: const Text('Abbrechen'),
            onPressed: () => Navigator.pop(context, false),
          ),
          PlatformDialogAction(
            child: const Text('Weiter'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  void _showMenu() {
    showPlatformModalSheet(
      context: context,
      builder: (_) => PlatformWidget(
        material: (_, _) => Container(
          padding: const EdgeInsets.all(20),
          child: _buildMenuContent(),
        ),
        cupertino: (_, _) => Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: CupertinoColors.systemBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: _buildMenuContent(),
        ),
      ),
    );
  }

  Widget _buildMenuContent() {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Menü',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade800,
            ),
          ),
          const SizedBox(height: 16),
          _buildMenuItem(
            icon: isMaterial(context) ? Icons.health_and_safety : CupertinoIcons.checkmark_shield,
            title: 'System-Check',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                platformPageRoute(
                  context: context,
                  builder: (_) => const SystemCheckScreen(),
                ),
              );
            },
          ),
          _buildMenuItem(
            icon: isMaterial(context) ? Icons.settings : CupertinoIcons.settings,
            title: 'Konfiguration',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                platformPageRoute(
                  context: context,
                  builder: (_) => const ConfigScreen(),
                ),
              );
            },
          ),
          _buildMenuItem(
            icon: isMaterial(context) ? Icons.download : CupertinoIcons.arrow_down_circle,
            title: 'GPX Export',
            onTap: () {
              Navigator.pop(context);
              _exportGpx();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, color: Colors.red.shade800, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            Icon(
              isMaterial(context) ? Icons.chevron_right : CupertinoIcons.chevron_right,
              color: Colors.grey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showQrCode() {
    final deeplink =
        'truppapp://config?protocol=$protocol&server=$server:$port&token=$token&issi=$issi&trupp=$trupp&leiter=$leiter';

    showPlatformModalSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isMaterial(context) ? Colors.white : CupertinoColors.systemBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Config QR-Code',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: QrImageView(
                  data: deeplink,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: PlatformElevatedButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: deeplink));
                    if (mounted) Navigator.pop(context);
                    _showSnackbar('Link kopiert', success: true);
                  },
                  child: const Text('Link kopieren'),
                  material: (_, _) => MaterialElevatedButtonData(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  cupertino: (_, _) => CupertinoElevatedButtonData(
                    color: Colors.red.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
  Widget build(BuildContext context) {
    return PlatformScaffold(
      backgroundColor: isMaterial(context) ? Colors.grey[100] : CupertinoColors.systemGroupedBackground,
      appBar: PlatformAppBar(
        title: const Text('Status'),
        material: (_, _) => MaterialAppBarData(
          backgroundColor: Colors.red.shade800,
          elevation: 0,
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code, size: 22),
              onPressed: _showQrCode,
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 22),
              onPressed: _showMenu,
            ),
          ],
        ),
        cupertino: (_, _) => CupertinoNavigationBarData(
          backgroundColor: Colors.red.shade800,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _showQrCode,
                child: const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(CupertinoIcons.qrcode, color: Colors.white, size: 22),
                ),
              ),
              GestureDetector(
                onTap: _showMenu,
                child: const Icon(CupertinoIcons.ellipsis, color: Colors.white, size: 22),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildCompactStatusBar(),
                      const SizedBox(height: 8),
                      _buildEssentialInfo(),
                      const SizedBox(height: 8),
                      _buildMessageSection(),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: isMaterial(context) ? Colors.white : CupertinoColors.systemBackground,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Keypad(
                  onPressed: _onStatusPressed,
                  selectedStatus: selectedStatus,
                  lastPersistentStatus: _lastPersistentStatus,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Kompakter Status-Bar (kombiniert Deployment + Tracking + Battery)
  Widget _buildCompactStatusBar() {
    final isDeployed = _deploymentMode == DeploymentMode.deployed;
    final baseColor = isDeployed ? Colors.green : Colors.blue;

    return GestureDetector(
      onTap: _toggleDeploymentMode,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: baseColor.shade700,
          border: Border(bottom: BorderSide(color: baseColor.shade900, width: 1)),
        ),
        child: Row(
          children: [
            // Deployment Status
            Icon(
              isDeployed ? Icons.emergency : Icons.home,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              isDeployed ? 'EINSATZ' : 'BEREIT',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.8,
              ),
            ),

            const Spacer(),

            // Tracking Indicator (nur wenn aktiv)
            if (_bgTrackingActive) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMaterial(context) ? Icons.gps_fixed : CupertinoIcons.location_fill,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'GPS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Battery
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getBatteryIcon(),
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$_batteryLevel%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getBatteryIcon() {
    if (_batteryLevel < 15) return Icons.battery_alert;
    if (_batteryLevel < 30) return Icons.battery_2_bar;
    if (_batteryLevel < 60) return Icons.battery_4_bar;
    return Icons.battery_full;
  }

  // Essentielle Info (nur Trupp, Leiter, aktueller Status, Queue kompakt)
  Widget _buildEssentialInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isMaterial(context) ? Colors.white : CupertinoColors.systemBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Trupp & Leiter kompakt
            Row(
              children: [
                Expanded(
                  child: _buildCompactInfo(
                    icon: isMaterial(context) ? Icons.group : CupertinoIcons.person_2_fill,
                    label: trupp,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCompactInfo(
                    icon: isMaterial(context) ? Icons.person : CupertinoIcons.person_fill,
                    label: leiter,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Aktueller Status + Queue in einer Zeile
            Row(
              children: [
                // Aktueller Status
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selectedStatus != null
                          ? Colors.red.shade800.withOpacity(0.1)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          selectedStatus != null ? 'Status $selectedStatus' : 'Kein Status',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: selectedStatus != null
                                ? Colors.red.shade800
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Queue kompakt
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _stats['pending']! > 0
                        ? Colors.orange.shade100
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isMaterial(context) ? Icons.storage : CupertinoIcons.tray_arrow_up,
                        size: 16,
                        color: _stats['pending']! > 0
                            ? Colors.orange.shade800
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_stats['pending']}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _stats['pending']! > 0
                              ? Colors.orange.shade800
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactInfo({required IconData icon, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.red.shade800),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Collapsible Nachrichtenfeld
  Widget _buildMessageSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          color: isMaterial(context) ? Colors.white : CupertinoColors.systemBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Header zum Ein-/Ausklappen
            InkWell(
              onTap: () => setState(() => _showMessageField = !_showMessageField),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      isMaterial(context) ? Icons.message : CupertinoIcons.chat_bubble_fill,
                      color: Colors.red.shade800,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Nachricht senden',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      _showMessageField
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            // Ausklappbares Nachrichtenfeld
            if (_showMessageField) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: PlatformTextFormField(
                        controller: _infoCtrl,
                        hintText: 'Nachricht eingeben...',
                        material: (_, _) => MaterialTextFormFieldData(
                          decoration: InputDecoration(
                            hintText: 'Nachricht eingeben...',
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                        ),
                        cupertino: (_, _) => CupertinoTextFormFieldData(
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemGrey6,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          placeholder: 'Nachricht eingeben...',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Material(
                      color: Colors.red.shade800,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () async {
                          final s = _infoCtrl.text.trim();
                          if (s.isEmpty) {
                            _showSnackbar('Bitte Text eingeben', success: false);
                            return;
                          }
                          await _sendSds(s);
                          _infoCtrl.clear();
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.send, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
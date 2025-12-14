// lib/screens/status_overview.dart
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
import 'ConfigScreen.dart';
import 'Keypad.dart';
import 'data/edp_api.dart';
import 'data/gpx_exporter.dart';
import 'data/location_queue.dart';
import 'data/location_sync_manager.dart';
import 'service.dart';

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
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

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
    _infoCtrl.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadConfig();
    await _ensureNotificationPermission();
    await _checkLocationServicesSilently();

    final prefs = await SharedPreferences.getInstance();
    final firstRun = !(prefs.getBool('onboarded') ?? false);
    if (firstRun) {
      await _firstRunPermissionFlow();
      await prefs.setBool('onboarded', true);
    }

    final last = prefs.getInt('lastStatus') ?? 1;
    final wantsTracking = [1, 3, 7].contains(last);
    final canTrack = wantsTracking ? await _hasBackgroundPermission() : false;

    await _setBackgroundTracking(wantsTracking && canTrack);
    await _onPersistentStatus(last, notify: false);
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

  // WICHTIG: Im iOS Simulator funktionieren Location-Permissions nicht zuverlässig!
  // Für echtes Testing bitte ein physisches iOS-Gerät verwenden.
  // Im Simulator:
  // - Features > Location > Apple (oder Custom Location setzen)
  // - Permissions können sich trotzdem merkwürdig verhalten
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
      // Auf iOS: Nach dem Request nochmal prüfen
      await Future.delayed(const Duration(milliseconds: 300));
      p = await Geolocator.checkPermission();

      if (p == LocationPermission.always) return true;

      if (p == LocationPermission.deniedForever) {
        _showInfoDialog(
          title: 'Berechtigung nötig',
          msg: 'Bitte in den Systemeinstellungen auf „Immer" setzen.',
        );
      } else if (p == LocationPermission.whileInUse) {
        // User hat "Beim Verwenden" gewählt - das ist OK für Vordergrund
        // Zeige Info, dass für Hintergrund "Immer" nötig ist
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
    final now = DateTime.now();
    if (notify && now.difference(_lastSent) < _sendInterval) return;

    _lastPersistentStatus = st;
    selectedStatus = st;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastStatus', st);

    final svc = FlutterBackgroundService();
    if (await svc.isRunning()) {
      svc.invoke('statusChanged', {'status': st});
    }

    final needsTracking = [1, 3, 7].contains(st);
    if (needsTracking && !await _hasBackgroundPermission()) {
      await _offerBackgroundPermission(st);
      return;
    }

    await _setBackgroundTracking(needsTracking);

    if (notify) {
      try {
        await EdpApi.instance.sendStatus(st);
        await LocationSyncManager.instance.flushPendingNow();
        _lastSent = now;
        _showSnackbar('Status $st gesendet', success: true);
      } catch (_) {
        _showSnackbar('Status $st gespeichert (offline)', success: false);
      }
    }

    setState(() {});
  }

  Future<void> _onTempStatus(int st) async {
    final now = DateTime.now();
    if (now.difference(_lastSent) < _sendInterval) return;

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
      await EdpApi.instance.sendStatus(st);
      _lastSent = now;
      _showSnackbar('Status $st gesendet', success: true);
    } catch (_) {
      _showSnackbar('Status $st gespeichert (offline)', success: false);
    }
  }

  Future<void> _onStatusPressed(int st) async {
    // Erst prüfen ob WhileInUse-Permission vorhanden ist
    if (!await _hasWhileInUsePermission()) {
      final granted = await _requestWhileInUseWithRationale();
      if (!granted) {
        _showSnackbar('Standort nötig zum Senden', success: false);
        return;
      }
      // Kurze Verzögerung nach Permission-Request, damit iOS Zeit hat die Permission zu verarbeiten
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
        // Permission wurde nicht erteilt - trotzdem Status senden aber ohne Hintergrund-Tracking
        _showSnackbar('Status $st nur im Vordergrund', success: false);
      }
    } else {
      // User hat "Später" gewählt - Status trotzdem ohne Hintergrund-Tracking senden
      _showSnackbar('Status $st nur im Vordergrund', success: false);
    }

    // Status trotzdem senden (auch ohne Background-Permission)
    try {
      await EdpApi.instance.sendStatus(st);
      await LocationSyncManager.instance.flushPendingNow();
      setState(() {});
    } catch (_) {
      // Wird bereits in _onPersistentStatus behandelt
    }
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
      _showSnackbar('Warteschlange geleert', success: true);
    }
  }

  void _showSnackbar(String msg, {bool success = true}) {
    if (isMaterial(context)) {
      // Material Design: SnackBar
      final color = success ? Colors.green : Colors.red;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: color,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // iOS: Overlay-basierte Toast-Nachricht
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

      // Auto-dismiss nach 2 Sekunden mit Animation
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
        material: (_, __) => Container(
          padding: const EdgeInsets.all(24),
          child: _buildMenuContent(),
        ),
        cupertino: (_, __) => Container(
          padding: const EdgeInsets.all(24),
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
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade800,
            ),
          ),
          const SizedBox(height: 20),
          _buildMenuItem(
            icon: isMaterial(context) ? Icons.settings : CupertinoIcons.settings,
            title: 'Konfiguration ändern',
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
            title: 'GPX exportieren',
            onTap: () {
              Navigator.pop(context);
              _exportGpx();
            },
          ),
          _buildMenuItem(
            icon: isMaterial(context) ? Icons.delete : CupertinoIcons.delete,
            title: 'Warteschlange löschen',
            onTap: () {
              Navigator.pop(context);
              _clearQueue();
            },
          ),
          if (Platform.isAndroid)
            _buildMenuItem(
              icon: Icons.battery_charging_full,
              title: 'Akkuoptimierung deaktivieren',
              onTap: () async {
                Navigator.pop(context);
                await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();
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
    return PlatformWidget(
      material: (_, __) => ListTile(
        leading: Icon(icon, color: Colors.red.shade800),
        title: Text(title),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      cupertino: (_, __) => CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        onPressed: onTap,
        child: Row(
          children: [
            Icon(icon, color: Colors.red.shade800),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  color: CupertinoColors.label,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQrCode() {
    final deeplink =
        'truppapp://config?protocol=$protocol&server=$server:$port&token=$token&issi=$issi&trupp=$trupp&leiter=$leiter';

    if (isMaterial(context)) {
      // Material: Dialog
      showPlatformDialog(
        context: context,
        builder: (_) => PlatformAlertDialog(
          title: const Text('Konfiguration teilen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Scanne diesen Code mit einem anderen Gerät:'),
              const SizedBox(height: 16),
              QrImageView(
                data: deeplink,
                size: 200,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 16),
              PlatformElevatedButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: deeplink));
                  if (mounted) Navigator.pop(context);
                  _showSnackbar('Link kopiert', success: true);
                },
                child: const Text('Link kopieren'),
                material: (_, __) => MaterialElevatedButtonData(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            PlatformDialogAction(
              child: const Text('Schließen'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } else {
      // iOS: Modal Sheet
      showPlatformModalSheet(
        context: context,
        builder: (_) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: CupertinoColors.systemBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag Handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Konfiguration teilen',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Scanne diesen Code mit einem anderen Gerät:',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: CupertinoColors.systemGrey4),
                  ),
                  child: QrImageView(
                    data: deeplink,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: Colors.red.shade800,
                    borderRadius: BorderRadius.circular(12),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: deeplink));
                      if (mounted) Navigator.pop(context);
                      _showSnackbar('Link kopiert', success: true);
                    },
                    child: const Text('Link kopieren'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    borderRadius: BorderRadius.circular(12),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Schließen'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      backgroundColor: isMaterial(context) ? Colors.grey[50] : CupertinoColors.systemGroupedBackground,
      appBar: PlatformAppBar(
        title: const Text('Status'),
        material: (_, __) => MaterialAppBarData(
          backgroundColor: Colors.red.shade800,
          elevation: 0,
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code),
              onPressed: _showQrCode,
              tooltip: 'QR-Code anzeigen',
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: _showMenu,
              tooltip: 'Menü',
            ),
          ],
        ),
        cupertino: (_, __) => CupertinoNavigationBarData(
          backgroundColor: Colors.red.shade800,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _showQrCode,
                child: const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(CupertinoIcons.qrcode, color: Colors.white),
                ),
              ),
              GestureDetector(
                onTap: _showMenu,
                child: const Icon(CupertinoIcons.ellipsis, color: Colors.white),
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
                      if (_bgTrackingActive)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          color: Colors.green.shade700,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isMaterial(context) ? Icons.location_on : CupertinoIcons.location_fill,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Hintergrundortung aktiv',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      _buildInfoCard(),
                      const SizedBox(height: 20),
                      _buildStatusIndicator(),
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
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Keypad(
                  onPressed: _onStatusPressed,
                  selectedStatus: selectedStatus,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: PlatformWidget(
        material: (_, __) => Card(
          elevation: 2,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: _buildInfoCardContent(),
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
          child: _buildInfoCardContent(),
        ),
      ),
    );
  }

  Widget _buildInfoCardContent() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildInfoRow(
            icon: isMaterial(context) ? Icons.group : CupertinoIcons.person_2_fill,
            label: 'Trupp',
            value: trupp,
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            icon: isMaterial(context) ? Icons.person : CupertinoIcons.person_fill,
            label: 'Ansprechpartner',
            value: leiter,
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                isMaterial(context) ? Icons.message : CupertinoIcons.chat_bubble_fill,
                color: Colors.red.shade800,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Nachricht senden',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PlatformTextFormField(
                  controller: _infoCtrl,
                  hintText: 'Freitext (z. B. Info an ELW)',
                  material: (_, __) => MaterialTextFormFieldData(
                    decoration: InputDecoration(
                      hintText: 'Freitext (z. B. Info an ELW)',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.red.shade800, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                  cupertino: (_, __) => CupertinoTextFormFieldData(
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey6,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: CupertinoColors.systemGrey4),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    placeholder: 'Freitext (z. B. Info an ELW)',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              PlatformWidget(
                material: (_, __) => Material(
                  color: Colors.red.shade800,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final s = _infoCtrl.text.trim();
                      if (s.isEmpty) {
                        _showSnackbar('Bitte eine Nachricht eingeben.', success: false);
                        return;
                      }
                      await _sendSds(s);
                      _infoCtrl.clear();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      child: const Icon(Icons.send, color: Colors.white, size: 24),
                    ),
                  ),
                ),
                cupertino: (_, __) => CupertinoButton(
                  padding: const EdgeInsets.all(14),
                  color: Colors.red.shade800,
                  borderRadius: BorderRadius.circular(12),
                  onPressed: () async {
                    final s = _infoCtrl.text.trim();
                    if (s.isEmpty) {
                      _showSnackbar('Bitte eine Nachricht eingeben.', success: false);
                      return;
                    }
                    await _sendSds(s);
                    _infoCtrl.clear();
                  },
                  child: const Icon(CupertinoIcons.paperplane_fill, color: Colors.white, size: 24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String label, required String value}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.red.shade800, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selectedStatus != null ? Colors.red.shade800 : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          selectedStatus != null ? 'Aktueller Status: $selectedStatus' : 'Kein Status gewählt',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: selectedStatus != null ? Colors.white : Colors.grey.shade700,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
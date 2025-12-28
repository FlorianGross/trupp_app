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
import 'iot_car_helper.dart';
import 'service.dart';

class StatusOverview extends StatefulWidget {
  const StatusOverview({super.key});

  @override
  State<StatusOverview> createState() => _StatusOverviewState();
}

class _StatusOverviewState extends State<StatusOverview> with TickerProviderStateMixin {
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
    IotCarHelper.initialize((status) {
      // Status wurde im Auto geändert
      _onPersistentStatus(status, notify: false);
    });
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
      title: 'Standortzugriff benötigt',
      msg: 'Der Standort wird zusammen mit jedem Status an den EDP-Server übertragen. '
          'Dazu benötigt die App Zugriff auf deinen Standort während der Nutzung.',
      primary: 'Fortfahren',
    );
    if (proceed != true) return false;

    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      _showSnackbar('Standortberechtigung nicht erteilt.', success: false);
      return false;
    }
    return true;
  }

  Future<bool> _requestBackgroundWithRationale() async {
    final proceed = await _showRationale(
      title: 'Hintergrund-Standort',
      msg: 'Bei Status 1, 3 oder 7 wird dein Standort zusätzlich regelmäßig im Hintergrund übertragen.',
      primary: 'Fortfahren',
    );
    if (proceed != true) return false;

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      final p = await Geolocator.requestPermission();
      if (p == LocationPermission.always) return true;
      _showSnackbar('Hintergrund-Standort nicht erteilt.', success: false);
      return false;
    } else {
      final bg = await Permission.locationAlways.request();
      if (bg.isGranted) return true;
      _showSnackbar('Hintergrund-Standort nicht erteilt.', success: false);
      return false;
    }
  }

  Future<void> _setBackgroundTracking(bool enabled) async {
    try {
      final service = FlutterBackgroundService();
      if (enabled) {
        if (!await service.isRunning()) {
          await service.startService();
        }
        service.invoke('setTracking', {'enabled': true});
      } else {
        service.invoke('setTracking', {'enabled': false});
      }
      setState(() => _bgTrackingActive = enabled);
    } catch (e) {
      // Background service error - ignore in non-main isolate
      print('Background service error (safe to ignore): $e');
      setState(() => _bgTrackingActive = enabled);
    }
  }

  Future<void> _onStatusPressed(int status) async {
    final needsWiu = !await _hasWhileInUsePermission();
    if (needsWiu) {
      final granted = await _requestWhileInUseWithRationale();
      if (!granted) return;
    }

    _tempStatusTimer?.cancel();
    if (_isTempStatus(status)) {
      await _sendStatus(status);
      setState(() {
        selectedStatus = status;
        _tempStatusTimer = Timer(_tempDurations[status]!, () async {
          final fallback = _lastPersistentStatus ?? 1;
          await _onPersistentStatus(fallback);
        });
      });
    } else {
      await _onPersistentStatus(status);
    }
  }

  Future<void> _onPersistentStatus(int status, {bool notify = true}) async {
    _tempStatusTimer?.cancel();
    _lastPersistentStatus = status;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastStatus', status);

    try {
      final service = FlutterBackgroundService();
      service.invoke('statusChanged', {'status': status});
    } catch (e) {
      print('Background service error (safe to ignore): $e');
    }

    final wantsTracking = [1, 3, 7].contains(status);
    if (wantsTracking && !await _hasBackgroundPermission()) {
      final granted = await _requestBackgroundWithRationale();
      if (!granted) {
        await _setBackgroundTracking(false);
        setState(() => selectedStatus = status);
        await _sendStatus(status);
        return;
      }
    }
    await _setBackgroundTracking(wantsTracking);
    setState(() => selectedStatus = status);
    await _sendStatus(status);
  }

  Future<void> _sendStatus(int status) async {
    final now = DateTime.now();
    if (now.difference(_lastSent) < _sendInterval) return;
    _lastSent = now;

    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      final api = EdpApi.instance;
      await api.sendStatus(status);
      await LocationSyncManager.instance.sendOrQueue(
        lat: pos.latitude,
        lon: pos.longitude,
        accuracy: pos.accuracy.isFinite ? pos.accuracy : null,
        status: status,
        timestamp: pos.timestamp ?? now,
      );

      await IotCarHelper.sendStatusToIot(status);
      _showSnackbar('Status $status gesendet');
    } catch (e) {
      _showSnackbar('Fehler beim Senden: $e', success: false);
    }
  }

  Future<void> _sendSds(String text) async {
    try {
      final api = EdpApi.instance;
      final res = await api.sendSdsText(text);
      if (res.ok) {
        _showSnackbar('Nachricht gesendet');
      } else {
        _showSnackbar('Fehler: ${res.statusCode}', success: false);
      }
    } catch (e) {
      _showSnackbar('Fehler: $e', success: false);
    }
  }

  void _showSnackbar(String msg, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green : Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 80,
          left: 16,
          right: 16,
        ),
      ),
    );
  }

  Future<void> _showInfoDialog({required String title, required String msg}) async {
    await showPlatformDialog(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: Text(title),
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

  Future<void> _showPrePermissionInfo({required String title, required String msg}) async {
    await showPlatformDialog(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          PlatformDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showRationale({
    required String title,
    required String msg,
    required String primary,
  }) async {
    return showPlatformDialog<bool>(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          PlatformDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          PlatformDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: Text(primary),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext ctx) async {
    final ok = await showPlatformDialog<bool>(
      context: ctx,
      builder: (_) => PlatformAlertDialog(
        title: const Text('Konfiguration löschen?'),
        content: const Text(
          'Alle Einstellungen und die Historie werden gelöscht. Dies kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          PlatformDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          PlatformDialogAction(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
            material: (_, __) => MaterialDialogActionData(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (ok == true) {
      await stopBackgroundServiceCompletely();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await LocationQueue.instance.destroyDb();

      if (ctx.mounted) {
        Navigator.of(ctx).pushAndRemoveUntil(
          platformPageRoute(context: ctx, builder: (_) => const ConfigScreen()),
              (_) => false,
        );
      }
    }
  }

  String _buildConfigDeepLink() {
    final qp = <String, String>{
      'protocol': protocol,
      'server': server,
      'port': port,
      'token': token,
      'issi': issi,
      'trupp': trupp,
      'leiter': leiter,
    };
    final uri = Uri(scheme: 'truppapp', host: 'config', queryParameters: qp);
    return uri.toString();
  }

  Future<void> _exportAndShareGpx() async {
    try {
      final path = await GpxExporter.exportAllFixesToGpx();
      await Share.shareXFiles([XFile(path)], text: 'Trupp App GPS-Export');
      _showSnackbar('GPX exportiert');
    } catch (e) {
      _showSnackbar('Export-Fehler: $e', success: false);
    }
  }

  Future<void> _clearQueue() async {
    final ok = await showPlatformDialog<bool>(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: const Text('Warteschlange löschen?'),
        content: const Text('Alle gespeicherten Standortdaten werden entfernt.'),
        actions: [
          PlatformDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          PlatformDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await LocationQueue.instance.deleteAll();
      _showSnackbar('Warteschlange geleert');
    }
  }

  Future<void> _flushQueue() async {
    try {
      final success = await LocationSyncManager.instance.flushPendingNow(batchSize: 300);
      if (success) {
        _showSnackbar('Warteschlange abgearbeitet');
      } else {
        _showSnackbar('Einige Einträge konnten nicht gesendet werden', success: false);
      }
    } catch (e) {
      _showSnackbar('Fehler: $e', success: false);
    }
  }

  Widget _buildSettingsDrawer(BuildContext context) {
    final content = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            const SizedBox(height: 12),
            Text(
              'Einstellungen',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade800,
              ),
            ),
            const SizedBox(height: 24),
            _buildInfoTile(
              icon: Icons.dns,
              label: 'Server',
              value: '$protocol://$server:$port',
            ),
            const Divider(height: 24),
            _buildInfoTile(
              icon: Icons.vpn_key,
              label: 'Token',
              value: token.isEmpty ? 'Nicht gesetzt' : token,
            ),
            const Divider(height: 24),
            _buildInfoTile(
              icon: Icons.badge,
              label: 'ISSI',
              value: issi,
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              color: _bgTrackingActive ? Colors.green.shade50 : Colors.grey.shade100,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _bgTrackingActive ? Icons.gps_fixed : Icons.gps_off,
                      color: _bgTrackingActive ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hintergrund-Tracking',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _bgTrackingActive ? 'Aktiv' : 'Inaktiv',
                            style: TextStyle(
                              color: _bgTrackingActive ? Colors.green : Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Bei Status 1, 3 oder 7 wird der Standort automatisch im Hintergrund übertragen.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Konfiguration teilen',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade800,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: QrImageView(
                data: _buildConfigDeepLink(),
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _buildConfigDeepLink()));
                      _showSnackbar('Link kopiert');
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Kopieren'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade800,
                      side: BorderSide(color: Colors.red.shade200),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Share.share(_buildConfigDeepLink()),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Teilen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            _buildActionButton(
              label: 'GPX Export',
              icon: Icons.file_download,
              onPressed: _exportAndShareGpx,
            ),
            const Spacer(),
            PlatformElevatedButton(
              child: const Text("Konfiguration zurücksetzen"),
              onPressed: () => _confirmLogout(context),
              cupertino: (_, _) => CupertinoElevatedButtonData(color: Colors.red.shade700),
              material: (_, __) => MaterialElevatedButtonData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (isCupertino(context))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: PlatformElevatedButton(
                  child: const Text("Schließen"),
                  onPressed: () => Navigator.of(context).pop(),
                  cupertino: (_, __) => CupertinoElevatedButtonData(
                    color: Colors.red.shade700,
                  ),
                  material: (_, __) => MaterialElevatedButtonData(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (isMaterial(context)) {
      return Drawer(backgroundColor: Colors.white, child: content);
    }
    return Material(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SingleChildScrollView(child: content),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.red.shade800, size: 22),
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
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: Colors.red.shade800,
        side: BorderSide(color: Colors.red.shade200),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      backgroundColor: Colors.grey[100],
      appBar: PlatformAppBar(
        title: const Text("Statusübersicht"),
        material: (_, __) => MaterialAppBarData(
          backgroundColor: Colors.red.shade800,
          centerTitle: true,
          elevation: 0,
          actions: [
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          ],
        ),
        cupertino: (_, __) => CupertinoNavigationBarData(
          backgroundColor: Colors.red.shade800,
          trailing: GestureDetector(
            child: const Icon(CupertinoIcons.bars, color: Colors.white),
            onTap: () => showPlatformModalSheet(
              context: context,
              builder: (_) => _buildSettingsDrawer(context),
            ),
          ),
        ),
      ),
      material: (_, __) => MaterialScaffoldData(endDrawer: _buildSettingsDrawer(context)),
      body: SafeArea(
        bottom: true,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Column(
                    children: [
                      Card(
                        elevation: 2,
                        shadowColor: Colors.black26,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.group, color: Colors.red.shade800, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Trupp',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          trupp,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.person, color: Colors.red.shade800, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Ansprechpartner',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          leiter,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              const Divider(),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Icon(Icons.message, color: Colors.red.shade800, size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Nachricht senden',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _infoCtrl,
                                      decoration: InputDecoration(
                                        hintText: 'Freitext (z. B. Info an Leitstelle)',
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
                                  ),
                                  const SizedBox(width: 12),
                                  Material(
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
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: selectedStatus != null ? Colors.red.shade800 : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          selectedStatus != null
                              ? 'Aktueller Status: $selectedStatus'
                              : 'Kein Status gewählt',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: selectedStatus != null ? Colors.white : Colors.grey.shade700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
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
}
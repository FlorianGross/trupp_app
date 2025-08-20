// lib/screens/status_overview.dart
import 'dart:async';
import 'dart:io';
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
import 'package:http/http.dart' as http;
import 'ConfigScreen.dart';
import 'Keypad.dart';
import 'service.dart';

class StatusOverview extends StatefulWidget {
  const StatusOverview({super.key});

  @override
  State<StatusOverview> createState() => _StatusOverviewState();
}

class _StatusOverviewState extends State<StatusOverview> {
  // Config
  String protocol = 'https',
      server = 'localhost',
      port = '443',
      token = '';
  String trupp = 'Unbekannt',
      leiter = 'Unbekannt',
      issi = '0000';

  // UI/Status
  int? selectedStatus;
  int? _lastPersistentStatus;
  Timer? _tempStatusTimer;

  // Kurzstatus 0/9/5 → nach 5s zurück
  bool _isTempStatus(int s) => s == 0 || s == 9 || s == 5;
  static const Map<int, Duration> _tempDurations = {
    0: Duration(seconds: 5),
    9: Duration(seconds: 5),
    5: Duration(seconds: 5),
  };

  // Location (nur für Sofort-Positions-Sendungen u. Glättung im UI)
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _sendInterval = Duration(seconds: 2);


  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _tempStatusTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _ensureLocationReady();
    await _loadConfig();
    await _ensureNotificationPermission();
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('lastStatus') ?? 1;
    await _setBackgroundTracking([1,3,7].contains(last));
    await _onPersistentStatus(last);
  }

  Future<void> _ensureNotificationPermission() async {
    if (Platform.isAndroid) {
      // Android 13+ braucht explizit Notification-Permission
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        _showErrorDialog('Benachrichtigungen sind deaktiviert. '
            'Ohne Benachrichtigung kann die Standortübertragung im Hintergrund beendet werden.');
      }
    }
  }

  Future<void> _ensureLocationReady() async {
    final ok = await Geolocator.isLocationServiceEnabled();
    if (!ok) {
      _showErrorDialog("Standortdienste sind deaktiviert. Bitte aktivieren.");
      return;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }

    // iOS: "Always" ist für echtes Background-Tracking empfehlenswert
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) &&
        p != LocationPermission.always) {
      // Freundlicher Hinweis + Sprung in Einstellungen
      _showErrorDialog("Bitte 'Standortzugriff: Immer' in den iOS-Einstellungen erlauben, "
          "damit die Übertragung im Hintergrund zuverlässig läuft.");
      // Optional: Geolocator.openAppSettings();
    }

    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      _showErrorDialog("Standortberechtigung fehlt.");
    }
  }

  void _showErrorDialog(String msg) {
    showPlatformDialog(
      context: context, builder: (_) =>
        PlatformAlertDialog(
          title: const Text('Fehler'),
          content: Text(msg),
          actions: [ PlatformDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),),
          ],),);
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final sp = prefs.getString('protocol') ?? protocol;
    final sv = prefs.getString('server') ?? server;
    final tk = prefs.getString('token') ?? token;
    final tr = prefs.getString('trupp') ?? trupp;
    final lt = prefs.getString('leiter') ?? leiter;
    final iss = prefs.getString('issi') ?? issi;

    String host = sv; String prt = '';
    if (host.contains(':')) {
    final parts = host.split(':'); host = parts[0]; prt = parts.length > 1 ? parts[1] : '';
    }
    if (prt.isEmpty) prt = sp == 'https' ? '443' : '80';

    setState(() {
    protocol = sp; server = host; port = prt; token = tk;
    trupp = tr; leiter = lt; issi = iss;
    });
  }

  // ---------------- Networking Helpers ----------------
  Uri _buildUri(String path, Map<String, String> params) {
    final parsedPort = int.tryParse(port) ?? (protocol == 'https' ? 443 : 80);
    return Uri(
      scheme: protocol,
      host: server,
      port: parsedPort,
      pathSegments: [if (token.isNotEmpty) token, path],
      queryParameters: params,
    );
  }

  Future<void> _sendStatus(int status, {bool notify = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastStatus', status);

    final service = FlutterBackgroundService();
    service.invoke('statusChanged', {'status': status});

    final url = _buildUri("setstatus", {'issi': issi, 'status': '$status'});
    try {
      final r = await http.get(url);
      if (!mounted) return;
      if (r.statusCode == 200) {
        setState(() => selectedStatus = status);
        if (notify) {
          _showSnackbar(
            "Status $status erfolgreich gesendet ✅", success: true);
        }
      } else if (notify) {
        _showSnackbar(
            "Fehler beim Senden von Status $status ❌ (Code: ${r.statusCode})",
            success: false);
      }
    } catch (e) {
      if (notify) {
        _showSnackbar(
          "Fehler beim Senden von Status $status ❌", success: false);
      }
    }
  }

  Future<void> _sendLocationLatLon(double lat, double lon) async {
    try {
      final url = _buildUri("gpsposition", {
        'issi': issi,
        'lat': lat.toString().replaceAll('.', ','),
        'lon': lon.toString().replaceAll('.', ','),
      });
      await http.get(url);
    } catch (_) {}
  }

  // --------------- Background Service Control ---------------
  Future<void> _setBackgroundTracking(bool enabled) async {
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (enabled) {
      if (!running) await service.startService();
      service.invoke('setTracking', {'enabled': true});
    } else {
      if (running) service.invoke('setTracking', {'enabled': false});
    }
  }

  // --------------- Status Handling (inkl. Kurzstatus) ---------------
  void _onStatusPressed(int status) async {
    if (_isTempStatus(status)) {
      _tempStatusTimer?.cancel();
      await _sendStatus(status);
      _sendCurrentPositionOnce();

      final duration = _tempDurations[status] ?? const Duration(seconds: 5);
      _tempStatusTimer = Timer(duration, () {
        if (!mounted) return;
        final revert = _lastPersistentStatus ?? 1;
        _onStatusPressed(revert);
      });
      return;
    }

    if (selectedStatus == status && [1, 3, 7].contains(status)) {
      return;
    }

    _lastPersistentStatus = status;
    await _sendStatus(status);

    final wantsTracking = [1, 3, 7].contains(status);
    await _setBackgroundTracking(wantsTracking);

    if (!wantsTracking) {
      _sendCurrentPositionOnce();
    }
  }

  Future<void> _onPersistentStatus(int status, {bool notify = true}) async {
    _tempStatusTimer?.cancel();
    _tempStatusTimer = null;
    _lastPersistentStatus = status;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastStatus', status);

    _sendStatus(status, notify: notify);
    _setBackgroundTracking([1, 3, 7].contains(status));
    if (![1, 3, 7].contains(status)) _sendCurrentPositionOnce();
  }

  Future<void> _sendCurrentPositionOnce() async {

    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 5),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 100,
        pauseLocationUpdatesAutomatically: true,
        // Only set to true if our app will be started up in the background.
        showBackgroundLocationIndicator: false,
      );
    } else if (kIsWeb) {
      locationSettings = WebSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
        maximumAge: Duration(minutes: 5),
      );
    } else {
      locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
      );
    }

    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
      final now = DateTime.now();
      if (now.difference(_lastSent) >= _sendInterval) {
        _lastSent = now;
        _sendLocationLatLon(p.latitude, p.longitude);
      }
    } catch (_) {}
  }

  // ---------------- UI Helpers ----------------
  void _showSnackbar(String message, {required bool success}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
      return;
    }
    showCupertinoDialog(
      context: context,
      builder: (_) =>
          CupertinoAlertDialog(
            title: Text(success ? 'Erfolg' : 'Fehler'),
            content: Padding(
                padding: const EdgeInsets.only(top: 8), child: Text(message)),
          ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    });
  }

  void _confirmLogout(BuildContext context) {
    showPlatformDialog(
      context: context,
      builder: (_) =>
          PlatformAlertDialog(
            title: const Text("Konfiguration zurücksetzen?"),
            content: const Text("Alle gespeicherten Daten werden gelöscht."),
            actions: [
              PlatformDialogAction(child: const Text("Abbrechen"),
                  onPressed: () => Navigator.of(context).pop()),
              PlatformDialogAction(
                child: const Text("Zurücksetzen"),
                cupertino: (_, __) =>
                    CupertinoDialogActionData(isDestructiveAction: true),
                material: (_, __) => MaterialDialogActionData(),
                onPressed: () async {
                  await stopBackgroundServiceCompletely();
                  await _sendStatus(6, notify: false);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  if (!mounted) return;
                  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                    platformPageRoute(
                        context: context, builder: (_) => const ConfigScreen()),
                        (_) => false,
                  );
                },
              ),
            ],
          ),
    );
  }

  Widget _configRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  String _buildConfigDeepLink() {
    // Custom Scheme: truppapp://config?protocol=...&server=...&port=...&token=...&issi=...&trupp=...&leiter=...
    final qp = <String, String>{
      'protocol': protocol,
      'server'  : server,
      'port'    : port,
      'token'   : token,
      'leiter'  : leiter,
    };

    final uri = Uri(
      scheme: 'truppapp',
      host: 'config',
      queryParameters: qp,
    );
    return uri.toString();
  }


  Widget _buildSettingsDrawer(BuildContext context) {
    final fullServer = '$protocol://$server:$port';
    final deepLink = _buildConfigDeepLink();

    final content = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Aktuelle Konfiguration",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Divider(height: 20),
          _configRow("Server", fullServer),
          _configRow("Token", token),
          _configRow("ISSI", issi),
          _configRow("Trupp", trupp),
          _configRow("Ansprechpartner", leiter),

          const SizedBox(height: 24),
          const Text("Konfiguration teilen",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),

          const SizedBox(height: 12),
          // QR-Code
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: deepLink,
              version: QrVersions.auto,
              size: 220,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PlatformElevatedButton(
                color: Colors.red,
                child: const Text("Link kopieren", style: TextStyle(color: Colors.white),),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: deepLink));
                  _showSnackbar("Link kopiert", success: true);
                },
              ),
              const SizedBox(width: 12),
              PlatformElevatedButton(
                color: Colors.red,
                child: const Text("Teilen", style: TextStyle(color: Colors.white),),
                onPressed: () => Share.share(deepLink),
              ),
            ],
          ),

          const SizedBox(height: 24),
          PlatformElevatedButton(
            child: const Text("Konfiguration zurücksetzen"),
            onPressed: () => _confirmLogout(context),
            cupertino: (_, __) => CupertinoElevatedButtonData(color: Colors.red.shade700),
            material:  (_, __) => MaterialElevatedButtonData(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.logout),
            ),
          ),
          if (isCupertino(context))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: PlatformElevatedButton(
                child: const Text("Schließen"),
                onPressed: () => Navigator.of(context).pop(),
                cupertino: (_, __) => CupertinoElevatedButtonData(),
              ),
            ),
        ]),
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

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      backgroundColor: Colors.grey[100],
      appBar: PlatformAppBar(
        title: const Text("Statusübersicht"),
        material: (_, __) =>
            MaterialAppBarData(
              backgroundColor: Colors.red.shade800, centerTitle: true,
              actions: [
                Builder(builder: (context) =>
                    IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                    ))
              ],
            ),
        cupertino: (_, __) =>
            CupertinoNavigationBarData(
              backgroundColor: Colors.red.shade800,
              trailing: GestureDetector(
                child: const Icon(CupertinoIcons.bars),
                onTap: () =>
                    showPlatformModalSheet(context: context,
                        builder: (_) => _buildSettingsDrawer(context)),
              ),
            ),
      ),
      material: (_, __) =>
          MaterialScaffoldData(endDrawer: _buildSettingsDrawer(context)),
      body: Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.group, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text('Trupp: $trupp', style: const TextStyle(
                            fontSize: 18))),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.person, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                        'Ansprechpartner: $leiter', style: const TextStyle(
                        fontSize: 18))),
                  ]),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            selectedStatus != null
                ? 'Aktueller Status: $selectedStatus'
                : 'Kein Status gewählt',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          const Spacer(),
          Align(
            alignment: Alignment.bottomCenter,
            child: Keypad(
                onPressed: _onStatusPressed, selectedStatus: selectedStatus),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

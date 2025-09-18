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

class _StatusOverviewState extends State<StatusOverview> {
  // Config
  String protocol = 'https', server = 'localhost', port = '443', token = '';
  String trupp = 'Unbekannt', leiter = 'Unbekannt', issi = '0000';

  // UI/Status
  int? selectedStatus;
  int? _lastPersistentStatus;
  Timer? _tempStatusTimer;

  bool get _trackingDesired =>
      [1, 3, 7].contains(_lastPersistentStatus ?? selectedStatus ?? -1);

  // Hintergrund-Tracking-Indikator (nur für UI im Config-Drawer)
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
    await _loadConfig();
    await _ensureNotificationPermission();

    // Beim Starten nur prüfen, ob Services/Berechtigungen vorhanden sind;
    // kein Prompt außer beim allerersten Start (onboarding).
    await _checkLocationServicesSilently();

    final prefs = await SharedPreferences.getInstance();
    final firstRun = !(prefs.getBool('onboarded') ?? false);
    if (firstRun) {
      // Einmalige, freundliche Vorab-Erklärung + While-In-Use anfragen.
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
          msg:
              'Benachrichtigungen sind deaktiviert. Ohne Benachrichtigung kann die Standortübertragung im Hintergrund beendet werden.',
        );
      }
    }
  }

  Future<void> _checkLocationServicesSilently() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _showInfoDialog(
        title: 'Standortdienste deaktiviert',
        msg:
            'Bitte Standortdienste aktivieren, damit Position gesendet werden kann.',
      );
    }
  }

  // -------------------- Permissions (kontextuell) --------------------

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
    // Android: permission_handler kapselt Background; zusätzlich explizit prüfen
    final bg = await Permission.locationAlways.status;
    if (bg.isGranted) return true;
    return p == LocationPermission.always;
  }

  Future<void> _firstRunPermissionFlow() async {
    await _showPrePermissionInfo(
      title: 'Standortzugriff benötigt',
      msg:
          'Der Standort wird zusammen mit jedem Status an den EDP-Server übertragen. '
          'Bitte erlaube „Beim Verwenden der App“, damit Statusmeldungen korrekt gesendet werden.',
    );

    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission(); // shows OS sheet
    }

    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      _showSnackbar('Standortberechtigung nicht erteilt.', success: false);
    }
  }

  Future<bool> _requestWhileInUseWithRationale() async {
    final proceed = await _showRationale(
      title: 'Standortzugriff benötigt',
      msg:
          'Der Standort wird zusammen mit jedem Status an den EDP-Server übertragen. '
          'Dazu benötigt die App Zugriff auf deinen Standort während der Nutzung.',
      primary: 'Fortfahren',
    );
    if (proceed != true) return false;

    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      _showSnackbar('Standortberechtigung nicht erteilt.', success: false);
      return false;
    }
    return true;
  }

  Future<bool> _requestBackgroundWithRationale() async {
    final proceed = await _showRationale(
      title: 'Hintergrund-Standort',
      msg:
          'Bei Status 1, 3 oder 7 wird dein Standort zusätzlich regelmäßig im Hintergrund übertragen.',
      primary: 'Fortfahren',
    );
    if (proceed != true) return false;

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p != LocationPermission.always) {
        // Kein Auto-Redirect – nur optional anbieten
        final open = await _offerSettings(
          msg:
              'Bitte in den iOS-Einstellungen „Standortzugriff: Immer“ erlauben, um die Hintergrundübertragung zu aktivieren.',
        );
        if (open == true) {
          await Geolocator.openAppSettings();
        }
        return false;
      }
      return true;
    } else {
      final whenInUse = await Permission.location.request();
      if (!whenInUse.isGranted) {
        _showSnackbar('Standortberechtigung nicht erteilt.', success: false);
        return false;
      }
      final bg = await Permission.locationAlways.request();
      if (!bg.isGranted) {
        final open = await _offerSettings(
          msg:
              'Bitte in den Android-Einstellungen „Standort im Hintergrund“ erlauben, um die Hintergrundübertragung zu aktivieren.',
        );
        if (open == true) {
          await openAppSettings();
        }
        return false;
      }
      return true;
    }
  }

  // -------------------- Networking & Location --------------------

  Future<void> _sendCurrentPositionOnce() async {
    // Für JEDE Statusmeldung: einmalige Positionssendung (wenn erlaubt)
    if (_bgTrackingActive) return;
    if (!await _hasWhileInUsePermission()) return;

    late LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 5),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 100,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: false,
      );
    } else if (kIsWeb) {
      locationSettings = WebSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
        maximumAge: Duration(minutes: 5),
      );
    } else {
      locationSettings = const LocationSettings(
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
        // **Nur gute Fixe** in Queue/Send (nutzt denselben Filter im Service implizit)
        await LocationSyncManager.instance.sendOrQueue(
          lat: p.latitude,
          lon: p.longitude,
          accuracy: p.accuracy.isFinite ? p.accuracy : null,
          status: _lastPersistentStatus ?? selectedStatus,
          timestamp: now,
        );
      }
    } catch (_) {}
  }

  Future<void> _sendStatus(int status, {bool notify = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastStatus', status);

    final service = FlutterBackgroundService();
    service.invoke('statusChanged', {'status': status});

    try {
      final api =
          EdpApi.instance; // setzt voraus, dass init im main() passiert ist
      final r = await api.sendStatus(status);
      if (!mounted) return;
      if (r.ok) {
        setState(() => selectedStatus = status);
        if (notify)
          _showSnackbar("Status $status erfolgreich gesendet ✅", success: true);
      } else if (notify) {
        _showSnackbar(
          "Fehler beim Senden von Status $status ❌ (Code: ${r.statusCode})",
          success: false,
        );
      }
    } catch (_) {
      if (notify) {
        _showSnackbar(
          "Fehler beim Senden von Status $status ❌",
          success: false,
        );
      }
    }
    if (!_bgTrackingActive) {
      await _sendCurrentPositionOnce(); // bleibt wie gehabt
    }
  }

  // ---------------- Background Service Control ----------------
  Future<void> _setBackgroundTracking(bool enabled) async {
    final service = FlutterBackgroundService();
    final running = await service.isRunning();

    // Nur auf Flanken reagieren
    if (enabled) {
      if (!running) await service.startService();
      service.invoke('setTracking', {'enabled': true});
    } else {
      if (running) service.invoke('setTracking', {'enabled': false});
    }

    if (mounted) setState(() => _bgTrackingActive = enabled);
  }

  // ---------------- Status Handling ----------------
  void _onStatusPressed(int status) async {
    if (_isTempStatus(status)) {
      _tempStatusTimer?.cancel();
      await _sendStatus(status);

      final duration = _tempDurations[status] ?? const Duration(seconds: 5);
      _tempStatusTimer = Timer(duration, () {
        if (!mounted) return;
        final revert = _lastPersistentStatus ?? 1;
        _onStatusPressed(revert);
      });
      return;
    }

    final wasPersistent = _lastPersistentStatus;
    final wantsTracking = [1, 3, 7].contains(status);

    final samePersistent = (wasPersistent != null && wasPersistent == status);

    if (wantsTracking && !samePersistent && !_bgTrackingActive) {
      // Ensure When-In-Use first
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        // No pre-prompt with cancel – just request
        p = await Geolocator.requestPermission();
      }

      // Ask for Background directly when required (no custom cancel UI beforehand)
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        if (p != LocationPermission.always) {
          // iOS needs a second request step initiated by the app
          p = await Geolocator.requestPermission(); // iOS may escalate to "Immer"
        }
        if (p != LocationPermission.always) {
          // Now it’s allowed to inform and link to Settings
          final open = await _offerSettings(
            msg:
                'Für Status 1, 3 oder 7 bitte in den iOS-Einstellungen '
                '„Standortzugriff: Immer“ aktivieren, um die Hintergrundübertragung zu ermöglichen.',
          );
          if (open == true) await Geolocator.openAppSettings();
        }
      } else {
        // Android
        final whenInUse = await Permission.location.request();
        if (whenInUse.isGranted) {
          final bg = await Permission.locationAlways.request();
          if (!bg.isGranted) {
            final open = await _offerSettings(
              msg:
                  'Bitte in den Android-Einstellungen „Standort im Hintergrund“ erlauben, '
                  'um die Hintergrundübertragung zu aktivieren.',
            );
            if (open == true) await openAppSettings();
          }
        }

        // Check for Battery Optimization
        bool? isBatteryOptimizationDisabled =
            await DisableBatteryOptimization.isBatteryOptimizationDisabled;
        if (isBatteryOptimizationDisabled == false) {
          // Ask to disable battery optimization
          await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();
        }
      }
    }

    _lastPersistentStatus = status;
    await _sendStatus(status);

    if (!samePersistent) {
      final canTrack = wantsTracking ? await _hasBackgroundPermission() : false;
      await _setBackgroundTracking(wantsTracking && canTrack);
    }
  }

  Future<void> _onPersistentStatus(int status, {bool notify = true}) async {
    _tempStatusTimer?.cancel();
    _tempStatusTimer = null;
    _lastPersistentStatus = status;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastStatus', status);

    final wantsTracking = [1, 3, 7].contains(status);
    final canTrack = wantsTracking ? await _hasBackgroundPermission() : false;

    await _sendStatus(status, notify: notify);
    await _setBackgroundTracking(wantsTracking && canTrack);
  }

  // ---------------- Dialog/Helper ----------------

  Future<bool?> _showRationale({
    required String title,
    required String msg,
    String primary = 'OK',
    String secondary = 'Abbrechen',
  }) async {
    return showPlatformDialog<bool>(
      context: context,
      builder:
          (_) => PlatformAlertDialog(
            title: Text(title),
            content: Text(msg),
            actions: [
              PlatformDialogAction(
                child: Text(secondary),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              PlatformDialogAction(
                child: Text(primary),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
    );
  }

  Future<void> _showPrePermissionInfo({
    required String title,
    required String msg,
    String actionLabel = 'Fortfahren',
  }) async {
    await showPlatformDialog<void>(
      context: context,
      builder:
          (_) => PlatformAlertDialog(
            title: Text(title),
            content: Text(msg),
            actions: [
              PlatformDialogAction(
                child: Text(actionLabel),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
    );
  }

  Future<bool?> _offerSettings({required String msg}) {
    return showPlatformDialog<bool>(
      context: context,
      builder:
          (_) => PlatformAlertDialog(
            title: const Text('Berechtigung erforderlich'),
            content: Text(msg),
            actions: [
              PlatformDialogAction(
                child: const Text('Abbrechen'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              PlatformDialogAction(
                child: const Text('Zu den Einstellungen'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
    );
  }

  void _showInfoDialog({required String title, required String msg}) {
    showPlatformDialog(
      context: context,
      builder:
          (_) => PlatformAlertDialog(
            title: Text(title),
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

  void _showSnackbar(String message, {required bool success}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      return;
    }
    showCupertinoDialog(
      context: context,
      builder:
          (_) => CupertinoAlertDialog(
            title: Text(success ? 'Erfolg' : 'Fehler'),
            content: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(message),
            ),
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
      builder:
          (_) => PlatformAlertDialog(
            title: const Text("Konfiguration zurücksetzen?"),
            content: const Text("Alle gespeicherten Daten werden gelöscht."),
            actions: [
              PlatformDialogAction(
                child: const Text("Abbrechen"),
                onPressed: () => Navigator.of(context).pop(),
              ),
              PlatformDialogAction(
                child: const Text("Zurücksetzen"),
                cupertino:
                    (_, __) =>
                        CupertinoDialogActionData(isDestructiveAction: true),
                material: (_, __) => MaterialDialogActionData(),
                onPressed: () async {
                  await stopBackgroundServiceCompletely();

                  // optional: Status 6 melden ohne UI
                  await _sendStatus(6, notify: false);

                  // 1) Queue-Datenbank löschen
                  try {
                    await LocationQueue.instance.destroyDb();
                  } catch (_) {}

                  // 2) SharedPreferences leeren
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();

                  if (!mounted) return;
                  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                    platformPageRoute(
                      context: context,
                      builder: (_) => const ConfigScreen(),
                    ),
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
    final qp = <String, String>{
      'protocol': protocol,
      'server': server,
      'port': port,
      'token': token,
      'leiter': leiter,
    };

    final uri = Uri(scheme: 'truppapp', host: 'config', queryParameters: qp);
    return uri.toString();
  }

  Widget _buildSettingsDrawer(BuildContext context) {
    final fullServer = '$protocol://$server:$port';
    final deepLink = _buildConfigDeepLink();

    final content = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Aktuelle Konfiguration",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 20),
            // Sichtbare, reviewer-freundliche Info NUR hier:
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Standortübertragung",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "• Der Standort wird bei JEDEM Status zusammen mit der Meldung übertragen.",
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    "• Bei Status 1, 3 oder 7 wird der Standort zusätzlich regelmäßig im Hintergrund gesendet (sofern erlaubt).",
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        "Hintergrund-Standort: ",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Chip(
                        label: Text(_bgTrackingActive ? 'Aktiv' : 'Inaktiv'),
                        backgroundColor:
                            _bgTrackingActive
                                ? Colors.green.shade100
                                : Colors.grey.shade200,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 20),

            const SizedBox(height: 24),
            const Text(
              "Konfiguration teilen",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
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
                  child: const Text(
                    "Link kopieren",
                    style: TextStyle(color: Colors.white),
                  ),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: deepLink));
                    _showSnackbar("Link kopiert", success: true);
                  },
                ),
                const SizedBox(width: 12),
                PlatformElevatedButton(
                  color: Colors.red,
                  child: const Text(
                    "Teilen",
                    style: TextStyle(color: Colors.white),
                  ),
                  onPressed: () => Share.share(deepLink),
                ),
              ],
            ),
            const Divider(height: 20),
            const Text(
              "Datenexport",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            PlatformElevatedButton(
              child: const Text("GPX exportieren"),
              onPressed: () async {
                try {
                  final path = await GpxExporter.exportAllFixesToGpx();
                  SharePlus.instance.share(
                    ShareParams(
                      files: [XFile(path)],
                      text: "GPX-Datei mit Standortpunkten",
                    ),
                  );
                } catch (e) {
                  _showSnackbar("Export fehlgeschlagen: $e", success: false);
                }
              },
              material:
                  (_, __) => MaterialElevatedButtonData(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade800,
                      foregroundColor: Colors.white,
                    ),
                  ),
              cupertino:
                  (_, __) =>
                      CupertinoElevatedButtonData(color: Colors.red.shade800),
            ),
            const SizedBox(height: 12),
            const Divider(height: 20),
            PlatformElevatedButton(
              child: const Text("Konfiguration zurücksetzen"),
              onPressed: () => _confirmLogout(context),
              cupertino:
                  (_, _) =>
                      CupertinoElevatedButtonData(color: Colors.red.shade700),
              material:
                  (_, __) => MaterialElevatedButtonData(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    ),
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

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      backgroundColor: Colors.grey[100],
      appBar: PlatformAppBar(
        title: const Text("Statusübersicht"),
        material:
            (_, __) => MaterialAppBarData(
              backgroundColor: Colors.red.shade800,
              centerTitle: true,
              actions: [
                Builder(
                  builder:
                      (context) => IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () => Scaffold.of(context).openEndDrawer(),
                      ),
                ),
              ],
            ),
        cupertino:
            (_, __) => CupertinoNavigationBarData(
              backgroundColor: Colors.red.shade800,
              trailing: GestureDetector(
                child: const Icon(CupertinoIcons.bars),
                onTap:
                    () => showPlatformModalSheet(
                      context: context,
                      builder: (_) => _buildSettingsDrawer(context),
                    ),
              ),
            ),
      ),
      material:
          (_, __) =>
              MaterialScaffoldData(endDrawer: _buildSettingsDrawer(context)),
      body: Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.group, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Trupp: $trupp',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.person, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ansprechpartner: $leiter',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                    // Hinweis-Text zur Standortlogik wurde aus der Hauptansicht entfernt (nur im Drawer).
                  ],
                ),
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
              onPressed: _onStatusPressed,
              selectedStatus: selectedStatus,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

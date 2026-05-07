import 'dart:async';
import 'dart:io';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/app_prefs.dart';
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
import 'main.dart' show themeNotifier, toggleTheme;
import 'map_screen.dart';
import 'profiles_screen.dart';
import 'data/profile_store.dart';
import 'staerke_editor_screen.dart';
import 'status_history_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'iot_car_helper.dart';
import 'alarm_overview_screen.dart';
import 'alarm_detail_screen.dart';
import 'alarm_notification.dart';
import 'alarm_overlay.dart' show kOverlayOpenDetail;
import 'data/alarm_store.dart';
import 'data/alarm_service.dart';

import 'data/unit_type_store.dart';
import 'simplified_status_panel.dart';
import 'unit_type_picker_screen.dart';
enum _ConnectionState { unknown, connected, degraded, disconnected }

class StatusOverview extends StatefulWidget {
  const StatusOverview({super.key});

  @override
  State<StatusOverview> createState() => _StatusOverviewState();
}

class _StatusOverviewState extends State<StatusOverview> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  bool _showStaerkeField = false; // Collapsible eigene Stärke

  // Eigene Stärke: Führung / Unterführer / Mannschaft
  int _eigeneF = 0;
  int _eigeneU = 0;
  int _eigeneM = 0;
  bool _isSendingStaerke = false;

  // Deployment & Tracking State
  DeploymentMode _deploymentMode = DeploymentMode.standby;
  TrackingMode _trackingMode = TrackingMode.balanced;
  int _batteryLevel = 100;

  // Stats
  Map<String, int> _stats = {'pending': 0, 'total': 0};

  // Verbindungsstatus
  _ConnectionState _connectionState = _ConnectionState.unknown;
  Timer? _connectionCheckTimer;

  // Einsatz-Timer
  Timer? _deploymentTickTimer;
  int _deploymentStartMs = 0;

  // Alarmierungs-Badge + Realtime-Listener
  int _alarmUnread = 0;
  StreamSubscription? _alarmEventSub;

  // Tracking ist immer gewünscht, sobald konfiguriert
  bool get _trackingDesired => true;

  // Hintergrund-Tracking-Indikator (GPS-Übertragung aktiv)
  bool _bgTrackingActive = false;

  // Auto-Deaktivierung in Minuten (0 = aus)
  int _autoDeactivateMinutes = 0;

  // Aktiver Profilname (für AppBar-Anzeige)
  String _activeProfileName = '';

  UnitType? _unitType;
  bool _gpsLoading = false;

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
    WidgetsBinding.instance.addObserver(this);
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

    // Car-Integration: Status-Änderungen von Android Auto / CarPlay empfangen
    IotCarHelper.initialize((status) {
      if (status >= 0 && status <= 9) {
        _onStatusPressed(status);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tempStatusTimer?.cancel();
    _statsRefreshTimer?.cancel();
    _connectionCheckTimer?.cancel();
    _deploymentTickTimer?.cancel();
    _alarmEventSub?.cancel();
    _infoCtrl.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.inactive) {
      _onAppPaused();
    }
  }

  /// Wird aufgerufen wenn die App in den Hintergrund geht.
  /// Stellt sicher, dass der Background-Service für Alarm-Empfang läuft.
  /// GPS-Übertragung nur wenn der Nutzer sie explizit aktiviert hat.
  Future<void> _onAppPaused() async {
    final svc = FlutterBackgroundService();
    final alarmConfigured = await AlarmService.isConfigured();

    // Service starten wenn nötig (für Alarmierung oder aktives Tracking)
    if (!await svc.isRunning() && (alarmConfigured || _bgTrackingActive)) {
      await svc.startService();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // GPS-Tracking nur wenn explizit aktiv
    if (_bgTrackingActive && await svc.isRunning()) {
      svc.invoke('setTracking', {'enabled': true});
    }
  }

  /// Wird aufgerufen wenn die App wieder in den Vordergrund kommt.
  /// Flusht die Queue sofort und aktualisiert den GPS-Tracking-Modus.
  Future<void> _refreshAlarmBadge() async {
    final count = await AlarmStore.unreadCount();
    if (mounted) setState(() => _alarmUnread = count);
  }

  Future<void> _openAlarmOverview() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AlarmOverviewScreen()),
    );
    // Badge zurücksetzen nachdem Nutzer die Übersicht besucht hat
    await AlarmStore.markAllSeen();
    if (mounted) setState(() => _alarmUnread = 0);
  }

  Future<void> _onAppResumed() async {
    // Queue sofort flushen (Daten die im Hintergrund aufgelaufen sind)
    try {
      await LocationSyncManager.instance.flushPendingNow(batchSize: 200);
    } catch (_) {}

    // Tracking-Modus aktualisieren (falls sich Akku/Status geändert hat)
    await _loadDeploymentState();
    await _updateBatteryLevel();
    await _refreshStats();

    // Tracking nur aufrechterhalten wenn es vorher aktiv war
    if (_bgTrackingActive) {
      final canTrack = await _hasBackgroundPermission();
      if (canTrack) {
        await _setBackgroundTracking(true);
      }
    }

    await _refreshAlarmBadge();

    // Overlay-Detail-Flag: wenn aus dem Alarm-Overlay auf "Details" getippt wurde
    await _checkOverlayDetailRequest();

    // Periodisches DB-Cleanup (einmal pro App-Resume, max alle 24h)
    await _maybeCleanupDatabase();
  }

  Future<void> _maybeCleanupDatabase() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCleanup = prefs.getInt(AppPrefsKeys.lastDbCleanupMs) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const cleanupInterval = Duration(hours: 24);
    if ((now - lastCleanup) >= cleanupInterval.inMilliseconds) {
      await LocationSyncManager.instance.cleanupOldEntries(maxAgeDays: 30);
      await prefs.setInt(AppPrefsKeys.lastDbCleanupMs, now);
    }
  }

  Future<void> _initialize() async {
    await _loadConfig();
    await _loadDeploymentState();
    await _updateBatteryLevel();
    await _ensureNotificationPermission();
    await _checkLocationServicesSilently();
    await _refreshAlarmBadge();

    final prefs = await SharedPreferences.getInstance();
    final firstRun = !(prefs.getBool(AppPrefsKeys.onboarded) ?? false);
    if (firstRun) {
      await _firstRunPermissionFlow();
      await prefs.setBool(AppPrefsKeys.onboarded, true);
    }

    // Hintergrund-Berechtigung sicherstellen
    final hasBgPerm = await _hasBackgroundPermission();
    if (!hasBgPerm) {
      await _requestBackgroundWithRationale();
    }

    // Batterie-Optimierung deaktivieren für dauerhaftes Hintergrund-Tracking
    await _requestDisableBatteryOptimization();

    // Overlay-Permission anfordern (Android: "Über anderen Apps anzeigen")
    // Nur relevant wenn Alarmierung konfiguriert ist
    if (Platform.isAndroid && await AlarmService.isConfigured()) {
      await _requestOverlayPermission();
    }

    final last = prefs.getInt(AppPrefsKeys.lastStatus) ?? 1;
    final autoDeact = prefs.getInt('autoDeactivateMinutes') ?? 0;

    final activeProfile = await ProfileStore.activeName() ?? '';

    // GPS-Übertragungsstatus: main.dart hat transmissionEnabled auf false gesetzt,
    // daher ist hier immer false (neu nach Neustart) – Service läuft evtl. für Alarmierung
    if (mounted) setState(() {
      _bgTrackingActive = false;
      _autoDeactivateMinutes = autoDeact;
      _activeProfileName = activeProfile;
    });
    await _onPersistentStatus(last, notify: false);

    // Stats und Verbindungsstatus regelmäßig aktualisieren
    _statsRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshStats();
    });

    // Alarm-Badge live aktualisieren wenn Background-Service einen neuen Alarm meldet
    _alarmEventSub = FlutterBackgroundService()
        .on('newAlarm')
        .listen((_) => _refreshAlarmBadge());
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkConnection();
    });
    await _refreshStats();
    await _checkConnection();
  }

  Future<void> _checkConnection() async {
    try {
      // Aktuellen Standort als Ping senden (kein Status-Seiteneffekt)
      double? lat, lon;
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          lat = pos.latitude;
          lon = pos.longitude;
        }
      } catch (_) {}

      final result = await EdpApi.instance.probe(lat: lat, lon: lon);
      final pending = _stats['pending'] ?? 0;
      if (!mounted) return;
      setState(() {
        if (result.ok) {
          _connectionState = pending > 0 ? _ConnectionState.degraded : _ConnectionState.connected;
        } else {
          _connectionState = _ConnectionState.disconnected;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _connectionState = _ConnectionState.disconnected);
    }
  }

  Future<void> _requestDisableBatteryOptimization() async {
    if (Platform.isAndroid) {
      try {
        final isBatteryOptDisabled =
            await DisableBatteryOptimization.isBatteryOptimizationDisabled;
        if (isBatteryOptDisabled != true) {
          await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();
        }
      } catch (_) {}
    }
  }

  Future<void> _checkOverlayDetailRequest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (prefs.getBool(kOverlayOpenDetail) != true) return;
      await prefs.remove(kOverlayOpenDetail);

      final alarm = await AlarmNotificationService.getPendingAlarm();
      if (alarm == null || !mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AlarmDetailScreen(alarm: alarm)),
      );
    } catch (_) {}
  }

  Future<void> _requestOverlayPermission() async {
    try {
      if (await FlutterOverlayWindow.isPermissionGranted()) return;
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Popup-Erlaubnis'),
          content: const Text(
            'Damit Alarmierungen als Popup über anderen Apps angezeigt werden, '
            'wird die Berechtigung „Über anderen Apps einblenden" benötigt.\n\n'
            'Bitte die App in der folgenden Einstellung zulassen.',
          ),
          actions: [
            TextButton(
              child: const Text('Überspringen'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Einstellung öffnen'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await FlutterOverlayWindow.requestPermission();
      }
    } catch (_) {}
  }

  Future<void> _loadDeploymentState() async {
    _deploymentMode = await DeploymentState.getMode();
    final status = await _getCurrentStatus();
    _trackingMode = await AdaptiveLocationSettings.determineMode(
      deployment: _deploymentMode,
      currentStatus: status,
    );

    // Einsatz-Timer laden
    if (_deploymentMode == DeploymentMode.deployed) {
      final prefs = await SharedPreferences.getInstance();
      _deploymentStartMs = prefs.getInt(AppPrefsKeys.deploymentStartMs) ?? 0;
      _startDeploymentTimer();
      WakelockPlus.enable();
    } else {
      _deploymentStartMs = 0;
      _deploymentTickTimer?.cancel();
      WakelockPlus.disable();
    }

    setState(() {});
  }

  void _startDeploymentTimer() {
    _deploymentTickTimer?.cancel();
    _deploymentTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  String _formatDeploymentDuration() {
    if (_deploymentStartMs == 0) return '';
    final elapsed = DateTime.now().millisecondsSinceEpoch - _deploymentStartMs;
    if (elapsed < 0) return '';
    final totalSec = elapsed ~/ 1000;
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<int> _getCurrentStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(AppPrefsKeys.lastStatus) ?? 1;
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
    final sp = prefs.getString(AppPrefsKeys.protocol) ?? protocol;
    final sv = prefs.getString(AppPrefsKeys.server) ?? server;
    final tk = prefs.getString(AppPrefsKeys.token) ?? token;
    final tr = prefs.getString(AppPrefsKeys.trupp) ?? trupp;
    final lt = prefs.getString(AppPrefsKeys.leiter) ?? leiter;
    final iss = prefs.getString(AppPrefsKeys.issi) ?? issi;
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
    _unitType = await UnitTypeStore.load();
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppPrefsKeys.transmissionEnabled, enabled);

      final svc = FlutterBackgroundService();
      if (enabled) {
        if (!await svc.isRunning()) {
          await svc.startService();
        }
        if (await svc.isRunning()) {
          svc.invoke('setTracking', {'enabled': true});
        }
      } else {
        if (await svc.isRunning()) {
          svc.invoke('stopService', {});
          // Kurz warten, dann Service für Alarm-Empfang neu starten falls konfiguriert
          await Future.delayed(const Duration(milliseconds: 800));
          if (await AlarmService.isConfigured() && !await svc.isRunning()) {
            await svc.startService();
          }
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _bgTrackingActive = enabled);
  }

  Future<void> _onPersistentStatus(int st, {bool notify = true}) async {
    _lastPersistentStatus = st;
    selectedStatus = st;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppPrefsKeys.lastStatus, st);
    await DeploymentState.updateActivity();

    final svc = FlutterBackgroundService();
    if (await svc.isRunning()) {
      svc.invoke('statusChanged', {'status': st});
    }

    // Service nur starten wenn Nutzer explizit einen Status drückt (notify: true)
    // oder der Service bereits läuft (aktiver Einsatz)
    if (notify || _bgTrackingActive) {
      if (!await _hasBackgroundPermission()) {
        if (notify) await _offerBackgroundPermission(st);
        return;
      }
      await _setBackgroundTracking(true);
    }

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
        } catch (sdsError) {
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
    // Haptic Feedback sofort auslösen
    _hapticForStatus(st);

    if (!await _hasWhileInUsePermission()) {
      final granted = await _requestWhileInUseWithRationale();
      if (!granted) {
        _showSnackbar('Standort nötig zum Senden', success: false);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Statuswechsel in History aufnehmen
    StatusHistory.add(st);

    // Status an Car-Display senden (Android Auto / CarPlay)
    IotCarHelper.sendStatusToIot(st);

    if (_isTempStatus(st)) {
      await _onTempStatus(st);
    } else {
      await _onPersistentStatus(st);
    }
  }

  Future<void> _offerBackgroundPermission(int st) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hintergrundortung'),
        content: const Text(
          'Damit bei Status 1, 3 und 7 auch bei geschlossener App der Standort gesendet wird, '
              'benötigt die App die „Immer"-Berechtigung.\n\nJetzt anfragen?',
        ),
        actions: [
          TextButton(
            child: const Text('Später'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
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
    if (_deploymentMode == DeploymentMode.deployed) {
      await _endDeploymentWithDialog();
    } else {
      // Einsatz starten
      await DeploymentState.setMode(DeploymentMode.deployed);
      _deploymentMode = DeploymentMode.deployed;

      // Übertragung automatisch aktivieren wenn noch nicht aktiv
      if (!_bgTrackingActive) {
        final canTrack = await _hasBackgroundPermission();
        if (canTrack) await _setBackgroundTracking(true);
      }

      final svc = FlutterBackgroundService();
      if (await svc.isRunning()) {
        svc.invoke('updateDeploymentMode', {'mode': DeploymentMode.deployed.name});
      }
      await _loadDeploymentState();
      _showSnackbar('Einsatz gestartet', success: true);
    }
  }

  Future<void> _endDeploymentWithDialog() async {
    final startMs = _deploymentStartMs;
    final endMs = DateTime.now().millisecondsSinceEpoch;
    final durationMin = startMs > 0 ? (endMs - startMs) ~/ 60000 : 0;
    final durationText = durationMin >= 60
        ? '${durationMin ~/ 60} Std ${durationMin % 60} Min'
        : '$durationMin Min';

    bool exportGpx = false;
    bool stopTracking = true;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Einsatz beenden?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (durationMin > 0)
                Text(
                  'Einsatzdauer: $durationText',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('GPS-Track exportieren (GPX)'),
                value: exportGpx,
                onChanged: (v) => setDialogState(() => exportGpx = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Übertragung deaktivieren'),
                value: stopTracking,
                onChanged: (v) => setDialogState(() => stopTracking = v ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Abbrechen'),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            FilledButton(
              child: const Text('Beenden'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    // GPX-Export vor dem Beenden (Positionen sind noch in der DB)
    if (exportGpx && startMs > 0) {
      try {
        final path = await GpxExporter.exportDeploymentGpx(
          startMs: startMs,
          endMs: endMs,
        );
        if (mounted) {
          await Share.shareXFiles([XFile(path)], text: 'Einsatz-Track');
        }
      } catch (e) {
        if (mounted) _showSnackbar('Export fehlgeschlagen: $e', success: false);
      }
    }

    // Deployment-Modus beenden
    await DeploymentState.setMode(DeploymentMode.standby);
    _deploymentMode = DeploymentMode.standby;

    final svc = FlutterBackgroundService();
    if (await svc.isRunning()) {
      svc.invoke('updateDeploymentMode', {'mode': DeploymentMode.standby.name});
    }

    if (stopTracking) {
      await _setBackgroundTracking(false);
    }

    await _loadDeploymentState();
    if (!mounted) return;
    // SnackBar mit optionalem Replay-Link
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Einsatz beendet'),
        backgroundColor: Colors.green,
        action: startMs > 0
            ? SnackBarAction(
                label: 'Replay',
                textColor: Colors.white,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MapScreen(
                      replayFromMs: startMs,
                      replayToMs: endMs,
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  /// Haptic Feedback je nach Status-Typ
  void _hapticForStatus(int st) {
    if (st == 0) {
      HapticFeedback.heavyImpact();
    } else if (_isTempStatus(st)) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.mediumImpact();
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

  Future<void> _sendEigeneStaerke() async {
    setState(() => _isSendingStaerke = true);
    try {
      // Fahrzeugbezeichnung aus eigener ISSI ableiten (wenn 5-stellig)
      final decoded = IssiHelper.isValidIssi(issi) ? IssiHelper.decode(issi) : trupp;
      final text = '$decoded Stärke: $_eigeneF/$_eigeneU/$_eigeneM';
      final res = await EdpApi.instance.sendSdsText(text);
      if (!mounted) return;
      if (res.ok) {
        _showSnackbar('Eigene Stärke gesendet', success: true);
        setState(() {
          _eigeneF = 0;
          _eigeneU = 0;
          _eigeneM = 0;
        });
      } else {
        _showSnackbar('Fehler: ${res.statusCode}', success: false);
      }
    } catch (e) {
      if (mounted) _showSnackbar('Fehler: $e', success: false);
    } finally {
      if (mounted) setState(() => _isSendingStaerke = false);
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Warteschlange löschen?'),
        content: const Text('Alle gespeicherten Positionen werden gelöscht.'),
        actions: [
          TextButton(
            child: const Text('Abbrechen'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
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
    final color = success ? Colors.green : Colors.red;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showInfoDialog({required String title, required String msg}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
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
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
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
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
            child: const Text('Abbrechen'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text('Weiter'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<void> _reloadConfig() async {
    await EdpApi.initFromPrefs();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      protocol = prefs.getString(AppPrefsKeys.protocol) ?? protocol;
      server = prefs.getString(AppPrefsKeys.server) ?? server;
      token = prefs.getString(AppPrefsKeys.token) ?? token;
      trupp = prefs.getString(AppPrefsKeys.trupp) ?? trupp;
      leiter = prefs.getString(AppPrefsKeys.leiter) ?? leiter;
      issi = prefs.getString(AppPrefsKeys.issi) ?? issi;
    });
  }

  Future<void> _showAutoDeactivateDialog() async {
    const options = [
      (0, 'Aus'),
      (30, '30 Minuten'),
      (60, '1 Stunde'),
      (120, '2 Stunden'),
      (240, '4 Stunden'),
      (480, '8 Stunden'),
    ];

    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Auto-Deaktivierung'),
        children: options.map((opt) {
          final (minutes, label) = opt;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, minutes),
            child: Row(
              children: [
                Radio<int>(
                  value: minutes,
                  groupValue: _autoDeactivateMinutes,
                  onChanged: (_) => Navigator.pop(ctx, minutes),
                ),
                Text(label),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (selected == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('autoDeactivateMinutes', selected);
    setState(() => _autoDeactivateMinutes = selected);

    final msg = selected == 0
        ? 'Auto-Deaktivierung deaktiviert'
        : 'Auto-Deaktivierung nach ${selected >= 60 ? '${selected ~/ 60}h' : '${selected}min'} Inaktivität';
    _showSnackbar(msg, success: true);
  }

  void _showMenu() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        color: _isDark ? Theme.of(context).colorScheme.surface : null,
        child: _buildMenuContent(),
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
            icon: Icons.assignment_ind,
            title: 'Melde-Editor',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const StaerkeEditorScreen()),
              );
            },
          ),
          _buildMenuItem(
            icon: Icons.health_and_safety,
            title: 'System-Check',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SystemCheckScreen()),
              );
            },
          ),
          _buildMenuItem(
            icon: Icons.settings,
            title: 'Konfiguration',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConfigScreen()),
              );
            },
          ),
          _buildMenuItem(
            icon: Icons.switch_account,
            title: _activeProfileName.isNotEmpty
                ? 'Profile  (${_activeProfileName})'
                : 'Profile',
            onTap: () async {
              Navigator.pop(context);
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilesScreen()),
              );
              // Profil könnte gewechselt worden sein → Config neu laden
              final active = await ProfileStore.activeName() ?? '';
              if (mounted) setState(() => _activeProfileName = active);
              await _reloadConfig();
            },
          ),
          _buildMenuItem(
            icon: Icons.history,
            title: 'Statusverlauf',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StatusHistoryScreen()),
              );
            },
          ),
          _buildMenuItem(
            icon: Icons.map,
            title: 'Live-Karte',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MapScreen()),
              );
            },
          ),
          _buildMenuItem(
            icon: Icons.download,
            title: 'GPX Export (Gesamt)',
            onTap: () {
              Navigator.pop(context);
              _exportGpx();
            },
          ),
          _buildMenuItem(
            icon: Icons.timer_off,
            title: _autoDeactivateMinutes == 0
                ? 'Auto-Deaktivierung: Aus'
                : 'Auto-Deaktivierung: ${_autoDeactivateMinutes >= 60 ? '${_autoDeactivateMinutes ~/ 60}h' : '${_autoDeactivateMinutes}min'}',
            onTap: () {
              Navigator.pop(context);
              _showAutoDeactivateDialog();
            },
          ),
          _buildMenuItem(
            icon: Icons.directions_run,
            title: 'Einheit wechseln',
            onTap: () {
              Navigator.pop(context);
              _changeUnitType();
            },
          ),
          _buildMenuItem(
            icon: themeNotifier.value == ThemeMode.dark
                ? Icons.light_mode
                : Icons.dark_mode,
            title: themeNotifier.value == ThemeMode.dark ? 'Light Mode' : 'Dark Mode',
            onTap: () {
              Navigator.pop(context);
              toggleTheme();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _manualSendGps() async {
    setState(() => _gpsLoading = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await LocationSyncManager.instance.sendOrQueue(
        lat: position.latitude,
        lon: position.longitude,
        accuracy: position.accuracy,
        status: selectedStatus ?? 2,
        timestamp: position.timestamp ?? DateTime.now(),
      );
      await LocationSyncManager.instance.flushPendingNow();
      _showSnackbar('Position gesendet', success: true);
    } catch (_) {
      _showSnackbar('GPS-Fehler', success: false);
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _changeUnitType() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UnitTypePickerScreen(
          allowBack: true,
          onComplete: null,
        ),
      ),
    );
    if (mounted) {
      final type = await UnitTypeStore.load();
      setState(() => _unitType = type);
    }
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
            const Icon(
              Icons.chevron_right,
              color: Colors.grey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showQrCode() async {
    final prefs = await SharedPreferences.getInstance();
    final pbUrl = prefs.getString(AppPrefsKeys.pbUrl) ?? '';
    final proApiUrl = prefs.getString(AppPrefsKeys.proApiUrl) ?? '';

    // Uri-Builder sorgt für korrekte Prozentkodierung aller Werte
    final params = <String, String>{
      'protocol': protocol,
      'server': '$server:$port',
      'token': token,
      'issi': issi,
      if (trupp.isNotEmpty && trupp != 'Unbekannt') 'trupp': trupp,
      if (leiter.isNotEmpty && leiter != 'Unbekannt') 'leiter': leiter,
      if (pbUrl.isNotEmpty) 'pb_url': pbUrl,
      if (proApiUrl.isNotEmpty) 'pro_api_url': proApiUrl,
    };
    final deeplink = Uri(
      scheme: 'truppapp',
      host: 'config',
      queryParameters: params,
    ).toString();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Konfigurations-QR-Code',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                server,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
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
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              // Zeige welche optionalen Parameter enthalten sind
              Wrap(
                spacing: 6,
                children: [
                  if (pbUrl.isNotEmpty)
                    _QrParamChip(label: 'Bereitschafts-App'),
                  if (proApiUrl.isNotEmpty)
                    _QrParamChip(label: 'EDP-Pro-API'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: deeplink));
                    if (mounted) Navigator.pop(context);
                    _showSnackbar('Link kopiert', success: true);
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Link kopieren'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
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

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    final scaffoldBg = _isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : Colors.grey[100];
    final appBarBg = _isDark ? Colors.red.shade900 : Colors.red.shade800;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('Status'),
        backgroundColor: appBarBg,
        elevation: 0,
        centerTitle: true,
        actions: [
          // Alarm-Glocke mit Badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.campaign_outlined, size: 24),
                tooltip: 'Alarmierungen',
                onPressed: _openAlarmOverview,
              ),
              if (_alarmUnread > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _alarmUnread > 99 ? '99+' : '$_alarmUnread',
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
                      _buildEigeneStaerkeSection(),
                      const SizedBox(height: 8),
                      _buildMessageSection(),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: _isDark
                      ? Theme.of(context).colorScheme.surface
                      : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(_isDark ? 0.2 : 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: (_unitType == null || _unitType == UnitType.erfahren)
                    ? Keypad(
                        onPressed: _onStatusPressed,
                        selectedStatus: selectedStatus,
                        lastPersistentStatus: _lastPersistentStatus,
                      )
                    : SimplifiedStatusPanel(
                        unitType: _unitType!,
                        onStatusPressed: _onStatusPressed,
                        onSendGps: _manualSendGps,
                        selectedStatus: selectedStatus,
                        gpsLoading: _gpsLoading,
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

            // Einsatz-Timer
            if (isDeployed && _deploymentStartMs > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatDeploymentDuration(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],

            const Spacer(),

            // Verbindungsstatus-Indikator
            _buildConnectionDot(),
            const SizedBox(width: 8),

            // Tracking Toggle (immer sichtbar, tippbar)
            GestureDetector(
              onTap: () async {
                if (_bgTrackingActive) {
                  await _setBackgroundTracking(false);
                  _showSnackbar('Übertragung deaktiviert', success: false);
                } else {
                  final canTrack = await _hasBackgroundPermission();
                  if (!canTrack) {
                    await _requestBackgroundWithRationale();
                    return;
                  }
                  await _setBackgroundTracking(true);
                  _showSnackbar('Übertragung aktiviert', success: true);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _bgTrackingActive
                      ? Colors.white.withOpacity(0.2)
                      : Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _bgTrackingActive ? Icons.gps_fixed : Icons.gps_off,
                      color: _bgTrackingActive ? Colors.white : Colors.white54,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'GPS',
                      style: TextStyle(
                        color: _bgTrackingActive ? Colors.white : Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

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

  Widget _buildConnectionDot() {
    Color dotColor;
    String tooltip;
    switch (_connectionState) {
      case _ConnectionState.connected:
        dotColor = Colors.greenAccent;
        tooltip = 'Verbunden';
        break;
      case _ConnectionState.degraded:
        dotColor = Colors.orangeAccent;
        tooltip = 'Warteschlange';
        break;
      case _ConnectionState.disconnected:
        dotColor = Colors.redAccent;
        tooltip = 'Offline';
        break;
      case _ConnectionState.unknown:
        dotColor = Colors.grey;
        tooltip = 'Prüfe...';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: dotColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: dotColor.withOpacity(0.6),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }

  // Essentielle Info (nur Trupp, Leiter, aktueller Status, Queue kompakt)
  Widget _buildEssentialInfo() {
    final cardBg = _isDark
        ? Theme.of(context).colorScheme.surface
        : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Trupp & Leiter kompakt
            Row(
              children: [
                Expanded(
                  child: _buildCompactInfo(
                    icon: Icons.group,
                    label: trupp,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCompactInfo(
                    icon: Icons.person,
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
                        Icons.storage,
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

  // Collapsible Eigene-Stärke-Sektion
  Widget _buildEigeneStaerkeSection() {
    final cardBg = _isDark
        ? Theme.of(context).colorScheme.surface
        : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () =>
                  setState(() => _showStaerkeField = !_showStaerkeField),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.groups, color: Colors.red.shade800, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Eigene Stärke melden',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(
                      _showStaerkeField
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (_showStaerkeField) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildStaerkeCounter(
                            abbr: 'Z',
                            label: 'Zugführer',
                            value: _eigeneF,
                            onChanged: (v) => setState(() => _eigeneF = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStaerkeCounter(
                            abbr: 'G',
                            label: 'Gruppenführer',
                            value: _eigeneU,
                            onChanged: (v) => setState(() => _eigeneU = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStaerkeCounter(
                            abbr: 'H',
                            label: 'Helfer',
                            value: _eigeneM,
                            onChanged: (v) => setState(() => _eigeneM = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Vorschau
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        () {
                          final decoded = IssiHelper.isValidIssi(issi)
                              ? IssiHelper.decode(issi)
                              : trupp;
                          return '$decoded Stärke: $_eigeneF/$_eigeneU/$_eigeneM';
                        }(),
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: Colors.red.shade800,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _isSendingStaerke ? null : _sendEigeneStaerke,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: _isSendingStaerke
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.send,
                                            color: Colors.white, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          'Stärke senden',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
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

  Widget _buildStaerkeCounter({
    required String abbr,
    required String label,
    required int value,
    required void Function(int) onChanged,
  }) {
    return Column(
      children: [
        Text(
          abbr,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _miniCounterBtn(
              icon: Icons.remove,
              onTap: value > 0 ? () => onChanged(value - 1) : null,
              primary: false,
            ),
            SizedBox(
              width: 30,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            _miniCounterBtn(
              icon: Icons.add,
              onTap: () => onChanged(value + 1),
              primary: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _miniCounterBtn({
    required IconData icon,
    required VoidCallback? onTap,
    required bool primary,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: (primary && onTap != null)
              ? Colors.red.shade800
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 15,
          color: (primary && onTap != null)
              ? Colors.white
              : (onTap != null ? Colors.black87 : Colors.grey.shade400),
        ),
      ),
    );
  }

  // Collapsible Nachrichtenfeld
  Widget _buildMessageSection() {
    final cardBg = _isDark
        ? Theme.of(context).colorScheme.surface
        : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
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
                      Icons.message,
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
                      child: TextFormField(
                        controller: _infoCtrl,
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

class _QrParamChip extends StatelessWidget {
  final String label;
  const _QrParamChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: Colors.green.shade50,
      side: BorderSide(color: Colors.green.shade200),
      labelStyle: TextStyle(color: Colors.green.shade700),
    );
  }
}

// lib/screens/system_check_screen.dart
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';

enum CheckStatus { ok, warning, error, checking }

class SystemCheckItem {
  final String title;
  final String description;
  CheckStatus status;
  String? details;
  VoidCallback? action;
  String? actionLabel;

  SystemCheckItem({
    required this.title,
    required this.description,
    this.status = CheckStatus.checking,
    this.details,
    this.action,
    this.actionLabel,
  });
}

class SystemCheckScreen extends StatefulWidget {
  const SystemCheckScreen({super.key});

  @override
  State<SystemCheckScreen> createState() => _SystemCheckScreenState();
}

class _SystemCheckScreenState extends State<SystemCheckScreen> {
  final List<SystemCheckItem> _checks = [];
  bool _isChecking = true;
  int _okCount = 0;
  int _warningCount = 0;
  int _errorCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeChecks();
    _runAllChecks();
  }

  void _initializeChecks() {
    _checks.addAll([
      SystemCheckItem(
        title: 'Standort-Berechtigung (Bei Nutzung)',
        description: 'Benötigt zum Senden von Status-Updates',
      ),
      SystemCheckItem(
        title: 'Standort-Berechtigung (Immer)',
        description: 'Benötigt für Hintergrund-Tracking',
      ),
      SystemCheckItem(
        title: 'Standortdienste',
        description: 'GPS muss aktiviert sein',
      ),
      SystemCheckItem(
        title: 'Benachrichtigungen',
        description: 'Wichtig für Hintergrund-Service',
      ),
      if (Platform.isAndroid)
        SystemCheckItem(
          title: 'Akku-Optimierung',
          description: 'Sollte deaktiviert sein',
        ),
      SystemCheckItem(
        title: 'GPS-Genauigkeit',
        description: 'Hohe Genauigkeit empfohlen',
      ),
      SystemCheckItem(
        title: 'Hintergrund-Service',
        description: 'Status des Background-Services',
      ),
      SystemCheckItem(
        title: 'Konfiguration',
        description: 'Server und Token konfiguriert',
      ),
      SystemCheckItem(
        title: 'Akkustand',
        description: 'Ausreichend Akku für Einsatz',
      ),
    ]);
  }

  Future<void> _runAllChecks() async {
    setState(() => _isChecking = true);

    await Future.wait([
      _checkLocationPermissionWhileInUse(),
      _checkLocationPermissionAlways(),
      _checkLocationServices(),
      _checkNotificationPermission(),
      if (Platform.isAndroid) _checkBatteryOptimization(),
      _checkGpsAccuracy(),
      _checkBackgroundService(),
      _checkConfiguration(),
      _checkBatteryLevel(),
    ]);

    _updateCounts();
    setState(() => _isChecking = false);
  }

  void _updateCounts() {
    _okCount = _checks.where((c) => c.status == CheckStatus.ok).length;
    _warningCount = _checks.where((c) => c.status == CheckStatus.warning).length;
    _errorCount = _checks.where((c) => c.status == CheckStatus.error).length;
  }

  Future<void> _checkLocationPermissionWhileInUse() async {
    final check = _checks.firstWhere((c) => c.title.contains('Bei Nutzung'));

    try {
      final permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        check.status = CheckStatus.ok;
        check.details = 'Berechtigung erteilt';
      } else if (permission == LocationPermission.denied) {
        check.status = CheckStatus.error;
        check.details = 'Berechtigung nicht erteilt';
        check.actionLabel = 'Erlauben';
        check.action = () async {
          await Geolocator.requestPermission();
          await _runAllChecks();
        };
      } else {
        check.status = CheckStatus.error;
        check.details = 'Dauerhaft verweigert - Einstellungen öffnen';
        check.actionLabel = 'Einstellungen';
        check.action = () async {
          await Geolocator.openLocationSettings();
        };
      }
    } catch (e) {
      check.status = CheckStatus.error;
      check.details = 'Fehler beim Prüfen: $e';
    }

    if (mounted) setState(() {});
  }

  Future<void> _checkLocationPermissionAlways() async {
    final check = _checks.firstWhere((c) => c.title.contains('Immer'));

    try {
      final permission = await Geolocator.checkPermission();

      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        if (permission == LocationPermission.always) {
          check.status = CheckStatus.ok;
          check.details = 'Hintergrund-Ortung erlaubt';
        } else if (permission == LocationPermission.whileInUse) {
          check.status = CheckStatus.warning;
          check.details = 'Nur während Nutzung - empfohlen: Immer';
          check.actionLabel = 'Einstellungen';
          check.action = () async {
            await Geolocator.openLocationSettings();
          };
        } else {
          check.status = CheckStatus.error;
          check.details = 'Nicht erteilt';
          check.actionLabel = 'Einstellungen';
          check.action = () async {
            await Geolocator.openLocationSettings();
          };
        }
      } else {
        // Android
        final bgStatus = await Permission.locationAlways.status;
        if (bgStatus.isGranted || permission == LocationPermission.always) {
          check.status = CheckStatus.ok;
          check.details = 'Hintergrund-Ortung erlaubt';
        } else if (permission == LocationPermission.whileInUse) {
          check.status = CheckStatus.warning;
          check.details = 'Nur während Nutzung - empfohlen: Immer erlauben';
          check.actionLabel = 'Erlauben';
          check.action = () async {
            await Permission.locationAlways.request();
            await _runAllChecks();
          };
        } else {
          check.status = CheckStatus.error;
          check.details = 'Nicht erteilt';
          check.actionLabel = 'Einstellungen';
          check.action = () async {
            await openAppSettings();
          };
        }
      }
    } catch (e) {
      check.status = CheckStatus.error;
      check.details = 'Fehler beim Prüfen: $e';
    }

    if (mounted) setState(() {});
  }

  Future<void> _checkLocationServices() async {
    final check = _checks.firstWhere((c) => c.title.contains('Standortdienste'));

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();

      if (enabled) {
        check.status = CheckStatus.ok;
        check.details = 'GPS ist aktiviert';
      } else {
        check.status = CheckStatus.error;
        check.details = 'GPS ist deaktiviert';
        check.actionLabel = 'Einstellungen';
        check.action = () async {
          await Geolocator.openLocationSettings();
        };
      }
    } catch (e) {
      check.status = CheckStatus.error;
      check.details = 'Fehler beim Prüfen: $e';
    }

    if (mounted) setState(() {});
  }

  Future<void> _checkNotificationPermission() async {
    final check = _checks.firstWhere((c) => c.title.contains('Benachrichtigungen'));

    if (Platform.isAndroid) {
      try {
        final status = await Permission.notification.status;

        if (status.isGranted) {
          check.status = CheckStatus.ok;
          check.details = 'Benachrichtigungen erlaubt';
        } else {
          check.status = CheckStatus.warning;
          check.details = 'Benachrichtigungen empfohlen für Background-Service';
          check.actionLabel = 'Erlauben';
          check.action = () async {
            await Permission.notification.request();
            await _runAllChecks();
          };
        }
      } catch (e) {
        check.status = CheckStatus.warning;
        check.details = 'Konnte Status nicht prüfen';
      }
    } else {
      // iOS prüft automatisch bei Background-Service Start
      check.status = CheckStatus.ok;
      check.details = 'iOS verwaltet Benachrichtigungen automatisch';
    }

    if (mounted) setState(() {});
  }

  Future<void> _checkBatteryOptimization() async {
    if (!Platform.isAndroid) return;

    final check = _checks.firstWhere((c) => c.title.contains('Akku-Optimierung'));

    try {
      final isDisabled = await DisableBatteryOptimization.isBatteryOptimizationDisabled;

      if (isDisabled ?? false) {
        check.status = CheckStatus.ok;
        check.details = 'Optimierung deaktiviert (empfohlen)';
      } else {
        check.status = CheckStatus.warning;
        check.details = 'Akku-Optimierung aktiv - kann Background-Tracking stoppen';
        check.actionLabel = 'Deaktivieren';
        check.action = () async {
          await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();
        };
      }
    } catch (e) {
      check.status = CheckStatus.warning;
      check.details = 'Konnte Status nicht prüfen';
    }

    if (mounted) setState(() {});
  }


  Future<void> _checkGpsAccuracy() async {
    final check = _checks.firstWhere((c) => c.title.contains('GPS-Genauigkeit'));

    try {
      final permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        check.status = CheckStatus.error;
        check.details = 'Standort-Berechtigung fehlt';
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('GPS-Timeout'),
      );

      if (position.accuracy <= 20) {
        check.status = CheckStatus.ok;
        check.details = 'Genauigkeit: ${position.accuracy.toStringAsFixed(1)}m (sehr gut)';
      } else if (position.accuracy <= 50) {
        check.status = CheckStatus.ok;
        check.details = 'Genauigkeit: ${position.accuracy.toStringAsFixed(1)}m (gut)';
      } else if (position.accuracy <= 100) {
        check.status = CheckStatus.warning;
        check.details = 'Genauigkeit: ${position.accuracy.toStringAsFixed(1)}m (akzeptabel)';
      } else {
        check.status = CheckStatus.warning;
        check.details = 'Genauigkeit: ${position.accuracy.toStringAsFixed(1)}m (niedrig)';
        check.actionLabel = 'Tipps';
        check.action = () {
          _showAccuracyTips();
        };
      }
    } catch (e) {
      check.status = CheckStatus.warning;
      check.details = 'GPS-Signal nicht verfügbar (Gebäude/Indoor?)';
      check.actionLabel = 'Tipps';
      check.action = () {
        _showAccuracyTips();
      };
    }

    if (mounted) setState(() {});
  }

  Future<void> _checkBackgroundService() async {
    final check = _checks.firstWhere((c) => c.title.contains('Hintergrund-Service'));

    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (isRunning) {
        check.status = CheckStatus.ok;
        check.details = 'Service läuft';
      } else {
        check.status = CheckStatus.warning;
        check.details = 'Service nicht aktiv - wird bei Bedarf gestartet';
      }
    } catch (e) {
      check.status = CheckStatus.warning;
      check.details = 'Konnte Status nicht prüfen';
    }

    if (mounted) setState(() {});
  }

  Future<void> _checkConfiguration() async {
    final check = _checks.firstWhere((c) => c.title.contains('Konfiguration'));

    try {
      final prefs = await SharedPreferences.getInstance();
      final server = prefs.getString('server') ?? '';
      final token = prefs.getString('token') ?? '';
      final trupp = prefs.getString('trupp') ?? '';

      if (server.isNotEmpty && token.isNotEmpty && trupp.isNotEmpty) {
        check.status = CheckStatus.ok;
        check.details = 'Server, Token und Trupp konfiguriert';
      } else {
        check.status = CheckStatus.error;
        final missing = <String>[];
        if (server.isEmpty) missing.add('Server');
        if (token.isEmpty) missing.add('Token');
        if (trupp.isEmpty) missing.add('Trupp');
        check.details = 'Fehlend: ${missing.join(', ')}';
        check.actionLabel = 'Konfigurieren';
        check.action = () {
          Navigator.pop(context);
          // Config-Screen sollte vom Haupt-Screen geöffnet werden
        };
      }
    } catch (e) {
      check.status = CheckStatus.error;
      check.details = 'Fehler beim Prüfen: $e';
    }

    if (mounted) setState(() {});
  }

  Future<void> _checkBatteryLevel() async {
    final check = _checks.firstWhere((c) => c.title.contains('Akkustand'));

    try {
      final battery = Battery();
      final level = await battery.batteryLevel;

      if (level >= 50) {
        check.status = CheckStatus.ok;
        check.details = 'Akku: $level% (gut)';
      } else if (level >= 20) {
        check.status = CheckStatus.warning;
        check.details = 'Akku: $level% (niedrig - bald laden)';
      } else {
        check.status = CheckStatus.error;
        check.details = 'Akku: $level% (kritisch - jetzt laden!)';
      }
    } catch (e) {
      check.status = CheckStatus.warning;
      check.details = 'Konnte Akkustand nicht prüfen';
    }

    if (mounted) setState(() {});
  }

  void _showAccuracyTips() {
    showPlatformDialog(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: const Text('GPS-Genauigkeit verbessern'),
        content: const Text(
          'Tipps für bessere GPS-Genauigkeit:\n\n'
              '• Nach draußen gehen (freie Sicht zum Himmel)\n'
              '• Von Gebäuden/Metall wegbewegen\n'
              '• GPS ein paar Minuten "warmlaufen" lassen\n'
              '• Flugmodus aus/ein schalten\n'
              '• Handy neustarten\n'
              '• "Hohe Genauigkeit" in Standort-Einstellungen',
        ),
        actions: [
          PlatformDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
          PlatformDialogAction(
            child: const Text('Einstellungen'),
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openLocationSettings();
            },
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(CheckStatus status) {
    switch (status) {
      case CheckStatus.ok:
        return Colors.green;
      case CheckStatus.warning:
        return Colors.orange;
      case CheckStatus.error:
        return Colors.red;
      case CheckStatus.checking:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(CheckStatus status) {
    switch (status) {
      case CheckStatus.ok:
        return isMaterial(context) ? Icons.check_circle : CupertinoIcons.check_mark_circled_solid;
      case CheckStatus.warning:
        return isMaterial(context) ? Icons.warning : CupertinoIcons.exclamationmark_triangle_fill;
      case CheckStatus.error:
        return isMaterial(context) ? Icons.error : CupertinoIcons.xmark_circle_fill;
      case CheckStatus.checking:
        return isMaterial(context) ? Icons.hourglass_empty : CupertinoIcons.hourglass;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allOk = _errorCount == 0 && _warningCount == 0 && !_isChecking;

    return PlatformScaffold(
      backgroundColor: isMaterial(context) ? Colors.grey[100] : CupertinoColors.systemGroupedBackground,
      appBar: PlatformAppBar(
        title: const Text('System-Check'),
        material: (_, _) => MaterialAppBarData(
          backgroundColor: allOk ? Colors.green.shade800 : Colors.red.shade800,
          elevation: 0,
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isChecking ? null : _runAllChecks,
              tooltip: 'Erneut prüfen',
            ),
          ],
        ),
        cupertino: (_, _) => CupertinoNavigationBarData(
          backgroundColor: allOk ? Colors.green.shade800 : Colors.red.shade800,
          trailing: GestureDetector(
            onTap: _isChecking ? null : _runAllChecks,
            child: Icon(
              CupertinoIcons.refresh,
              color: _isChecking ? Colors.white.withOpacity(0.5) : Colors.white,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSummaryHeader(allOk),
            Expanded(
              child: _isChecking
                  ? _buildLoadingState()
                  : _buildCheckList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryHeader(bool allOk) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: allOk ? Colors.green.shade800 : Colors.red.shade800,
        border: Border(
          bottom: BorderSide(
            color: allOk ? Colors.green.shade900 : Colors.red.shade900,
            width: 2,
          ),
        ),
      ),
      child: Column(
        children: [
          Icon(
            allOk
                ? (isMaterial(context) ? Icons.check_circle : CupertinoIcons.check_mark_circled_solid)
                : (isMaterial(context) ? Icons.warning : CupertinoIcons.exclamationmark_triangle_fill),
            color: Colors.white,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            allOk ? 'Alles bereit!' : 'Verbesserungen empfohlen',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSummaryBadge(
                icon: Icons.check_circle,
                count: _okCount,
                color: Colors.green.shade300,
              ),
              const SizedBox(width: 12),
              if (_warningCount > 0)
                _buildSummaryBadge(
                  icon: Icons.warning,
                  count: _warningCount,
                  color: Colors.orange.shade300,
                ),
              if (_warningCount > 0) const SizedBox(width: 12),
              if (_errorCount > 0)
                _buildSummaryBadge(
                  icon: Icons.error,
                  count: _errorCount,
                  color: Colors.red.shade300,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBadge({
    required IconData icon,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            count.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PlatformCircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text(
            'Prüfe System-Einstellungen...',
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _checks.length,
      itemBuilder: (context, index) {
        final check = _checks[index];
        return _buildCheckItem(check);
      },
    );
  }

  Widget _buildCheckItem(SystemCheckItem check) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isMaterial(context) ? Colors.white : CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getStatusColor(check.status).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getStatusIcon(check.status),
                  color: _getStatusColor(check.status),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        check.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        check.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (check.details != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _getStatusColor(check.status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        check.details!,
                        style: TextStyle(
                          fontSize: 13,
                          color: _getStatusColor(check.status),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (check.action != null && check.actionLabel != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: PlatformElevatedButton(
                  onPressed: check.action,
                  child: Text(check.actionLabel!),
                  material: (_, _) => MaterialElevatedButtonData(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _getStatusColor(check.status),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  cupertino: (_, _) => CupertinoElevatedButtonData(
                    color: _getStatusColor(check.status),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
}
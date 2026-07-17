// lib/service.dart
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/app_prefs.dart';
import 'data/app_logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'data/edp_api.dart';
import 'data/location_quality.dart';
import 'data/profile_store.dart';
import 'data/location_sync_manager.dart';
import 'data/status_sync_manager.dart';
import 'data/deployment_state.dart';
import 'data/adaptive_location_settings.dart';
import 'data/auto_delete_config.dart';
import 'data/duty_end_config.dart';

import 'foreground_notification.dart';

// Globale Variablen für Service-Isolate
int _currentStatus = 0;
DeploymentMode _deploymentMode = DeploymentMode.standby;
TrackingMode _trackingMode = TrackingMode.balanced;

// Smart Heartbeat mit Bewegungserkennung
class SmartHeartbeat {
  static Position? _lastPosition;
  static DateTime? _lastMovement;
  static bool _isStationary = false;

  static Duration getHeartbeatInterval() {
    return AdaptiveLocationSettings.getHeartbeatInterval(_trackingMode, _isStationary);
  }

  static void updateMovementState(Position current) {
    if (_lastPosition == null) {
      _lastPosition = current;
      _lastMovement = DateTime.now();
      _isStationary = false;
      return;
    }

    final distance = Geolocator.distanceBetween(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
      current.latitude,
      current.longitude,
    );

    // Bewegung erkannt (>20m)
    if (distance > 20) {
      _isStationary = false;
      _lastMovement = DateTime.now();
      _lastPosition = current;
    }
    // Länger als 5 Min keine Bewegung
    else if (_lastMovement != null &&
        DateTime.now().difference(_lastMovement!) > const Duration(minutes: 5)) {
      _isStationary = true;
    }
  }

  static bool get isStationary => _isStationary;
}

const _minAccuracyMeters = 50.0;
const _minSendInterval = Duration(seconds: 5);
const _minDistanceMeters = 5.0;

final _quality = LocationQualityFilter(
  maxAccuracyM: _minAccuracyMeters,
  minDistanceM: _minDistanceMeters,
  minInterval: _minSendInterval,
  maxJumpSpeedMs: 55.0,  // ~200 km/h - Einsatzfahrzeuge fahren schnell
  heartbeatInterval: const Duration(seconds: 30),
);

Timer? _hbTimer;
Timer? _modeCheckTimer;
Timer? _flushTimer;
StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

/// Alle service.on(...)-Subscriptions, damit sie beim Stoppen sauber
/// gecancelt werden — sonst akkumulieren sich Handler über Service-Neustarts
/// und alte Handler arbeiten auf verwaistem State weiter.
final List<StreamSubscription> _serviceEventSubs = [];

// Connectivity-Flush-Debounce: ein Wiederherstellungs-Event darf nicht
// sofort 200 HTTP-Requests starten. Bei flakiger Verbindung kommen oft
// mehrere Events kurz hintereinander — wir warten 10 s und feuern dann
// genau einmal. Zusätzlich ein Reentrancy-Guard: läuft schon ein Flush,
// nicht parallel starten.
Timer? _connectivityFlushDebounce;
bool _flushInProgress = false;

/// Minimum-Intervall zwischen zwei Notification-Updates. Verhindert dass
/// `setForegroundNotificationInfo` 17 000 Mal/Tag im highAccuracy-Modus
/// (alle 5 s) den StatusBar-Redraw triggert.
const _kMinNotificationInterval = Duration(seconds: 30);
DateTime? _lastNotificationUpdate;
String? _lastNotificationContent;

/// Aktualisiert die FGS-Notification nur, wenn (a) der Inhalt sich ändert UND
/// (b) seit dem letzten Update mind. [_kMinNotificationInterval] vergangen
/// ist — ODER [force] gesetzt ist (z.B. bei Status-/Deployment-Wechsel,
/// damit der Nutzer das Update sofort sieht).
Future<void> _updateNotificationIfDue(
  ServiceInstance service, {
  required String title,
  required String content,
  bool force = false,
}) async {
  if (service is! AndroidServiceInstance) return;

  // Inhalts-Dedup: gleicher Text → kein Update (egal ob force).
  if (content == _lastNotificationContent && !force) return;

  // Throttle: wenn nicht erzwungen und das letzte Update <30 s her ist,
  // skippen.
  final now = DateTime.now();
  if (!force &&
      _lastNotificationUpdate != null &&
      now.difference(_lastNotificationUpdate!) < _kMinNotificationInterval) {
    return;
  }

  _lastNotificationContent = content;
  _lastNotificationUpdate = now;
  await service.setForegroundNotificationInfo(title: title, content: content);
}

Future<int> _readStatusFromPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  // Default 1 = „Einsatzbereit". Status 0 wäre „Dringender Notruf" (TETRA)
  // und darf nicht versehentlich aus einem leeren Pref entstehen.
  return prefs.getInt(AppPrefsKeys.lastStatus) ?? 1;
}

Future<bool> _hasValidConfig() async {
  return EdpApi.hasValidConfigInPrefs();
}

Future<void> _ensureFullAccuracyIfPossible() async {
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    final status = await Geolocator.getLocationAccuracy();
    if (status == LocationAccuracyStatus.reduced) {
      try {
        await Geolocator.requestTemporaryFullAccuracy(purposeKey: 'PreciseTracking');
      } catch (_) {
        /* Ignorieren */
      }
    }
  }
}

Future<void> _sendPositionIfOk(ServiceInstance service, Position pos,
    {bool forceByHeartbeat = false}) async {
  final now = DateTime.now();

  // Bewegungsstatus aktualisieren
  SmartHeartbeat.updateMovementState(pos);

  // Qualität / Drosselung
  if (!_quality.isGood(pos, now: now, forceByHeartbeat: forceByHeartbeat)) {
    await _updateNotificationIfDue(
      service,
      title: 'Trupp App',
      content: _getNotificationContent(isWaiting: true),
    );
    return;
  }

  if (!await _hasValidConfig()) {
    AppLogger.w('DIAG', 'Position NICHT gesendet – keine gültige Webhook-Config');
    return;
  }

  try {
    await LocationSyncManager.instance.sendOrQueue(
      lat: pos.latitude,
      lon: pos.longitude,
      accuracy: pos.accuracy.isFinite ? pos.accuracy : null,
      status: _currentStatus,
      timestamp: pos.timestamp,
    );
    AppLogger.i('DIAG',
        'Position an Webhook übergeben (lat=${pos.latitude.toStringAsFixed(5)}, status=$_currentStatus)');

    _quality.markSent(pos, now: now);

    await _updateNotificationIfDue(
      service,
      title: 'Trupp App',
      content: _getNotificationContent(),
    );
  } catch (e, st) {
    AppLogger.e('LocationService', 'Positionsübertragung fehlgeschlagen', e, st);
  }
}

int _lastPendingCount = 0;

Future<String> _getNotificationContentAsync({bool isWaiting = false}) async {
  try {
    _lastPendingCount = await LocationSyncManager.instance.getStats()
        .then((s) => s['pending'] ?? 0);
  } catch (_) {}
  return _getNotificationContent(isWaiting: isWaiting);
}

String _getNotificationContent({bool isWaiting = false}) {
  final modeText = _deploymentMode == DeploymentMode.deployed
      ? 'Im Einsatz'
      : _deploymentMode == DeploymentMode.stationary
          ? 'UHS-Standort'
          : (_deploymentMode == DeploymentMode.returning
              ? 'Rückweg'
              : 'Bereitschaft');

  final trackingText = AdaptiveLocationSettings.getModeDescription(_trackingMode);
  final pendingText = _lastPendingCount > 0 ? ' | $_lastPendingCount ausstehend' : '';

  if (isWaiting) {
    return '$modeText (Status $_currentStatus) - Warte auf GPS…$pendingText';
  }

  if (SmartHeartbeat.isStationary) {
    return '$modeText (Status $_currentStatus) - Stillstand - $trackingText$pendingText';
  }

  return '$modeText (Status $_currentStatus) - $trackingText$pendingText';
}

Future<void> _heartbeatTick(ServiceInstance service) async {
  try {
    // Accuracy + Timeout an den aktuellen Tracking-Modus anpassen —
    // im powerSaver muss kein bestForNavigation-Fix angefordert werden,
    // im Einsatz darf der Fix nicht zu lange dauern.
    final accuracy =
        AdaptiveLocationSettings.getOneShotAccuracy(_trackingMode);
    final timeout = AdaptiveLocationSettings.getOneShotTimeout(_trackingMode);

    // Immer frische Position holen - nie veralteten Cache senden
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        timeLimit: timeout,
      ),
    );

    await _sendPositionIfOk(service, pos, forceByHeartbeat: true);
  } catch (e, st) {
    AppLogger.e('LocationService', 'Heartbeat-GPS fehlgeschlagen', e, st);
  }
}

void _scheduleNextHeartbeat(ServiceInstance service) {
  _hbTimer?.cancel();

  // Akku: In Bereitschaft (kein Einsatz) + Energiesparmodus + Stillstand
  // braucht es keinen 5-Minuten-Heartbeat — 15 Minuten reichen, um „lebendig"
  // zu bleiben. Bewegung oder Statuswechsel setzen das Intervall sofort
  // wieder herunter (Stream-Update bzw. _updateTrackingMode).
  var interval = SmartHeartbeat.getHeartbeatInterval();
  if (_deploymentMode == DeploymentMode.standby &&
      _trackingMode == TrackingMode.powerSaver &&
      SmartHeartbeat.isStationary) {
    interval = const Duration(minutes: 15);
  }

  _hbTimer = Timer(interval, () async {
    await _heartbeatTick(service);
    _scheduleNextHeartbeat(service); // Rekursiv mit neuem Intervall
  });
}

/// Callback wird von onStart gesetzt, damit _updateTrackingMode den Stream
/// bei Moduswechsel neu starten kann.
Future<void> Function()? _restartStreamCallback;

/// Liefert die zum TrackingMode passende Quality-Filter-Mindestdistanz.
/// Faustregel: ~halber Stream-distanceFilter, damit der Filter im powerSaver
/// (Stream-DF 100 m) nicht alles durchlässt was er nicht schon vom OS
/// gefiltert bekommen hat.
double _minDistanceForMode(TrackingMode mode) {
  switch (mode) {
    case TrackingMode.highAccuracy:
      return 5.0;
    case TrackingMode.balanced:
      return 8.0;
    case TrackingMode.powerSaver:
      return 40.0;
  }
}

/// Setzt Distanz- und Genauigkeits-Schwellen des Quality-Filters passend zum
/// aktuellen TrackingMode und den App-Einstellungen (u.a. „nur präziser
/// Standort").
void _applyQualityThresholds(TrackingMode mode) {
  _quality.setMinDistance(_minDistanceForMode(mode));
  _quality.setMaxAccuracy(AdaptiveLocationSettings.getMaxAccuracy(mode));
}

/// Lädt die konfigurierbaren Tracking-Einstellungen in die (Isolate-lokalen)
/// statischen Felder von [AdaptiveLocationSettings].
Future<void> _loadTrackingPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  AdaptiveLocationSettings.highFrequency =
      prefs.getBool(AppPrefsKeys.highFrequencyTracking) ?? true;
  AdaptiveLocationSettings.preciseLocationOnly =
      prefs.getBool(AppPrefsKeys.preciseLocationOnly) ?? true;
}

Future<void> _updateTrackingMode(ServiceInstance service) async {
  final newMode = await AdaptiveLocationSettings.determineMode(
    deployment: _deploymentMode,
    currentStatus: _currentStatus,
  );

  if (newMode != _trackingMode) {
    _trackingMode = newMode;
    _applyQualityThresholds(newMode);

    // GPS-Stream mit neuen Einstellungen neu starten
    if (_restartStreamCallback != null) {
      await _restartStreamCallback!();
    }

    // Modus-Wechsel ist eine sichtbare Zustandsänderung → force=true,
    // damit der Nutzer sofort sieht "Energiesparmodus" statt nach 30 s.
    await _updateNotificationIfDue(
      service,
      title: 'Trupp App',
      content: _getNotificationContent(),
      force: true,
    );
  }
}

void _schedulePeriodicModeCheck(ServiceInstance service) {
  _modeCheckTimer?.cancel();
  _modeCheckTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
    // Abgelaufenes temporäres Einsatz-Profil aufräumen: Profil wird gelöscht
    // und das Standard-Profil aktiviert, damit keine Positionen mehr unter
    // der vergessenen Einsatz-Kennung gesendet werden.
    final expired = await ProfileStore.expireTemporaryIfDue();
    if (expired != null) {
      AppLogger.i('LocationService',
          'Einsatz-Profil "${expired.expiredName}" abgelaufen und gelöscht');
      if (expired.fallback != null) {
        // Standard-Profil übernehmen: Config neu laden, GPS-Stream neu starten
        await EdpApi.initFromPrefs();
        if (_restartStreamCallback != null) {
          await _restartStreamCallback!();
        }
        await _updateNotificationIfDue(
          service,
          title: 'Trupp App',
          content:
              'Einsatz-Profil abgelaufen – "${expired.fallback!.name}" aktiviert',
          force: true,
        );
      } else {
        // Kein Standard-Profil hinterlegt → Übertragung komplett stoppen
        _hbTimer?.cancel();
        _flushTimer?.cancel();
        _connectivitySub?.cancel();
        _connectivityFlushDebounce?.cancel();
        await service.stopSelf();
        return;
      }
    }

    // AutoDelete: Konfiguration automatisch löschen (nach X Stunden oder zu
    // einer festgelegten Uhrzeit). Danach ist keine gültige Konfiguration mehr
    // vorhanden → Service stoppen.
    if (await AutoDeleteConfig.deleteIfDue()) {
      AppLogger.i('LocationService', 'Konfiguration durch AutoDelete gelöscht');
      _hbTimer?.cancel();
      _flushTimer?.cancel();
      _connectivitySub?.cancel();
      _connectivityFlushDebounce?.cancel();
      for (final s in _serviceEventSubs) {
        s.cancel();
      }
      _serviceEventSubs.clear();
      await service.stopSelf();
      return;
    }

    // Dienstende: automatische Abmeldung zur festgelegten Zeit (Übertragung
    // stoppen, Einsatz/UHS beenden). Danach Service stoppen.
    if (await DutyEndConfig.signOffIfDue()) {
      AppLogger.i('LocationService', 'Dienstende erreicht – automatisch abgemeldet');
      _deploymentMode = DeploymentMode.standby;
      _hbTimer?.cancel();
      _flushTimer?.cancel();
      _connectivitySub?.cancel();
      _connectivityFlushDebounce?.cancel();
      for (final s in _serviceEventSubs) {
        s.cancel();
      }
      _serviceEventSubs.clear();
      await service.stopSelf();
      return;
    }

    await _updateTrackingMode(service);

    // Konfigurierbarer Auto-Deaktivierungs-Timer
    final prefs = await SharedPreferences.getInstance();
    final autoDeactMin = prefs.getInt(AppPrefsKeys.autoDeactivateMinutes) ?? 0;
    if (autoDeactMin > 0 && await DeploymentState.shouldAutoStop(inactiveMinutes: autoDeactMin)) {
      await DeploymentState.setMode(DeploymentMode.standby);
      _deploymentMode = DeploymentMode.standby;
      await prefs.setBool(AppPrefsKeys.transmissionEnabled, false);
      // Timers und Subscriptions kündigen bevor Service stoppt
      _hbTimer?.cancel();
      _flushTimer?.cancel();
      _connectivitySub?.cancel();
      _connectivityFlushDebounce?.cancel();
      for (final s in _serviceEventSubs) {
        s.cancel();
      }
      _serviceEventSubs.clear();
      await service.stopSelf();
      return;
    }

    // Fester Deployment-Reset nach 3 Stunden Inaktivität (Service bleibt aktiv)
    if (await DeploymentState.shouldAutoStop(inactiveMinutes: 180)) {
      await DeploymentState.setMode(DeploymentMode.standby);
      _deploymentMode = DeploymentMode.standby;
      await _updateTrackingMode(service);
    }
  });
}

/// Periodischer Flush: alle 3 Minuten ausstehende Positionen an den Server senden.
/// Skippt komplett wenn die Queue leer ist (kein HTTP, keine Notification).
void _schedulePeriodicFlush(ServiceInstance service) {
  _flushTimer?.cancel();
  _flushTimer = Timer.periodic(const Duration(minutes: 3), (_) async {
    // Ausstehende Statusmeldungen haben Priorität vor GPS-Punkten.
    try {
      if (await StatusSyncManager.instance.pendingCount() > 0) {
        await StatusSyncManager.instance.flushPendingNow();
      }
    } catch (e, st) {
      AppLogger.e('LocationService', 'Status-Flush fehlgeschlagen', e, st);
    }

    // Tägliches DB-Housekeeping auch ohne UI: das Cleanup hing bisher nur
    // am App-Resume — läuft die App wochenlang im Hintergrund, wuchs die
    // GPS-Datenbank unbegrenzt. Gleicher Pref-Key wie der UI-Pfad, damit
    // nicht doppelt aufgeräumt wird.
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCleanup = prefs.getInt(AppPrefsKeys.lastDbCleanupMs) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastCleanup >= const Duration(hours: 24).inMilliseconds) {
        await LocationSyncManager.instance.cleanupOldEntries(maxAgeDays: 30);
        await prefs.setInt(AppPrefsKeys.lastDbCleanupMs, now);
      }
    } catch (e, st) {
      AppLogger.e('LocationService', 'DB-Cleanup fehlgeschlagen', e, st);
    }

    // Guard: nichts zu flushen → kein Wake, keine Notification.
    final stats = await LocationSyncManager.instance.getStats();
    final pending = stats['pending'] ?? 0;
    if (pending == 0) return;

    try {
      await _runFlushGuarded(batchSize: 100);
    } catch (e, st) {
      AppLogger.e('LocationService', 'Periodischer Flush fehlgeschlagen', e, st);
    }
    // Notification aktualisieren mit aktuellem Pending-Count
    await _updateNotificationIfDue(
      service,
      title: 'Trupp App',
      content: await _getNotificationContentAsync(),
    );
  });
}

/// Reentrancy-geschützter Flush: läuft schon einer, sofort raus.
Future<bool> _runFlushGuarded({int batchSize = 100}) async {
  if (_flushInProgress) return false;
  _flushInProgress = true;
  try {
    return await LocationSyncManager.instance.flushPendingNow(batchSize: batchSize);
  } finally {
    _flushInProgress = false;
  }
}

/// Connectivity-Listener: Bei Netzwerk-Wiederherstellung Queue flushen —
/// aber debounced (10 s warten, dann genau einmal feuern) und gegen
/// parallele Flushes geschützt. Vermeidet 200-HTTP-Bursts bei flakiger
/// Verbindung (Tunnel/Aufzug/Funkloch).
void _startConnectivityListener() {
  _connectivitySub?.cancel();
  _connectivitySub = Connectivity().onConnectivityChanged.listen((results) async {
    final hasConnection = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
    if (!hasConnection) {
      _connectivityFlushDebounce?.cancel();
      return;
    }
    // Bestehenden Debounce-Timer ersetzen — bei mehreren Events kurz
    // hintereinander wird so nur der letzte ausgeführt.
    _connectivityFlushDebounce?.cancel();
    _connectivityFlushDebounce =
        Timer(const Duration(seconds: 10), () async {
      try {
        // Zuerst ausstehende Statusmeldungen (wichtiger als GPS-Historie)
        await StatusSyncManager.instance.flushPendingNow();
        await _runFlushGuarded(batchSize: 200);
      } catch (e, st) {
        AppLogger.e('LocationService', 'Connectivity-Flush fehlgeschlagen', e, st);
      }
    });
  });
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  // [DIAG] Läuft im Service-Isolate (erwartet: NICHT "main"). Zeigt außerdem,
  // dass onStart tatsächlich erreicht wird.
  AppLogger.i('DIAG', 'onStart · isolate=${Isolate.current.debugName}');

  await EdpApi.ensureInitialized();

  // Benachrichtigungs-Plugin initialisieren (Foreground-Service-Channel)
  await ForegroundNotificationService.initialize();

  // Alte Event-Subscriptions aufräumen, falls onStart im selben Isolate
  // erneut läuft — verhindert doppelte Handler.
  for (final s in _serviceEventSubs) {
    s.cancel();
  }
  _serviceEventSubs.clear();

  await _loadTrackingPrefs();
  _currentStatus = await _readStatusFromPrefs();
  _deploymentMode = await DeploymentState.getMode();
  _trackingMode = await AdaptiveLocationSettings.determineMode(
    deployment: _deploymentMode,
    currentStatus: _currentStatus,
  );
  _applyQualityThresholds(_trackingMode);

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
  }
  await _updateNotificationIfDue(
    service,
    title: 'Trupp App',
    content: _getNotificationContent(),
    force: true,
  );

  // Status-Änderungen lauschen
  _serviceEventSubs.add(service.on('statusChanged').listen((event) async {
    final s = event?['status'];
    if (s is int) {
      _currentStatus = s;
      await DeploymentState.updateActivity();
      await _updateTrackingMode(service);

      // Status-Wechsel ist sichtbare User-Aktion → force.
      await _updateNotificationIfDue(
        service,
        title: 'Trupp App',
        content: _getNotificationContent(),
        force: true,
      );
    }
  }));

  // Deployment-Modus-Änderungen lauschen
  _serviceEventSubs.add(service.on('updateDeploymentMode').listen((event) async {
    final mode = event?['mode'] as String?;
    if (mode != null) {
      _deploymentMode = DeploymentMode.values.firstWhere(
            (e) => e.name == mode,
        orElse: () => DeploymentMode.standby,
      );
      await _updateTrackingMode(service);

      // Deployment-Wechsel (Einsatz ↔ Bereitschaft) → force.
      await _updateNotificationIfDue(
        service,
        title: 'Trupp App',
        content: _getNotificationContent(),
        force: true,
      );
    }
  }));

  StreamSubscription<Position>? sub;
  bool trackingEnabled = false;
  Timer? streamRecovery;
  int streamRestartAttempts = 0;

  // Zentraler, selbstheilender GPS-Stream + Recovery-Planer.
  //
  // Auf Android teilen sich mehrere Flutter-Engines (Haupt-UI + Background-
  // Service) denselben nativen Geolocator-Location-Service. Dabei kann der
  // Positions-Stream einzelner Engines beendet werden ("position updates
  // stopped … another flutter engine connected"). Bisher wurden onError
  // verschluckt und onDone gar nicht behandelt – der Stream blieb dann still
  // stehen und es wurden keine Positionen mehr gesendet. Jetzt wird der Stream
  // bei Fehler/Ende, solange getrackt werden soll, mit Backoff neu aufgesetzt.
  //
  // Als `late`-Closures deklariert, weil sie sich gegenseitig referenzieren
  // (Stream → Recovery → Stream); die Auflösung erfolgt so erst zur Laufzeit.
  late final Future<void> Function() startPositionStream;
  late final void Function() scheduleStreamRecovery;

  startPositionStream = () async {
    await sub?.cancel();
    sub = null;
    streamRecovery?.cancel();

    if (!await _hasValidConfig()) return;

    final locationSettings = AdaptiveLocationSettings.buildSettings(_trackingMode);
    sub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (pos) async {
        streamRestartAttempts = 0; // gesunder Stream → Backoff zurücksetzen
        await _sendPositionIfOk(service, pos);
      },
      onError: (e, StackTrace st) {
        AppLogger.w('LocationService', 'GPS-Stream-Fehler – Neuaufbau geplant', e);
        scheduleStreamRecovery();
      },
      onDone: () {
        // Stream durch Engine-Churn beendet → neu aufsetzen, falls noch aktiv.
        if (trackingEnabled) scheduleStreamRecovery();
      },
      cancelOnError: false,
    );
  };

  // Plant einen Stream-Neuaufbau mit exponentiellem Backoff (1…30 s).
  scheduleStreamRecovery = () {
    if (!trackingEnabled) return;
    streamRestartAttempts =
        streamRestartAttempts >= 6 ? 6 : streamRestartAttempts + 1;
    final secs = 1 << (streamRestartAttempts - 1); // 1,2,4,8,16,32
    final delay = Duration(seconds: secs > 30 ? 30 : secs);
    streamRecovery?.cancel();
    streamRecovery = Timer(delay, () async {
      if (trackingEnabled) await startPositionStream();
    });
  };

  /// Startet den GPS-Stream mit aktuellen Einstellungen neu (Mode-Wechsel).
  Future<void> _restartStream() async {
    await startPositionStream();
  }

  // Callback registrieren, damit _updateTrackingMode den Stream neu starten kann
  _restartStreamCallback = _restartStream;

  /// Startet oder aktualisiert den GPS-Stream mit aktuellen Einstellungen
  Future<void> startTracking() async {
    AppLogger.i('DIAG',
        'startTracking aufgerufen · validConfig=${await _hasValidConfig()}');
    if (!await _hasValidConfig()) {
      await _updateNotificationIfDue(
        service,
        title: 'Trupp App',
        content: 'Keine gültige Konfiguration',
        force: true,
      );
      return;
    }

    await _ensureFullAccuracyIfPossible();
    await _updateTrackingMode(service);

    // Initialen Pending-Count laden, damit die Notification beim ersten
    // Update nicht „0 ausstehend" zeigt, obwohl die Queue schon Einträge
    // aus einem vorherigen Service-Lauf hat.
    try {
      final stats = await LocationSyncManager.instance.getStats();
      _lastPendingCount = stats['pending'] ?? 0;
    } catch (_) {}

    trackingEnabled = true;
    streamRestartAttempts = 0;
    // Nur starten, wenn noch kein Stream läuft. Einen echten Mode-Wechsel hat
    // _updateTrackingMode oben bereits behandelt (Stream neu gestartet); ein
    // wiederholtes setTracking(true) darf den laufenden Stream NICHT abreißen —
    // sonst entsteht ein Geolocator-Stop/Start-Karussell.
    if (sub == null) {
      await startPositionStream();
    }

    _scheduleNextHeartbeat(service);
    _schedulePeriodicModeCheck(service);
    _schedulePeriodicFlush(service);
    _startConnectivityListener();
  }

  /// Wechselt in den Energiesparmodus statt komplett zu stoppen.
  /// GPS bleibt aktiv mit reduzierter Frequenz.
  Future<void> switchToPowerSaver() async {
    _trackingMode = TrackingMode.powerSaver;
    trackingEnabled = true;
    streamRestartAttempts = 0;

    // Stream mit neuen (sparsamen) Einstellungen neu starten (selbstheilend)
    await startPositionStream();

    // Timer sicherstellen (falls noch nicht gestartet)
    _scheduleNextHeartbeat(service);
    _schedulePeriodicModeCheck(service);
    _schedulePeriodicFlush(service);
    _startConnectivityListener();

    await _updateNotificationIfDue(
      service,
      title: 'Trupp App',
      content: 'Hintergrund-Tracking (Status $_currentStatus) - Energiesparmodus',
      force: true,
    );
  }

  Future<void> stopTracking() async {
    if (!trackingEnabled) return;
    trackingEnabled = false;

    streamRecovery?.cancel();
    streamRecovery = null;
    streamRestartAttempts = 0;

    await sub?.cancel();
    sub = null;

    _hbTimer?.cancel();
    _hbTimer = null;

    _modeCheckTimer?.cancel();
    _modeCheckTimer = null;

    _flushTimer?.cancel();
    _flushTimer = null;

    _connectivitySub?.cancel();
    _connectivitySub = null;
    _connectivityFlushDebounce?.cancel();
    _connectivityFlushDebounce = null;

    await _updateNotificationIfDue(
      service,
      title: 'Trupp App',
      content: 'Standby (Status $_currentStatus)',
      force: true,
    );
  }

  // Tracking-Einstellungen (Frequenz / nur präziser Standort) wurden in den
  // App-Einstellungen geändert → neu laden und sofort anwenden.
  _serviceEventSubs.add(service.on('updateTrackingPrefs').listen((_) async {
    await _loadTrackingPrefs();
    _applyQualityThresholds(_trackingMode);
    // Stream mit neuen Intervallen/Distanzfiltern neu aufsetzen und
    // Heartbeat-Takt aktualisieren.
    if (_restartStreamCallback != null) {
      await _restartStreamCallback!();
    }
    _scheduleNextHeartbeat(service);
    await _updateNotificationIfDue(
      service,
      title: 'Trupp App',
      content: _getNotificationContent(),
      force: true,
    );
  }));

  _serviceEventSubs.add(service.on('setTracking').listen((event) async {
    final enabled = event?['enabled'] == true;
    if (enabled) {
      await startTracking();
    } else {
      // Statt komplett stoppen: auf Power-Saver wechseln
      // Damit wird auch im Hintergrund weiter getrackt
      await switchToPowerSaver();
    }
  }));

  _serviceEventSubs.add(service.on('stopService').listen((_) async {
    await stopTracking();
    // Event-Listener canceln — der Service stoppt, alte Handler dürfen bei
    // einem späteren Neustart nicht weiterleben.
    for (final s in _serviceEventSubs) {
      s.cancel();
    }
    _serviceEventSubs.clear();
    await service.stopSelf();
  }));

  // Tracking nur starten wenn vom Nutzer explizit aktiviert
  // (verhindert Auto-Start nach Neustart)
  if (await _hasValidConfig()) {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(AppPrefsKeys.transmissionEnabled) ?? false) {
      await startTracking();
    }
  }
}

const _flushInterval = Duration(minutes: 5);

Future<bool> _shouldFlushNow() async {
  final prefs = await SharedPreferences.getInstance();
  final last = prefs.getInt(AppPrefsKeys.lastFlushMs) ?? 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  return (now - last) >= _flushInterval.inMilliseconds;
}

Future<void> _markFlushedNow() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(AppPrefsKeys.lastFlushMs, DateTime.now().millisecondsSinceEpoch);
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  try {
    DartPluginRegistrant.ensureInitialized();
    WidgetsFlutterBinding.ensureInitialized();
    await EdpApi.ensureInitialized();

    if (!await _hasValidConfig()) return true;

    await _loadTrackingPrefs();
    _deploymentMode = await DeploymentState.getMode();
    _currentStatus = await _readStatusFromPrefs();
    _trackingMode = await AdaptiveLocationSettings.determineMode(
      deployment: _deploymentMode,
      currentStatus: _currentStatus,
    );
    _applyQualityThresholds(_trackingMode);

    // 1) aktuellen Fix holen — iOS BG-Fetch hat ~30 s Budget, daher hartes
    // Timeout, sonst killt iOS den Task und wir verlieren auch den Flush.
    Position? pos = await Geolocator.getLastKnownPosition();
    pos ??= await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: AdaptiveLocationSettings.getOneShotAccuracy(_trackingMode),
        timeLimit: const Duration(seconds: 15),
      ),
    );

    // 2) Qualität prüfen & direkt senden (nicht nur queuen)
    if (_quality.isGood(pos, now: DateTime.now(), forceByHeartbeat: true)) {
      await LocationSyncManager.instance.sendOrQueue(
        lat: pos.latitude,
        lon: pos.longitude,
        accuracy: pos.accuracy.isFinite ? pos.accuracy : null,
        status: _currentStatus,
        timestamp: pos.timestamp,
      );
      _quality.markSent(pos, now: DateTime.now());
    }

    // 3) Ausstehende Statusmeldungen IMMER nachsenden (klein & kritisch),
    // GPS-Historie nur alle 5 Min (kann groß sein, iOS-Budget ~30 s).
    await StatusSyncManager.instance.flushPendingNow();
    if (await _shouldFlushNow()) {
      await LocationSyncManager.instance.flushPendingNow(batchSize: 300);
      await _markFlushedNow();
    }
  } catch (e, st) {
    AppLogger.e('iOSBackground', 'iOS-Hintergrundhandler fehlgeschlagen', e, st);
  }
  return true;
}

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      foregroundServiceNotificationId: 880,
      // Eigener Low-Importance-Channel (in ForegroundNotificationService
      // .initialize angelegt) — stumm, keine Lockscreen-Pops, klar erkennbarer
      // Name in Android-Einstellungen statt generisch "Background Service".
      notificationChannelId: kForegroundChannelId,
      initialNotificationTitle: 'Trupp App',
      initialNotificationContent: 'Bereitschaft',
      // Android 14+ verlangt explizite Foreground-Service-Typen. Wir sind
      // ein location-tracker (siehe AndroidManifest).
      foregroundServiceTypes: const [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

/// Optionaler Helper für UI-Code
Future<void> stopBackgroundServiceCompletely() async {
  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke('setTracking', {'enabled': false});
    service.invoke('stopService');
  }
}
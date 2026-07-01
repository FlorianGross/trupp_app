// lib/data/location_sync_manager.dart
import 'dart:async';
import 'dart:math';
import 'package:trupp_app/data/edp_api.dart';
import 'package:trupp_app/data/location_queue.dart';

class LocationSyncManager {
  static LocationSyncManager? _instance;
  static LocationSyncManager get instance => _instance ??= LocationSyncManager._();
  LocationSyncManager._();

  final LocationQueue _queue = LocationQueue.instance;

  /// Ablauf mit intelligentem Batching:
  /// 1) Aktuellen Fix IMMER in DB schreiben (Historie).
  /// 2) Pending flushen nur wenn sinnvoll (wichtiger Status oder genug Punkte).
  /// 3) Wenn möglich: aktuellen Fix online senden und als sent markieren.
  Future<void> sendOrQueue({
    required double lat,
    required double lon,
    double? accuracy,
    int? status,
    DateTime? timestamp,
  }) async {
    final ts = timestamp?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;

    // API für dieses Isolate sicherstellen
    final api = await EdpApi.ensureInitialized();

    // 1) Aktuellen Fix protokollieren (single write)
    final id = await _queue.insert(
      LocationFix(tsMs: ts, lat: lat, lon: lon, acc: accuracy, status: status, isSent: false),
    );

    // Wenn API fehlt, nur queuen
    if (api == null) return;

    // 2) Intelligentes Batching: Nur senden wenn:
    //    - Wichtiger Status (0=Dringend, 3=Auftrag, 7=Transport, 9=Sonstiges) ODER
    //    - Genug Punkte für effizientes Batch (>=10)
    final pendingCount = await _queue.pendingCount();

    final isImportantStatus = status != null && [0, 3, 7, 9].contains(status);
    final hasEnoughForBatch = pendingCount >= 10;

    if (isImportantStatus || hasEnoughForBatch) {
      // Batch-Größe begrenzen für Performance
      final batchSize = min(pendingCount, 50);
      await _flushPendingInternal(api, batchSize: batchSize);
    } else {
      // Nur den aktuellen Fix senden, Rest bleibt pending
      try {
        final res = await api.sendGps(lat: lat, lon: lon);
        if (res.ok) {
          await _queue.markSentByIds([id], sentAtMs: DateTime.now().millisecondsSinceEpoch);
        }
      } catch (_) {
        // Bleibt pending
      }
    }
  }

  /// Nur queuen ohne zu senden (für iOS Background)
  Future<int> queueOnly({
    required double lat,
    required double lon,
    double? accuracy,
    int? status,
    DateTime? timestamp,
  }) async {
    final ts = timestamp?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
    return await _queue.insert(
      LocationFix(tsMs: ts, lat: lat, lon: lon, acc: accuracy, status: status, isSent: false),
    );
  }

  /// Manueller Trigger von außen (z.B. bei Netzwerk-Wiederherstellung)
  Future<bool> flushPendingNow({int batchSize = 200}) async {
    final api = await EdpApi.ensureInitialized();
    if (api == null) return false;
    return _flushPendingInternal(api, batchSize: batchSize);
  }

  /// Ab dieser Backlog-Größe wird beim Flush ausgedünnt: Punkte, die
  /// weniger als [_thinningMinDistanceM] vom zuletzt gesendeten entfernt
  /// sind, werden übersprungen statt einzeln per HTTP gesendet. Sie bleiben
  /// in der DB erhalten (GPX-Export liest alle Zeilen), werden aber als
  /// erledigt markiert. Punkte mit wichtigem Status (0, 3, 7, 9) werden
  /// nie übersprungen.
  static const _thinningThreshold = 100;
  static const _thinningMinDistanceM = 15.0;
  static const _importantStatuses = [0, 3, 7, 9];

  /// Interner Flush mit Batch-Verarbeitung
  Future<bool> _flushPendingInternal(EdpApi api, {int batchSize = 100}) async {
    int totalSent = 0;
    bool hadError = false;

    // Großer Backlog (z.B. nach langem Funkloch) → ausdünnen statt
    // hunderte fast identische Positionen einzeln zu senden.
    final thinning = await _queue.pendingCount() >= _thinningThreshold;
    LocationFix? lastSent;

    while (true) {
      final batch = await _queue.pendingBatch(limit: batchSize);
      if (batch.isEmpty) break; // Fertig

      final sentIds = <int>[];
      final skippedIds = <int>[];

      // Batch senden (mit kurzer Pause zwischen Requests für Server-Freundlichkeit)
      for (int i = 0; i < batch.length; i++) {
        final fix = batch[i];

        if (thinning &&
            lastSent != null &&
            fix.id != null &&
            !(fix.status != null && _importantStatuses.contains(fix.status)) &&
            _distanceMeters(lastSent.lat, lastSent.lon, fix.lat, fix.lon) <
                _thinningMinDistanceM) {
          skippedIds.add(fix.id!);
          continue;
        }

        try {
          final r = await api.sendGps(lat: fix.lat, lon: fix.lon);
          if (r.ok) {
            if (fix.id != null) sentIds.add(fix.id!);
            totalSent++;
            lastSent = fix;
          } else {
            hadError = true;
            break; // Reihenfolge bewahren - bei Fehler abbrechen
          }

          // Kleine Pause alle 5 Requests um Server nicht zu überlasten
          if ((i + 1) % 5 == 0 && i < batch.length - 1) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        } catch (_) {
          hadError = true;
          break; // Bei Fehler abbrechen
        }
      }

      // Gesendete und übersprungene IDs als erledigt markieren
      final doneIds = [...sentIds, ...skippedIds];
      if (doneIds.isNotEmpty) {
        await _queue.markSentByIds(
          doneIds,
          sentAtMs: DateTime.now().millisecondsSinceEpoch,
        );
      }

      // Bei Fehler oder Ende des Batches stoppen
      if (hadError || doneIds.length < batch.length) {
        return !hadError && doneIds.isNotEmpty;
      }

      // Weiter mit nächstem Batch
      if (doneIds.length == batch.length && batch.length == batchSize) {
        continue; // Es könnten noch mehr pending sein
      } else {
        break; // Fertig
      }
    }

    return totalSent > 0;
  }

  /// Haversine-Distanz in Metern (bewusst ohne Geolocator-Plugin, damit der
  /// Daten-Layer in reinen Dart-Tests läuft).
  static double _distanceMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180.0;

  /// Statistik für UI
  Future<Map<String, int>> getStats() async {
    return {
      'pending': await _queue.pendingCount(),
      'total': await _queue.totalCount(),
    };
  }

  /// Housekeeping: Alte Einträge löschen (älter als X Tage)
  Future<int> cleanupOldEntries({int maxAgeDays = 30}) async {
    return await _queue.purgeOlderThan(Duration(days: maxAgeDays));
  }
}
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

  /// Interner Flush mit Batch-Verarbeitung
  Future<bool> _flushPendingInternal(EdpApi api, {int batchSize = 100}) async {
    int totalSent = 0;
    bool hadError = false;

    while (true) {
      final batch = await _queue.pendingBatch(limit: batchSize);
      if (batch.isEmpty) break; // Fertig

      final sentIds = <int>[];

      // Batch senden (mit kurzer Pause zwischen Requests für Server-Freundlichkeit)
      for (int i = 0; i < batch.length; i++) {
        final fix = batch[i];

        try {
          final r = await api.sendGps(lat: fix.lat, lon: fix.lon);
          if (r.ok) {
            if (fix.id != null) sentIds.add(fix.id!);
            totalSent++;
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

      // Gesendete IDs markieren
      if (sentIds.isNotEmpty) {
        await _queue.markSentByIds(
          sentIds,
          sentAtMs: DateTime.now().millisecondsSinceEpoch,
        );
      }

      // Bei Fehler oder Ende des Batches stoppen
      if (hadError || sentIds.length < batch.length) {
        print('LocationSyncManager: Sent $totalSent positions, stopped ${hadError ? "due to error" : ""}');
        return !hadError && sentIds.isNotEmpty;
      }

      // Weiter mit nächstem Batch
      if (sentIds.length == batch.length && batch.length == batchSize) {
        continue; // Es könnten noch mehr pending sein
      } else {
        break; // Fertig
      }
    }

    print('LocationSyncManager: Flushed $totalSent positions successfully');
    return totalSent > 0;
  }

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
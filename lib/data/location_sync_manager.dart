import 'dart:async';
import 'package:trupp_app/data/edp_api.dart';
import 'package:trupp_app/data/location_queue.dart';

class LocationSyncManager {
  static LocationSyncManager? _instance;
  static LocationSyncManager get instance => _instance ??= LocationSyncManager._();
  LocationSyncManager._();

  final LocationQueue _queue = LocationQueue.instance;

  /// Ablauf:
  /// 1) Pending flushen (nur is_sent=0).
  /// 2) Aktuellen Fix IMMER in DB schreiben (Historie).
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

    // 1) Ältere Pendings zuerst flushen (wenn API fehlt, überspringen wir, aber schreiben den aktuellen Eintrag trotzdem)
    if (api != null) {
      await _flushPendingInternal(api);
    }

    // 2) Aktuellen Fix protokollieren
    final id = await _queue.insert(
      LocationFix(tsMs: ts, lat: lat, lon: lon, acc: accuracy, status: status, isSent: false),
    );

    // 3) Senden & markieren (nur, wenn API vorhanden)
    if (api == null) return;
    try {
      final res = await api.sendGps(lat: lat, lon: lon);
      if (res.ok) {
        await _queue.markSentByIds([id], sentAtMs: DateTime.now().millisecondsSinceEpoch);
      }
      // bei Fehler → bleibt pending
    } catch (_) {
      // bleibt pending
    }
  }

  /// Manueller Trigger von außen
  Future<bool> flushPendingNow({int batchSize = 200}) async {
    final api = await EdpApi.ensureInitialized();
    if (api == null) return false;
    return _flushPendingInternal(api, batchSize: batchSize);
  }

  Future<bool> _flushPendingInternal(EdpApi api, {int batchSize = 100}) async {
    while (true) {
      final batch = await _queue.pendingBatch(limit: batchSize);
      if (batch.isEmpty) return true;

      final sentIds = <int>[];
      for (final fix in batch) {
        try {
          final r = await api.sendGps(lat: fix.lat, lon: fix.lon);
          if (r.ok) {
            if (fix.id != null) sentIds.add(fix.id!);
          } else {
            break; // Reihenfolge bewahren
          }
        } catch (_) {
          break;
        }
      }

      if (sentIds.isEmpty) return false;

      await _queue.markSentByIds(
        sentIds,
        sentAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      if (sentIds.length < batch.length) return false; // Rest beim nächsten Versuch
    }
  }
}
// lib/data/status_sync_manager.dart
//
// Zuverlässiges Status-Senden mit Offline-Queue und In-Flight-Guard.
//
// Probleme, die hier gelöst werden:
//  1. Bisher gingen Statusmeldungen nach 3 fehlgeschlagenen Retries verloren
//     („Status gespeichert (offline)" war eine leere Versprechung).
//  2. Zwei schnell hintereinander gedrückte Status konnten sich im Netz
//     überholen (Status 1 kommt NACH Status 3 beim Server an).
//
// Lösung: Jeder Status wird zuerst in die StatusQueue geschrieben, dann
// streng seriell (ein Send-Vorgang zur Zeit, FIFO) an den Server übertragen.
// Fehlgeschlagene Sends bleiben pending und werden bei den bestehenden
// Flush-Triggern (Connectivity-Restore, periodischer Flush, iOS-Background)
// nachgesendet.
import 'dart:async';

import 'edp_api.dart';
import 'status_queue.dart';

class StatusSyncManager {
  static StatusSyncManager? _instance;
  static StatusSyncManager get instance => _instance ??= StatusSyncManager._();
  StatusSyncManager._();

  final StatusQueue _queue = StatusQueue.instance;

  /// Pending-Status älter als das hier wird beim Flush verworfen statt
  /// nachgesendet — ein 6 h alter Status würde beim Server einen längst
  /// überholten Zustand setzen.
  static const _maxPendingAge = Duration(hours: 6);

  /// Serialisierung: alle Sende-Vorgänge hängen an dieser Future-Kette.
  /// Damit ist garantiert, dass nie zwei sendStatus-Requests parallel laufen
  /// und die Reihenfolge der Queue erhalten bleibt.
  Future<void> _chain = Future.value();

  Future<T> _serialized<T>(Future<T> Function() op) {
    final result = _chain.then((_) => op());
    // Fehler nicht in der Kette halten — der nächste Vorgang soll laufen.
    _chain = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Persistiert [status] und versucht ihn (und alle älteren pending Status)
  /// sofort zu senden. Wirft nie.
  ///
  /// Rückgabe: true wenn der Status den Server erreicht hat, false wenn er
  /// nur gequeued wurde (Offline/Fehler) und automatisch nachgesendet wird.
  Future<bool> sendOrQueue(int status) async {
    await _queue.insert(QueuedStatus(
      tsMs: DateTime.now().millisecondsSinceEpoch,
      status: status,
    ));
    return _serialized(_flushInternal);
  }

  /// Sendet alle pending Status in Originalreihenfolge.
  /// Rückgabe: true wenn die Queue danach leer ist.
  Future<bool> flushPendingNow() => _serialized(_flushInternal);

  Future<int> pendingCount() => _queue.pendingCount();

  Future<bool> _flushInternal() async {
    final api = await EdpApi.ensureInitialized();
    if (api == null) return false;

    await _queue.discardPendingOlderThan(_maxPendingAge);
    await _queue.purgeOlderThan(const Duration(days: 7));

    while (true) {
      final batch = await _queue.pendingBatch(limit: 50);
      if (batch.isEmpty) return true;

      for (final entry in batch) {
        try {
          final res = await api.sendStatus(entry.status);
          if (!res.ok) return false; // bleibt pending, Reihenfolge bewahren
          await _queue.markSentByIds(
            [entry.id!],
            sentAtMs: DateTime.now().millisecondsSinceEpoch,
          );
        } catch (_) {
          return false; // bleibt pending
        }
      }
    }
  }
}

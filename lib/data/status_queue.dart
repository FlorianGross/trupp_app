// lib/data/status_queue.dart
//
// Persistente Warteschlange für Statusmeldungen — analog zur LocationQueue.
// Jeder Statuswechsel wird zuerst hier protokolliert; fehlgeschlagene Sends
// bleiben pending und werden beim nächsten Flush (Connectivity-Restore,
// periodischer Flush, iOS-Background) in Originalreihenfolge nachgesendet.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

@immutable
class QueuedStatus {
  final int? id;       // autoincrement
  final int tsMs;      // epoch ms — Sende-Reihenfolge
  final int status;    // TETRA-Status 0..9

  final bool isSent;
  final int? sentAtMs;

  const QueuedStatus({
    this.id,
    required this.tsMs,
    required this.status,
    this.isSent = false,
    this.sentAtMs,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'ts_ms': tsMs,
        'status': status,
        'is_sent': isSent ? 1 : 0,
        'sent_at_ms': sentAtMs,
      };

  static QueuedStatus fromMap(Map<String, Object?> m) => QueuedStatus(
        id: m['id'] as int?,
        tsMs: m['ts_ms'] as int,
        status: m['status'] as int,
        isSent: ((m['is_sent'] as int?) ?? 0) == 1,
        sentAtMs: m['sent_at_ms'] as int?,
      );
}

class StatusQueue {
  static const _dbName = 'status_queue.db';
  static const _dbVersion = 1;
  static const _table = 'status_queue';
  String? _dbpath;

  static StatusQueue? _instance;
  static StatusQueue get instance => _instance ??= StatusQueue._();

  Database? _db;
  StatusQueue._();

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final base = await getDatabasesPath();
    _dbpath = p.join(base, _dbName);
    _db = await openDatabase(
      _dbpath!,
      version: _dbVersion,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts_ms INTEGER NOT NULL,
            status INTEGER NOT NULL,
            is_sent INTEGER NOT NULL DEFAULT 0,
            sent_at_ms INTEGER
          )
        ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_${_table}_sent_ts ON $_table(is_sent, ts_ms)');
      },
    );
    return _db!;
  }

  Future<int> insert(QueuedStatus s) async {
    final db = await _open();
    return db.insert(_table, s.toMap());
  }

  Future<List<QueuedStatus>> pendingBatch({int limit = 50}) async {
    final db = await _open();
    final rows = await db.query(
      _table,
      where: 'is_sent = 0',
      orderBy: 'ts_ms ASC, id ASC',
      limit: limit,
    );
    return rows.map(QueuedStatus.fromMap).toList();
  }

  Future<void> markSentByIds(List<int> ids, {required int sentAtMs}) async {
    if (ids.isEmpty) return;
    final db = await _open();
    final qMarks = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE $_table SET is_sent = 1, sent_at_ms = ? WHERE id IN ($qMarks)',
      [sentAtMs, ...ids],
    );
  }

  Future<int> pendingCount() async {
    final db = await _open();
    final r = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_table WHERE is_sent = 0'));
    return r ?? 0;
  }

  /// Verwirft ungesendete Einträge, die älter als [maxAge] sind. Ein Status
  /// ist eine Zustandsmeldung — einen viele Stunden alten Status nachzusenden
  /// würde beim Server einen längst überholten Zustand setzen.
  Future<int> discardPendingOlderThan(Duration maxAge) async {
    final db = await _open();
    final cutoff = DateTime.now().millisecondsSinceEpoch - maxAge.inMilliseconds;
    return db.delete(_table, where: 'is_sent = 0 AND ts_ms < ?', whereArgs: [cutoff]);
  }

  /// Housekeeping: gesendete Einträge älter als [maxAge] löschen.
  Future<int> purgeOlderThan(Duration maxAge) async {
    final db = await _open();
    final cutoff = DateTime.now().millisecondsSinceEpoch - maxAge.inMilliseconds;
    return db.delete(_table, where: 'is_sent = 1 AND ts_ms < ?', whereArgs: [cutoff]);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

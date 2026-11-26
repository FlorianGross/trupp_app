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

  /// true, sobald für diesen (verzögerten) Status bereits eine SDS-Nachmeldung
  /// verschickt wurde — verhindert wiederholtes Senden bei jedem Flush.
  final bool sdsNotified;

  /// ISSI, unter der der Status gemeldet wurde. Nach einem Profilwechsel darf
  /// ein noch ausstehender Status der alten Einheit nicht unter der neuen ISSI
  /// gesendet werden. null = Altbestand vor Einführung der Spalte (gilt als
  /// zur aktuellen ISSI gehörig).
  final String? issi;

  const QueuedStatus({
    this.id,
    required this.tsMs,
    required this.status,
    this.isSent = false,
    this.sentAtMs,
    this.sdsNotified = false,
    this.issi,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'ts_ms': tsMs,
        'status': status,
        'is_sent': isSent ? 1 : 0,
        'sent_at_ms': sentAtMs,
        'sds_notified': sdsNotified ? 1 : 0,
        'issi': issi,
      };

  static QueuedStatus fromMap(Map<String, Object?> m) => QueuedStatus(
        id: m['id'] as int?,
        tsMs: m['ts_ms'] as int,
        status: m['status'] as int,
        isSent: ((m['is_sent'] as int?) ?? 0) == 1,
        sentAtMs: m['sent_at_ms'] as int?,
        sdsNotified: ((m['sds_notified'] as int?) ?? 0) == 1,
        issi: m['issi'] as String?,
      );
}

class StatusQueue {
  static const _dbName = 'status_queue.db';
  static const _dbVersion = 3;
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
      onConfigure: (db) async {
        // WAL: crash-sicherer und weniger Lock-Konflikte (siehe LocationQueue).
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA synchronous=NORMAL');
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts_ms INTEGER NOT NULL,
            status INTEGER NOT NULL,
            is_sent INTEGER NOT NULL DEFAULT 0,
            sent_at_ms INTEGER,
            sds_notified INTEGER NOT NULL DEFAULT 0,
            issi TEXT,
            claim_until_ms INTEGER
          )
        ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_${_table}_sent_ts ON $_table(is_sent, ts_ms)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 → v2: Spalte für die SDS-Nachmeldung verzögerter Status ergänzen.
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE $_table ADD COLUMN sds_notified INTEGER NOT NULL DEFAULT 0');
        }
        // v2 → v3: ISSI je Eintrag (Profilwechsel) und Sende-Claim
        // (verhindert Doppelversand aus UI- und Hintergrund-Isolate).
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE $_table ADD COLUMN issi TEXT');
          await db.execute('ALTER TABLE $_table ADD COLUMN claim_until_ms INTEGER');
        }
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
      'UPDATE $_table SET is_sent = 1, sent_at_ms = ?, claim_until_ms = NULL '
      'WHERE id IN ($qMarks)',
      [sentAtMs, ...ids],
    );
  }

  Future<int> pendingCount() async {
    final db = await _open();
    final r = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_table WHERE is_sent = 0'));
    return r ?? 0;
  }

  /// Beansprucht den Eintrag [id] exklusiv für einen Sendeversuch.
  ///
  /// UI- und Hintergrund-Isolate haben je eine eigene StatusSyncManager-
  /// Instanz; deren Future-Kette serialisiert nur innerhalb eines Isolates.
  /// Ohne diesen Claim könnten beide denselben Status gleichzeitig senden
  /// (doppelte Meldung in der Leitstelle). Das UPDATE ist in SQLite atomar —
  /// nur ein Aufrufer bekommt die Zeile. Der Claim läuft nach [lease] ab, damit
  /// ein während des Sendens beendeter Prozess den Eintrag nicht dauerhaft
  /// blockiert.
  ///
  /// Rückgabe: true, wenn der Aufrufer den Eintrag jetzt senden darf.
  Future<bool> tryClaim(int id, {required Duration lease, int? nowMs}) async {
    final db = await _open();
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final changed = await db.rawUpdate(
      'UPDATE $_table SET claim_until_ms = ? '
      'WHERE id = ? AND is_sent = 0 '
      'AND (claim_until_ms IS NULL OR claim_until_ms < ?)',
      [now + lease.inMilliseconds, id, now],
    );
    return changed == 1;
  }

  /// Gibt einen Claim nach einem fehlgeschlagenen Sendeversuch wieder frei,
  /// damit der nächste Flush (egal aus welchem Isolate) es erneut versucht.
  Future<void> releaseClaim(int id) async {
    final db = await _open();
    await db.update(_table, {'claim_until_ms': null},
        where: 'id = ? AND is_sent = 0', whereArgs: [id]);
  }

  /// true, wenn der Eintrag [id] als gesendet markiert ist.
  Future<bool> isSent(int id) async {
    final db = await _open();
    final rows = await db.query(_table,
        columns: ['is_sent'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return false;
    return ((rows.first['is_sent'] as int?) ?? 0) == 1;
  }

  /// Verwirft ausstehende Einträge, die unter einer anderen ISSI als
  /// [currentIssi] gemeldet wurden (Profilwechsel). Einträge ohne ISSI
  /// (Altbestand) bleiben erhalten.
  Future<int> discardPendingForOtherIssi(String currentIssi) async {
    final db = await _open();
    return db.delete(_table,
        where: 'is_sent = 0 AND issi IS NOT NULL AND issi != ?',
        whereArgs: [currentIssi]);
  }

  /// Markiert, dass für diesen Eintrag bereits eine SDS-Nachmeldung
  /// verschickt wurde.
  Future<void> markSdsNotified(int id) async {
    final db = await _open();
    await db.update(_table, {'sds_notified': 1},
        where: 'id = ?', whereArgs: [id]);
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

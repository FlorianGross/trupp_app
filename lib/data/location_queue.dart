// lib/data/location_queue.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

@immutable
class LocationFix {
  final int? id;              // autoincrement
  final int tsMs;             // epoch ms - Sende-Reihenfolge
  final double lat;
  final double lon;
  final double? acc;          // optional: accuracy (m)
  final int? status;          // optional: Status zum Zeitpunkt der Messung

  final bool isSent;
  final int? sentAtMs;

  /// ISSI, unter der die Position erfasst wurde (siehe QueuedStatus.issi).
  /// null = Altbestand, gilt als zur aktuellen ISSI gehörig.
  final String? issi;

  const LocationFix({
    this.id,
    required this.tsMs,
    required this.lat,
    required this.lon,
    this.acc,
    this.status,
    this.isSent = false,
    this.sentAtMs,
    this.issi,
  });

  LocationFix copyWith({
    int? id,
    int? tsMs,
    double? lat,
    double? lon,
    double? acc,
    int? status,
    bool? isSent,
    int? sentAtMs,
    String? issi,
  }) =>
      LocationFix(
        id: id ?? this.id,
        tsMs: tsMs ?? this.tsMs,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        acc: acc ?? this.acc,
        status: status ?? this.status,
        isSent: isSent ?? this.isSent,
        sentAtMs: sentAtMs ?? this.sentAtMs,
        issi: issi ?? this.issi,
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'ts_ms': tsMs,
    'lat': lat,
    'lon': lon,
    'acc': acc,
    'status': status,
    'is_sent': isSent ? 1 : 0,
    'sent_at_ms': sentAtMs,
    'issi': issi,
  };

  static LocationFix fromMap(Map<String, Object?> m) => LocationFix(
    id: m['id'] as int?,
    tsMs: m['ts_ms'] as int,
    lat: (m['lat'] as num).toDouble(),
    lon: (m['lon'] as num).toDouble(),
    acc: (m['acc'] as num?)?.toDouble(),
    status: m['status'] as int?,
    isSent: ((m['is_sent'] as int?) ?? 0) == 1,
    sentAtMs: m['sent_at_ms'] as int?,
    issi: m['issi'] as String?,
  );
}

class LocationQueue {
  static const _dbName = 'location_queue.db';
  static const _dbVersion = 3;
  static const _table = 'location_queue';
  String? _dbpath;

  static LocationQueue? _instance;
  static LocationQueue get instance => _instance ??= LocationQueue._();

  Database? _db;
  LocationQueue._();

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final base = await getDatabasesPath();
    _dbpath = p.join(base, _dbName);
    _db = await openDatabase(
      _dbpath!,
      version: _dbVersion,
      onConfigure: (db) async {
        // WAL: robuster gegen Abstürze und deutlich weniger „database is
        // locked" bei parallelem Insert (Stream) und Flush (Timer). NORMAL
        // ist mit WAL crash-sicher und schneller als FULL.
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA synchronous=NORMAL');
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts_ms INTEGER NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            acc REAL,
            status INTEGER,
            is_sent INTEGER NOT NULL DEFAULT 0,
            sent_at_ms INTEGER,
            issi TEXT
          )
        ''');
        // Sendeeffizienz: Index auf ts_ms
        await db.execute('CREATE INDEX IF NOT EXISTS idx_${_table}_ts ON $_table(ts_ms)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_${_table}_sent_ts ON $_table(is_sent, ts_ms)');
      },
      onUpgrade: (db, old, _) async {
        if (old < 2) {
          await db.execute('ALTER TABLE $_table ADD COLUMN is_sent INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE $_table ADD COLUMN sent_at_ms INTEGER');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_${_table}_sent_ts ON $_table(is_sent, ts_ms)');
        }
        // v2 → v3: ISSI je Position, damit nach einem Profilwechsel nichts
        // unter der falschen Einheit nachgesendet wird.
        if (old < 3) {
          await db.execute('ALTER TABLE $_table ADD COLUMN issi TEXT');
        }
      },
    );
    return _db!;
  }

  // ——— Einfügen ———
  Future<int> insert(LocationFix fix) async {
    final db = await _open();
    return db.insert(_table, fix.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ——— Pending lesen (nur is_sent = 0) ———
  Future<List<LocationFix>> pendingBatch({int limit = 100}) async {
    final db = await _open();
    final rows = await db.query(
      _table,
      where: 'is_sent = 0',
      orderBy: 'ts_ms ASC, id ASC',
      limit: limit,
    );
    return rows.map(LocationFix.fromMap).toList();
  }

  // ——— Alle (für Export) ———
  Future<List<LocationFix>> all() async {
    final db = await _open();
    final rows = await db.query(_table, orderBy: 'ts_ms ASC, id ASC');
    return rows.map(LocationFix.fromMap).toList();
  }

  // ——— Zeitbereich (für Einsatz-Export) ———
  Future<List<LocationFix>> byTimeRange({required int fromMs, required int toMs}) async {
    final db = await _open();
    final rows = await db.query(
      _table,
      where: 'ts_ms >= ? AND ts_ms <= ?',
      whereArgs: [fromMs, toMs],
      orderBy: 'ts_ms ASC, id ASC',
    );
    return rows.map(LocationFix.fromMap).toList();
  }

  // ——— Flags setzen nach erfolgreichem Versand ———
  Future<void> markSentByIds(List<int> ids, {required int sentAtMs}) async {
    if (ids.isEmpty) return;
    final db = await _open();
    final qMarks = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE $_table SET is_sent = 1, sent_at_ms = ? WHERE id IN ($qMarks)',
      [sentAtMs, ...ids],
    );
  }

  /// Nimmt ausstehende Positionen einer anderen ISSI als [currentIssi] aus der
  /// Übertragung (Profilwechsel). Sie bleiben für Karte/GPX-Export in der DB,
  /// werden aber nicht mehr gesendet (is_sent = 1, sent_at_ms = NULL heißt
  /// „nicht übertragen, verworfen"). Altbestand ohne ISSI bleibt pending.
  Future<int> retirePendingForOtherIssi(String currentIssi) async {
    final db = await _open();
    return db.rawUpdate(
      'UPDATE $_table SET is_sent = 1, sent_at_ms = NULL '
      'WHERE is_sent = 0 AND issi IS NOT NULL AND issi != ?',
      [currentIssi],
    );
  }

  // ——— Zähler ———
  Future<int> pendingCount() async {
    final db = await _open();
    final r = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $_table WHERE is_sent = 0'));
    return r ?? 0;
  }

  Future<int> totalCount() async {
    final db = await _open();
    final r = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $_table'));
    return r ?? 0;
  }

  // Housekeeping (optional): alles > X Tage löschen
  Future<int> purgeOlderThan(Duration maxAge) async {
    final db = await _open();
    final cutoff = DateTime.now().millisecondsSinceEpoch - maxAge.inMilliseconds;
    return db.delete(_table, where: 'ts_ms < ?', whereArgs: [cutoff]);
  }

  /// Harte Obergrenze gegen unbegrenztes Wachstum (z. B. langer Server-
  /// Ausfall): überzählige Zeilen löschen, **gesendete zuerst** (die sind schon
  /// übertragen), dann die ältesten. Gibt die Anzahl gelöschter Zeilen zurück.
  Future<int> capRows({required int maxTotal}) async {
    if (maxTotal <= 0) return 0;
    final db = await _open();
    final total = await totalCount();
    if (total <= maxTotal) return 0;
    final excess = total - maxTotal;
    return db.rawDelete(
      '''
      DELETE FROM $_table WHERE id IN (
        SELECT id FROM $_table
        ORDER BY is_sent DESC, ts_ms ASC, id ASC
        LIMIT ?
      )
      ''',
      [excess],
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> deleteAll() async {
    final db = await _open();
    await db.delete(_table);
  }

  Future<void> destroyDb() async {
    await _db?.close();
    _db = null;
    if (_dbpath != null) {
      await deleteDatabase(_dbpath!);
    }
  }
}
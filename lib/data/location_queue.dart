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

  const LocationFix({
    this.id,
    required this.tsMs,
    required this.lat,
    required this.lon,
    this.acc,
    this.status,
    this.isSent = false,
    this.sentAtMs,
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
  );
}

class LocationQueue {
  static const _dbName = 'location_queue.db';
  static const _dbVersion = 2;
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
            sent_at_ms INTEGER
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
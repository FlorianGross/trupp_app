// Prüft das Upgrade bestehender Installationen (DB-Version 2) auf Version 3
// (Spalten issi/claim_until_ms): ausstehende Einträge dürfen dabei nicht
// verloren gehen und müssen danach weiter gesendet werden können.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trupp_app/data/location_queue.dart';
import 'package:trupp_app/data/status_queue.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('queue_migration_test');
    await databaseFactory.setDatabasesPath(tempDir.path);

    // Schema v2 der StatusQueue, wie es auf Geräten liegt.
    final statusDb = await openDatabase(
      p.join(tempDir.path, 'status_queue.db'),
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE status_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts_ms INTEGER NOT NULL,
            status INTEGER NOT NULL,
            is_sent INTEGER NOT NULL DEFAULT 0,
            sent_at_ms INTEGER,
            sds_notified INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.insert('status_queue', {
          'ts_ms': DateTime.now().millisecondsSinceEpoch,
          'status': 3,
        });
      },
    );
    await statusDb.close();

    // Schema v2 der LocationQueue.
    final locDb = await openDatabase(
      p.join(tempDir.path, 'location_queue.db'),
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE location_queue (
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
        await db.insert('location_queue', {
          'ts_ms': 1,
          'lat': 52.0,
          'lon': 13.0,
        });
      },
    );
    await locDb.close();
  });

  tearDownAll(() async {
    await StatusQueue.instance.close();
    await LocationQueue.instance.close();
    await tempDir.delete(recursive: true);
  });

  test('StatusQueue v2 → v3: Eintrag bleibt pending, Claim funktioniert',
      () async {
    final batch = await StatusQueue.instance.pendingBatch();
    expect(batch.single.status, 3);
    expect(batch.single.issi, isNull);

    // Altbestand ohne ISSI wird bei einem Profilwechsel nicht verworfen.
    expect(await StatusQueue.instance.discardPendingForOtherIssi('x'), 0);

    final id = batch.single.id!;
    expect(
        await StatusQueue.instance
            .tryClaim(id, lease: const Duration(minutes: 3)),
        true);
  });

  test('LocationQueue v2 → v3: Position bleibt pending', () async {
    final pending = await LocationQueue.instance.pendingBatch();
    expect(pending.single.lat, 52.0);
    expect(pending.single.issi, isNull);
    expect(await LocationQueue.instance.retirePendingForOtherIssi('x'), 0);
  });
}

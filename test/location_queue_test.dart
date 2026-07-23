import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trupp_app/data/location_queue.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('location_queue_test');
    await databaseFactory.setDatabasesPath(tempDir.path);
  });

  tearDownAll(() async {
    await LocationQueue.instance.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await LocationQueue.instance.deleteAll();
  });

  LocationFix fix(int ts, {bool sent = false}) =>
      LocationFix(tsMs: ts, lat: 52.0, lon: 13.0, isSent: sent);

  test('capRows ist No-Op unterhalb der Grenze', () async {
    await LocationQueue.instance.insert(fix(1));
    await LocationQueue.instance.insert(fix(2));
    final deleted = await LocationQueue.instance.capRows(maxTotal: 10);
    expect(deleted, 0);
    expect(await LocationQueue.instance.totalCount(), 2);
  });

  test('capRows löscht die Überzahl, gesendete zuerst', () async {
    for (var i = 0; i < 3; i++) {
      await LocationQueue.instance.insert(fix(100 + i, sent: true));
    }
    for (var i = 0; i < 3; i++) {
      await LocationQueue.instance.insert(fix(200 + i, sent: false));
    }
    expect(await LocationQueue.instance.totalCount(), 6);

    // Auf 4 kappen → 2 löschen: die (älteren) gesendeten zuerst.
    final deleted = await LocationQueue.instance.capRows(maxTotal: 4);
    expect(deleted, 2);
    expect(await LocationQueue.instance.totalCount(), 4);
    // Alle ausstehenden bleiben erhalten (nur Gesendete wurden geopfert).
    expect(await LocationQueue.instance.pendingCount(), 3);
  });

  test('markSentByIds nimmt Punkte aus pending', () async {
    final id1 = await LocationQueue.instance.insert(fix(1));
    await LocationQueue.instance.insert(fix(2));
    expect(await LocationQueue.instance.pendingCount(), 2);
    await LocationQueue.instance.markSentByIds([id1], sentAtMs: 999);
    expect(await LocationQueue.instance.pendingCount(), 1);
    expect(await LocationQueue.instance.totalCount(), 2);
  });
}
